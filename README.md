# Omni UI

![Hex.pm](https://img.shields.io/hexpm/v/omni_ui?color=informational)
![License](https://img.shields.io/github/license/aaronrussell/omni_ui?color=informational)
![Build Status](https://img.shields.io/github/actions/workflow/status/aaronrussell/omni_ui/elixir.yml?branch=main)

**Agent chat UI for Elixir** — a ready-made LiveView interface for exploring, prototyping, and experimenting with [Omni Agent](https://github.com/aaronrussell/omni_agent) powered agents.

![Omni UI](https://raw.githubusercontent.com/aaronrussell/omni_ui/main/media/screenshot.webp)

## Features

- **Built on Omni** — multi-provider LLM support, streaming, tool use, structured output, persistent sessions, branching conversations, and pluggable storage — all inherited from [Omni](https://github.com/aaronrussell/omni), [Omni Agent](https://github.com/aaronrussell/omni_agent), and [Omni Tools](https://github.com/aaronrussell/omni_tools)
- **Drop-in agent chat** — `AgentLive` mounts a complete interface with a files panel, Elixir REPL, and web tools wired up out of the box
- **Build your own** — `use Omni.UI` adds session plumbing to any LiveView; compose with `ChatUI` and `CoreUI` components for the rendering layer
- **Themeable** — semantic colour tokens with light and dark mode support

## Installation

Add Omni UI to your dependencies:

```elixir
def deps do
  [
    {:omni_ui, "~> 0.1"}
  ]
end
```

Omni UI depends on `omni`, which provides the LLM API layer. Configure your provider API keys as described in the [Omni README](https://github.com/aaronrussell/omni#installation).

### Assets

Omni UI ships CSS and JavaScript that your application needs to include.

In your CSS entry point, add a `@source` directive pointing at the Omni UI component templates so Tailwind can scan them, and `@import` the shipped stylesheet:

```css
/* assets/css/app.css */
@source "../../deps/omni_ui/lib/omni/ui";
@import "../../deps/omni_ui/priv/static/omni_ui.css";
```

In your JavaScript entry point, import the shipped JS:

```js
// assets/js/app.js
import "../../deps/omni_ui/priv/static/omni_ui.js"
```

The CSS defines [OKLCH](https://oklch.com/) semantic colour tokens (`--color-omni-bg`, `--color-omni-text`, `--color-omni-accent-1`, etc.) with light and dark variants. Override any token in your own CSS to match your application's palette.

## Quick start

The fastest way to see Omni running in your app. Mount the built-in `AgentLive`, add the session manager to your supervision tree, and you're done.

### 1. Configure the session manager

```elixir
# config/config.exs
config :omni_ui, Omni.UI.Sessions,
  store: {Omni.Session.Stores.FileSystem, base_dir: "priv/sessions"},
  title_generator: {:anthropic, "claude-haiku-4-5"}
```

### 2. Add it to your supervision tree

```elixir
# application.ex
children = [
  # ... your other children
  Omni.UI.Sessions,
]
```

### 3. Mount in your router

```elixir
# router.ex
scope "/" do
  pipe_through :browser
  live "/", Omni.UI.AgentLive
end

forward "/omni_files", Omni.UI.Files.Plug
```

Start your server and open the browser — you have a working agent chat with sessions, files, REPL, and web tools.

## Build your own

When you want full control over the layout, tools, or event handling, skip `AgentLive` and `use Omni.UI` in your own LiveView. The macro injects session streaming, state management, and event routing — you bring the template and any custom behaviour.

```elixir
defmodule MyAppWeb.ChatLive do
  use Phoenix.LiveView
  use Omni.UI

  def render(assigns) do
    ~H"""
    <.chat_interface>
      <.turn_list stream={@streams.turns} tool_components={@tool_components} />
      <.turn :if={@current_turn} turn={@current_turn} tool_components={@tool_components} />
      <:editor>
        <.editor model={@model} />
      </:editor>
    </.chat_interface>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, init_session(socket, model: {:anthropic, "claude-sonnet-4-6"})}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, attach_session(socket, id: params["session_id"])}
  end
end
```

See the `Omni.UI` module documentation for the full API — session lifecycle, custom agents, tool components, configuration, and the `session_event` callback.

## Documentation

Full API reference is available on [HexDocs](https://hexdocs.pm/omni_ui).

## License

This package is open source and released under the [Apache-2 License](https://github.com/aaronrussell/omni_ui/blob/main/LICENSE).

(c) Copyright 2026 [Push Code Ltd](https://www.pushcode.com/).
