defmodule OmniUI.Messages do
  use Phoenix.Component

  def message_list(assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <.message
        :for={message <- @messages}
        message={message}
        tool_results={tool_result_map(message, @messages)}
      />
    </div>
    """
  end

  def message(%{message: %{role: :assistant}} = assigns) do
    ~H"""
    <div class="">
      <div class="px-4 flex flex-col gap-3">
        <.content_block
          :for={content <- @message.content}
          content={content} />
      </div>

      <!-- TODO - message usage -->
      <!-- TODO - message error -->
    </div>
    """
  end

  def message(%{message: %{role: :user}} = assigns) do
    ~H"""
    <div class="flex justify-start mx-4">
      <div class="user-message-container py-2 px-4 rounded-xl">
        <.content_block
          :for={content <- @message.content}
          content={content} />
      </div>

      <!-- TODO - attachments -->
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.Text{}} = assigns) do
    ~H"""
    <div class="content-block">
      <p><%= @content.text %></p>
    </div>
    """
  end

  # TODO - build toll result map
  defp tool_result_map(_message, _messages) do
    %{}
  end

end
