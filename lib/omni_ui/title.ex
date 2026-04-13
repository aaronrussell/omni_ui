defmodule OmniUI.Title do
  @moduledoc """
  Generates titles for conversation sessions.

  Two strategies:

    * `:heuristic` — truncates the first user message text. No LLM call.
    * `{provider, model}` — asks the given model to summarise the
      conversation into a concise title.

  The caller supplies a message list (typically from `OmniUI.Tree.messages/1`)
  and the chosen strategy. Non-text content (attachments, thinking blocks,
  tool uses, tool results) is filtered out — only `%Omni.Content.Text{}`
  blocks contribute.

  ## Examples

      iex> messages = [Omni.message("What is Elixir?"), Omni.message(role: :assistant, content: "...")]
      iex> OmniUI.Title.generate(:heuristic, messages)
      {:ok, "What is Elixir?"}

      iex> OmniUI.Title.generate({:anthropic, "claude-haiku-4-5"}, messages)
      {:ok, "Intro to Elixir"}

  Returns `{:error, :no_text}` when the conversation contains no extractable
  text (e.g. the first user message is all attachments and no assistant has
  responded yet).
  """

  @heuristic_length 50
  @max_tokens 50

  @system_prompt """
  Generate a concise 3-6 word title for the following conversation.
  Reply with only the title. No quotes, no punctuation, no explanation.
  """

  @spec generate(Omni.Model.ref() | :heuristic, [Omni.Message.t()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(strategy, messages, opts \\ [])

  def generate(:heuristic, messages, _opts) do
    case heuristic(messages) do
      "" -> {:error, :no_text}
      title -> {:ok, title}
    end
  end

  def generate(model, messages, opts) do
    case format_conversation(messages) do
      "" ->
        {:error, :no_text}

      prompt ->
        context = Omni.context(system: @system_prompt, messages: [Omni.message(prompt)])
        opts = Keyword.merge([max_tokens: @max_tokens], opts)

        case Omni.generate_text(model, context, opts) do
          {:ok, response} ->
            case extract_title(response) do
              "" -> {:error, :empty_response}
              title -> {:ok, title}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns the first user message's text, trimmed and truncated to 50
  characters. Returns an empty string when no user text is present.
  """
  @spec heuristic([Omni.Message.t()]) :: String.t()
  def heuristic(messages) do
    messages
    |> first_text(:user)
    |> truncate(@heuristic_length)
  end

  # ── Private ────────────────────────────────────────────────────────

  defp format_conversation(messages) do
    user = first_text(messages, :user)
    assistant = first_text(messages, :assistant)

    []
    |> prepend_part("User", user)
    |> prepend_part("Assistant", assistant)
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp prepend_part(parts, _label, ""), do: parts
  defp prepend_part(parts, label, text), do: ["#{label}: #{text}" | parts]

  defp first_text(messages, role) do
    case Enum.find(messages, &match?(%{role: ^role}, &1)) do
      nil -> ""
      msg -> extract_text(msg.content)
    end
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&match?(%Omni.Content.Text{}, &1))
    |> Enum.map_join("\n", & &1.text)
    |> String.trim()
  end

  defp extract_text(content) when is_binary(content), do: String.trim(content)

  defp extract_title(response) do
    response.message.content
    |> Enum.find_value(fn
      %Omni.Content.Text{text: text} -> text
      _ -> ""
    end)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp truncate(text, max) do
    normalized = text |> String.replace(~r/\s+/, " ") |> String.trim()

    if String.length(normalized) <= max do
      normalized
    else
      trimmed =
        normalized
        |> String.split(" ", trim: true)
        |> Enum.reduce_while("", fn word, acc ->
          candidate = if acc == "", do: word, else: acc <> " " <> word

          cond do
            String.length(candidate) <= max -> {:cont, candidate}
            acc == "" -> {:halt, String.slice(word, 0, max)}
            true -> {:halt, acc}
          end
        end)

      trimmed <> "..."
    end
  end
end
