defmodule OmniUI.Messages do
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  import OmniUI.Helpers, only: [format_usage: 1]

  attr :role, :atom, required: true, values: [:user, :assistant]
  attr :content, :list, required: true
  attr :tool_resuts, :map, default: %{}
  attr :usage, Omni.Usage
  attr :timestamp, DateTime, required: true
  attr :streaming, :boolean, default: false

  def message(%{role: :user} = assigns) do
    assigns =
      assign(assigns,
        attachments: filter_content(assigns.content, [Omni.Content.Attachment])
      )

    ~H"""
    <div class="flex justify-end">
      <div class="user-message-container py-2 px-4 rounded-xl">
        <.content_block
          :for={content <- text_content(@content)}
          content={content} />
      </div>

      <div :if={@attachments != []} class="mt-3 flex flex-wrap gap-2">
        <!-- TODO - attachment_tile -->
      </div>
    </div>
    """
  end

  def message(%{role: :assistant} = assigns) do
    ~H"""
    <div class="">
      <div class="px-4 flex flex-col gap-3">
        <.content_block
          :for={content <- @content}
          content={content}
          tool_results={@tool_results} />
      </div>

      <div :if={not @streaming} class="px-4 mt-2 text-xs text-muted-foreground">
        <%= format_usage(@usage) %>
      </div>

      <!-- TODO - message error -->
    </div>
    """
  end

  attr :content, :map, required: true
  attr :tool_results, :map

  def content_block(%{content: %Omni.Content.Text{}} = assigns) do
    ~H"""
    <div class="text-foreground max-w-none break-words overflow-wrap-anywhere [&>*:last-child]:!mb-0">
      <%= markdown(@content.text) %>
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.Thinking{}} = assigns) do
    ~H"""
    <div class="text-muted-foreground italic max-w-none break-words overflow-wrap-anywhere text-sm [&>*:last-child]:!mb-0">
      <%= markdown(@content.text) %>
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.ToolUse{id: tool_use_id}} = assigns) do
    assigns = assign(assigns, :result, assigns.tool_results[tool_use_id])

    ~H"""
    <div class="p-2.5 border border-border rounded-md bg-card text-card-foreground shadow-xs">
      <div class="space-y-3">
        <div class="flex items-center gap-2 text-sm text-muted-foreground">
          <%= @content.name %>
        </div>

        <div>
          <div class="text-xs font-medium mb-1 text-muted-foreground">Input</div>
          <pre><%= JSON.encode!(@content.input) %></pre>
        </div>

        <div :if={@result != nil}>
          <div class="text-xs font-medium mb-1 text-muted-foreground">Output</div>
          <pre><%= inspect(@result.content) %></pre>
        </div>
      </div>
    </div>
    """
  end

  defp filter_content(content, types),
    do: Enum.filter(content, fn content -> content.__struct__ in types end)

  defp text_content(content),
    do: filter_content(content, [Omni.Content.Text, Omni.Content.Thinking])

  defp markdown(text),
    do: text |> MDEx.to_html!() |> raw()
end
