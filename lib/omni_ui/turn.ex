defmodule OmniUI.Turn do
  defstruct [
    :id,
    status: :complete,
    siblings: [],
    user_text: [],
    user_attachments: [],
    user_timestamp: nil,
    content: [],
    timestamp: nil,
    tool_results: %{},
    error: nil,
    usage: %Omni.Usage{}
  ]

  @type t :: %__MODULE__{
          id: Omni.Turn.id(),
          status: :complete | :streaming | :error,
          siblings: [Omni.Turn.id()],
          # User message
          user_text: [Omni.Content.Text.t()],
          user_attachments: [Omni.Content.Attachment.t()],
          user_timestamp: DateTime.t() | nil,
          # Assistant message
          content: [Omni.Message.content()],
          timestamp: DateTime.t() | nil,
          tool_results: %{
            String.t() => Omni.Content.ToolResult.t()
          },
          error: String.t() | nil,
          usage: Omni.Usage.t()
        }

  @spec from_omni(Omni.Turn.t(), map()) :: t()
  def from_omni(
        %Omni.Turn{
          id: id,
          parent: parent_id,
          messages: [user | tail],
          usage: usage
        },
        parent_map
      ) do
    turn = %OmniUI.Turn{
      id: id,
      siblings: Map.get(parent_map, parent_id, []),
      user_text: Enum.filter(user.content, &match?(%Omni.Content.Text{}, &1)),
      user_attachments: Enum.filter(user.content, &match?(%Omni.Content.Attachment{}, &1)),
      user_timestamp: user.timestamp,
      usage: usage
    }

    Enum.reduce(tail, turn, &reduce_turn_content/2)
  end

  @spec push_content(t(), Omni.Message.content()) :: t()
  def push_content(%OmniUI.Turn{} = turn, content_block) do
    %{turn | content: turn.content ++ [content_block]}
  end

  @spec push_delta(t(), String.t()) :: t()
  def push_delta(%OmniUI.Turn{} = turn, delta) do
    content = List.update_at(turn.content, -1, &%{&1 | text: &1.text <> delta})
    %{turn | content: content}
  end

  def put_tool_result(%OmniUI.Turn{} = turn, tool_result) do
    tool_results = Map.put(turn.tool_results, tool_result.tool_use_id, tool_result)
    %{turn | tool_results: tool_results}
  end

  # Helpers

  defp reduce_turn_content(%Omni.Message{role: :user} = msg, turn) do
    tool_results =
      msg.content
      |> Enum.filter(&match?(%Omni.Content.ToolResult{}, &1))
      |> Enum.reduce(turn.tool_results, &Map.put(&2, &1.tool_use_id, &1))

    %{turn | tool_results: tool_results}
  end

  defp reduce_turn_content(%Omni.Message{role: :assistant} = msg, turn) do
    %{turn | content: turn.content ++ msg.content, timestamp: msg.timestamp}
  end
end
