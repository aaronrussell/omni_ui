defmodule OmniUI.Components do
  use Phoenix.Component
  import OmniUI.Helpers

  attr :turns, Phoenix.LiveView.LiveStream, required: true
  attr :current_turn, OmniUI.Turn
  attr :usage, Omni.Usage, required: true

  def chat_interface(assigns) do
    ~H"""
    <div class="h-full max-w-2xl mx-auto flex flex-col">
      <div class="flex-auto space-y-4 p-4">
        <div class="mb-4 flex flex-col gap-4" id="turns" phx-update="stream">
          <.turn
            :for={{dom_id, turn} <- @turns}
            id={dom_id}
            turn={turn} />
        </div>
        <.turn :if={@current_turn} turn={@current_turn} />
      </div>

      <div class="shrink-0">
        <.live_component module={OmniUI.MessageEditor} id="editor" />
        <div class="flex items-center justify-between">
          <div>
            <!-- MAYBE - theme togggle?? -->
          </div>
          <div class="text-xs">
            <span><%= format_usage(@usage) %></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :turn, OmniUI.Turn, required: true
  attr :rest, :global

  def turn(assigns) do
    ~H"""
    <div class="space-y-4" {@rest}>
      <.user_message
        text={@turn.user_text}
        attachments={@turn.user_attachments}
        timestamp={@turn.user_timestamp} />
      <.assistant_message
        content={@turn.content}
        tool_results={@turn.tool_results}
        timestamp={@turn.timestamp} />

      <div :if={@turn.status == :complete} class="text-xs">
        <%= format_usage(@turn.usage) %>
      </div>
    </div>
    """
  end

  attr :text, :list, required: true
  attr :attachments, :list, required: true
  attr :timestamp, DateTime, required: true

  def user_message(assigns) do
    ~H"""
    <div class="flex justify-end">
      <div class="relative px-4 py-2 bg-zinc-200 border border-zinc-400 rounded-lg">
        <div class="flex flex-col gap-3">
          <.content_block
            :for={content <- @text}
            content={content} />
        </div>
      </div>

      <div :if={@attachments != []} class="mt-3 flex flex-wrap gap-2">
        <!-- TODO - attachment_tile -->
      </div>
    </div>
    """
  end

  attr :content, :list, required: true
  attr :tool_results, :map, required: true
  attr :timestamp, DateTime, required: true

  def assistant_message(assigns) do
    ~H"""
    <div>
      <div class="flex flex-col gap-3">
        <.content_block
          :for={content <- @content}
          content={content}
          tool_results={@tool_results} />
      </div>

      <!-- TODO - message error -->
    </div>
    """
  end

  attr :content, :map, required: true
  attr :tool_results, :map, default: %{}

  def content_block(%{content: %Omni.Content.Text{}} = assigns) do
    ~H"""
    <div class="">
      <%= markdown(@content.text) %>
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.Thinking{}} = assigns) do
    ~H"""
    <div class="">
      <%= markdown(@content.text) %>
    </div>
    """
  end

  def content_block(%{content: %Omni.Content.ToolUse{}} = assigns) do
    ~H"""
    <div class="relative px-4 py-2 bg-zinc-200 border border-zinc-400 rounded-lg space-y-3">
      <div class="font-bold">
        <%= @content.name %>
      </div>

      <div>
        <div class="text-xs font-medium mb-1">Input</div>
        <pre><%= JSON.encode!(@content.input) %></pre>
      </div>

      <div :if={@tool_results[@content.id]}>
        <div class="text-xs font-medium mb-1">Output</div>
        <pre><%= inspect(@tool_results[@content.id]) %></pre>
      </div>
    </div>
    """
  end
end
