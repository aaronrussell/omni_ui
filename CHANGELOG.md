# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-25

Initial release. A Phoenix LiveView component kit for building agent chat interfaces on top of [omni_agent](https://github.com/aaronrussell/omni_agent).

- **Two ways to work** — mount `AgentLive` for a batteries-included chat app, or `use Omni.UI` in your own LiveView and compose with `ChatUI`/`CoreUI` components for full control.
- **Real-time streaming** — token-by-token rendering of assistant responses, thinking blocks, and tool use with autoscroll.
- **Conversation branching** — edit earlier messages, regenerate responses, and navigate between branches with version controls.
- **Session management** — persistent sessions with a sidebar drawer, inline rename, and lazy creation (no empty drafts on refresh).
- **Built-in tools** — file management, an Elixir REPL, and web fetching via [omni_tools](https://github.com/aaronrussell/omni_tools), with custom inline renderers for each.
- **Files panel** — browse, preview, and download agent-created files with syntax highlighting, HTML/PDF preview, and media display.
- **Themeable** — OKLCH semantic colour tokens with dark mode, overridable via CSS custom properties.

---

[Unreleased]: https://github.com/aaronrussell/omni_ui/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/aaronrussell/omni_ui/releases/tag/v0.1.0
