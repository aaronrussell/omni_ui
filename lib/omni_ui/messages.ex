defmodule OmniUI.Messages do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

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
      <p><%= MDEx.to_html!(@content.text) |> raw() %></p>
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.Thinking{}} = assigns) do
    ~H"""
    <div class="content-block">
      <p><%= MDEx.to_html!(@content.text) |> raw() %></p>
    </div>
    """
  end
end
