defmodule OmniUI.REPL.Tool do
  @moduledoc """
  Omni tool for executing Elixir code in a sandboxed peer node.

  Each invocation runs in a fresh Erlang peer node with a clean slate.
  IO output is captured and returned alongside the expression result.

  ## Usage

      tool = OmniUI.REPL.Tool.new()
      tool = OmniUI.REPL.Tool.new(timeout: 30_000, max_output: 10_000)

  ## Extensions

  Extensions inject additional code and documentation into the sandbox.
  See `OmniUI.REPL.SandboxExtension` for the behaviour.

      tool = OmniUI.REPL.Tool.new(
        extensions: [{OmniUI.Artifacts.REPLExtension, session_id: session_id}]
      )

  Then add the tool to the agent via `update_agent(socket, tools: [tool])`.
  """

  use Omni.Tool,
    name: "repl",
    description: "Execute Elixir code in a sandboxed peer node."

  alias OmniUI.REPL.Sandbox

  @impl Omni.Tool
  def schema do
    import Omni.Schema

    object(
      %{
        title:
          string(
            description:
              "Brief title describing what the code achieves in active form, e.g. 'Calculating average score'"
          ),
        code: string(description: "Elixir code to evaluate")
      },
      required: [:title, :code]
    )
  end

  @impl Omni.Tool
  def init(opts) do
    opts = opts || []

    opts
    |> Keyword.take([:timeout, :max_output, :extensions, :extra_description])
    |> Keyword.update(:extensions, [], &normalize_extensions/1)
  end

  @impl Omni.Tool
  def description(opts) do
    """
    Execute Elixir code in a sandboxed peer node.

    ## When to Use
    - Calculations and data transformations
    - Testing code snippets and exploring APIs
    - Processing, analysing, or generating data
    - Verifying assumptions about Elixir behaviour

    #{environment_section()}

    ## Output
    - IO output (IO.puts, IO.inspect, etc.) is captured and returned to you
    - The return value of the last expression is always shown
    - The user does not see raw output — summarise key findings in your response

    ## Example
    numbers = [10, 20, 15, 25]
    sum = Enum.sum(numbers)
    avg = sum / length(numbers)
    IO.puts("Sum: \#{sum}, Average: \#{avg}")

    ## Important Notes
    - Be intentional about return values — end with :ok if only IO output matters
    - For large data, use IO.inspect(data, limit: 20) rather than returning the full structure
    - Define modules freely — they exist only for the current invocation\
    #{extension_section(opts)}\
    #{extra_section(opts)}\
    """
  end

  @impl Omni.Tool
  def call(%{code: code}, opts) do
    setup = build_setup(opts)

    sandbox_opts =
      opts
      |> Keyword.take([:timeout, :max_output])
      |> maybe_put_setup(setup)

    case Sandbox.run(code, sandbox_opts) do
      {:ok, %{output: output, result: result}} ->
        format_success(output, result)

      {:error, :timeout, %{output: output}} ->
        raise format_error(output, "Execution timed out")

      {:error, :noconnection, %{output: output}} ->
        raise format_error(output, "Sandbox node crashed")

      {:error, {kind, reason, stacktrace}, %{output: output}} ->
        raise format_error(output, Exception.format(kind, reason, stacktrace))
    end
  end

  # ── Setup ─────────────────────────────────────────────────────────

  defp build_setup(opts) do
    case Keyword.get(opts, :extensions, []) do
      [] -> nil
      exts -> Enum.map(exts, fn {mod, ext_opts} -> mod.code(ext_opts) end)
    end
  end

  defp maybe_put_setup(opts, nil), do: opts
  defp maybe_put_setup(opts, setup), do: Keyword.put(opts, :setup, setup)

  defp normalize_extensions(exts) do
    Enum.map(exts, fn
      {mod, ext_opts} -> {mod, ext_opts}
      mod when is_atom(mod) -> {mod, []}
    end)
  end

  # ── Description helpers ───────────────────────────────────────────

  defp environment_section do
    if Code.ensure_loaded?(Mix) do
      """
      ## Environment
      - Full Elixir/Erlang standard library
      - Each invocation is a fresh VM — no state persists between calls
      - Pre-installed libraries (do NOT Mix.install these):
        - Req — HTTP client
        - Jason — JSON encoding/decoding

      ## Adding Packages
      Use Mix.install ONLY for packages not listed above. It can only be called \
      once per invocation, so install everything you need in a single call:
      Mix.install([:csv, :explorer, :xlsx_reader])  # CSV, dataframes, Excel\
      """
    else
      """
      ## Environment
      - Full Elixir/Erlang standard library
      - Each invocation is a fresh VM — no state persists between calls
      - The host application's compiled dependencies are available
      - Mix.install is not available in release mode\
      """
    end
  end

  defp extension_section(opts) do
    case Keyword.get(opts, :extensions, []) do
      [] ->
        ""

      exts ->
        desc =
          exts
          |> Enum.map(fn {mod, ext_opts} -> mod.description(ext_opts) end)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")

        case desc do
          "" -> ""
          text -> "\n\n" <> text
        end
    end
  end

  defp extra_section(opts) do
    case Keyword.get(opts, :extra_description) do
      nil -> ""
      "" -> ""
      text -> "\n\n" <> text
    end
  end

  # ── Formatting ────────────────────────────────────────────────────

  defp format_success(output, result) do
    inspected = inspect(result, pretty: true)

    case output do
      "" -> "=> #{inspected}"
      _ -> "#{output}\n=> #{inspected}"
    end
  end

  defp format_error("", message), do: message
  defp format_error(output, message), do: "#{output}\n#{message}"
end
