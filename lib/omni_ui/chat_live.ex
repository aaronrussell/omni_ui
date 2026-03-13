defmodule OmniUI.ChatLive do
  use Phoenix.LiveView

  def render(assigns) do
     ~H"""
     <div class="relative w-full h-full overflow-hidden flex">
       <div class="h-full w-full">
         <.live_component module={OmniUI.AgentInterface} id="agent" />
       </div>

       <!-- TODO : artifacts button -->

       <div class="h-full hidden">
         <!-- TODO : artifacts panel -->
       </div>
     </div>
     """
  end

  def mount(_params, _session, socket) do
     {:ok, socket}
  end
end
