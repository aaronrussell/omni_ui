defmodule OmniUI.TitleService do
  @moduledoc """
  Auto-generates titles for untitled `Omni.Session` processes.

  The service is a singleton GenServer that subscribes to an
  `Omni.Session.Manager` and watches for sessions opened without a
  title. For each such session it observes the agent stream and, once
  the next turn commits, calls `OmniUI.Title.generate/3` and writes the
  result back via `Omni.Session.set_title/2`.

  The trigger for generation is the `:turn, {:stop, _}` session event,
  and the messages passed to generation come from the post-commit
  snapshot, so the service works regardless of which LiveView (if any)
  is currently driving the session.

  ## Configuration

  Add the service after the Manager in your application supervision
  tree:

      children = [
        OmniUI.Sessions,
        OmniUI.TitleService,
        # ...
      ]

      # config/config.exs
      config :omni_ui, OmniUI.TitleService,
        manager: OmniUI.Sessions,
        model: {:anthropic, "claude-haiku-4-5"}

  Options:

    * `:manager` — `Omni.Session.Manager` module to track. Defaults to
      `OmniUI.Sessions`.
    * `:model` — `Omni.Model.ref()` tuple. When set, used for LLM-based
      title generation. When omitted (or `nil`), generation falls back
      to a heuristic — see `OmniUI.Title.generate/3`.

  Start opts override app env.

  ## Behaviour

    * Subscribes to running, untitled sessions as `:observer` (no
      lifetime pinning).
    * Generates one title per session per `:turn, {:stop, _}` cycle;
      duplicates while a generation is in flight are ignored.
    * Stops watching a session as soon as a non-nil title is set
      (whether by us, by a user, or by another process).
    * Re-subscribes if a session's title is later cleared back to
      `nil`, so a manual clear re-enables auto-generation on the next
      turn.
    * Generation failures keep the subscription open — the next turn
      retries.
  """

  use GenServer
  require Logger

  alias OmniUI.Title
  alias Omni.Session
  alias Omni.Session.Manager

  defstruct manager: nil,
            model: nil,
            pending: %{},
            task_refs: %{},
            session_refs: %{}

  # ── Public API ─────────────────────────────────────────────────────

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Starts the title service.

  Accepts the same `:manager` and `:model` options as the app-env
  config. Start opts win over app env. Pass `:name` to override the
  registered name (defaults to the module name); useful when running
  multiple managers or in tests.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # ── GenServer ──────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    config = resolve_config(opts)
    state = %__MODULE__{manager: config.manager, model: config.model}

    case Manager.subscribe(state.manager) do
      {:ok, entries} ->
        state =
          Enum.reduce(entries, state, fn entry, acc ->
            if is_nil(entry.title), do: track(acc, entry.id, entry.pid), else: acc
          end)

        {:ok, state}
    end
  end

  @impl true
  def handle_info({:manager, _mod, :opened, %{id: id, title: nil, pid: pid}}, state) do
    state = if Map.has_key?(state.pending, id), do: state, else: track(state, id, pid)
    {:noreply, state}
  end

  def handle_info({:manager, _mod, :opened, _entry}, state), do: {:noreply, state}

  def handle_info({:manager, _mod, :title, %{id: id, title: nil}}, state) do
    state =
      if Map.has_key?(state.pending, id) do
        state
      else
        case Manager.whereis(state.manager, id) do
          nil -> state
          pid -> track(state, id, pid)
        end
      end

    {:noreply, state}
  end

  def handle_info({:manager, _mod, :title, %{id: id, title: _}}, state) do
    {:noreply, untrack(state, id)}
  end

  def handle_info({:manager, _mod, :closed, %{id: id}}, state) do
    {:noreply, untrack(state, id)}
  end

  def handle_info({:manager, _mod, :status, _}, state), do: {:noreply, state}

  def handle_info({:session, pid, :turn, {:stop, _response}}, state) do
    case find_by_pid(state, pid) do
      nil -> {:noreply, state}
      {id, %{task: nil}} -> {:noreply, start_generation(state, id, pid)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:session, _pid, _type, _data}, state), do: {:noreply, state}

  def handle_info({ref, {:ok, title}}, state) when is_reference(ref) do
    case Map.pop(state.task_refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {id, task_refs} ->
        Process.demonitor(ref, [:flush])
        state = %{state | task_refs: task_refs}

        case Map.get(state.pending, id) do
          nil ->
            {:noreply, state}

          %{pid: pid} ->
            try do
              Session.set_title(pid, title)
            catch
              :exit, _ -> :ok
            end

            {:noreply, untrack(state, id)}
        end
    end
  end

  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    case Map.pop(state.task_refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {id, task_refs} ->
        Process.demonitor(ref, [:flush])

        Logger.warning(
          "OmniUI.TitleService: title generation failed for #{id}: #{inspect(reason)}"
        )

        state = %{state | task_refs: task_refs}
        {:noreply, clear_task(state, id)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    cond do
      Map.has_key?(state.task_refs, ref) ->
        {id, task_refs} = Map.pop(state.task_refs, ref)
        Logger.warning("OmniUI.TitleService: title task crashed for #{id}: #{inspect(reason)}")
        state = %{state | task_refs: task_refs}
        {:noreply, clear_task(state, id)}

      Map.has_key?(state.session_refs, ref) ->
        {id, session_refs} = Map.pop(state.session_refs, ref)
        state = %{state | session_refs: session_refs}
        {:noreply, drop_pending(state, id)}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internals: lifecycle ───────────────────────────────────────────

  defp track(state, id, pid) do
    case safe_subscribe(pid) do
      :ok ->
        ref = Process.monitor(pid)
        entry = %{pid: pid, monitor: ref, task: nil}

        %{
          state
          | pending: Map.put(state.pending, id, entry),
            session_refs: Map.put(state.session_refs, ref, id)
        }

      :error ->
        state
    end
  end

  defp untrack(state, id) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {entry, pending} ->
        if entry.task, do: Task.shutdown(entry.task, :brutal_kill)

        task_refs =
          if entry.task,
            do: Map.delete(state.task_refs, entry.task.ref),
            else: state.task_refs

        Process.demonitor(entry.monitor, [:flush])

        try do
          Session.unsubscribe(entry.pid)
        catch
          :exit, _ -> :ok
        end

        %{
          state
          | pending: pending,
            task_refs: task_refs,
            session_refs: Map.delete(state.session_refs, entry.monitor)
        }
    end
  end

  # Drop a pending entry without unsubscribing (session is already
  # gone, so unsubscribe would just hit :noproc). Used from the
  # session-DOWN path.
  defp drop_pending(state, id) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        state

      {entry, pending} ->
        if entry.task, do: Task.shutdown(entry.task, :brutal_kill)

        task_refs =
          if entry.task,
            do: Map.delete(state.task_refs, entry.task.ref),
            else: state.task_refs

        %{state | pending: pending, task_refs: task_refs}
    end
  end

  # Reset task fields after a failed generation, leaving the session
  # subscription open so the next turn retries.
  defp clear_task(state, id) do
    case Map.fetch(state.pending, id) do
      :error ->
        state

      {:ok, entry} ->
        %{state | pending: Map.put(state.pending, id, %{entry | task: nil})}
    end
  end

  defp start_generation(state, id, pid) do
    try do
      snapshot = Session.get_snapshot(pid)
      messages = Omni.Session.Tree.messages(snapshot.tree)
      model = state.model

      task = Task.async(fn -> Title.generate(model, messages) end)

      entry = Map.fetch!(state.pending, id)

      %{
        state
        | pending: Map.put(state.pending, id, %{entry | task: task}),
          task_refs: Map.put(state.task_refs, task.ref, id)
      }
    catch
      :exit, _ ->
        # Session died between :turn and the snapshot call. Manager
        # :closed will arrive shortly and clean up.
        state
    end
  end

  defp find_by_pid(state, pid) do
    Enum.find(state.pending, fn {_id, entry} -> entry.pid == pid end)
  end

  defp safe_subscribe(pid) do
    case Session.subscribe(pid, self(), mode: :observer) do
      {:ok, _snapshot} -> :ok
    end
  catch
    :exit, _ -> :error
  end

  # ── Internals: config ──────────────────────────────────────────────

  defp resolve_config(start_opts) do
    env = Application.get_env(:omni_ui, __MODULE__, [])
    merged = Keyword.merge(env, start_opts)

    %{
      manager: Keyword.get(merged, :manager, OmniUI.Sessions),
      model: Keyword.get(merged, :model)
    }
  end
end
