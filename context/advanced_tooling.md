# Advanced Tooling Design

Two interrelated systems: **Artifacts** (persistent files the agent creates and the UI renders) and a **Code Sandbox** (Elixir REPL the agent can execute code in). The sandbox can create artifacts, and artifacts can reference each other, making the two systems complementary.

---

## Artifacts

### What is an Artifact?

A file created by the agent, persisted in the session. Examples: HTML pages, data files, reports, images, Excel spreadsheets. Artifacts are **session-scoped** and **not branch-aware** — the conversation tree captures the history of artifact operations via tool calls, but navigating conversation branches does not rewind artifact state. This is a deliberate simplification; the alternative (reconstructing artifact state by replaying tool calls along the active path) is significantly more complex and not worth the tradeoff.

### Data Model

```elixir
%OmniUI.Artifacts.Artifact{
  filename: String.t(),       # eg "report.html", "data.json"
  mime_type: String.t(),      # Derived from extension via MIME library
  size: non_neg_integer(),    # File size in bytes
  updated_at: DateTime.t()    # From File.stat mtime, or DateTime.utc_now() on write
}
```

- Artifact **content** lives on disk (not in assigns).
- Artifact **metadata** lives in assigns as `%{filename => %Artifact{}}` — a lightweight cached view of what's on disk. Owned by `AgentLive`, not the macro.
- Metadata is **recovered by scanning** the session's artifacts directory on load. No separate metadata persistence needed.
- `mime_type` is derived from the file extension via the `mime` library (transitive dep via `plug`). Unknown extensions fall back to `"application/octet-stream"` — rendering falls back to download mode.
- `new/1` auto-derives `mime_type` from `filename` and defaults `updated_at` to now if not provided.

### Filesystem Layout

Artifacts are co-located with session data, under an `artifacts/` subdirectory:

```
{base_path}/sessions/{session_id}/
  tree.etf
  meta.etf
  artifacts/
    dashboard.html
    data.json
    report.xlsx
    app.jsx
```

This uses the same base path as `Store.Filesystem`. Deleting a session via `Store.delete/2` already does `File.rm_rf` on the session directory, which naturally cleans up artifacts too.

### Tool Definition

A single Omni tool (`OmniUI.Artifacts.Tool`) with a `command` discriminator. The agent uses one tool for all artifact operations:

| Command | Params | Returns |
|---------|--------|---------|
| `write` | `filename`, `content` | Confirmation with file size |
| `patch` | `filename`, `search`, `replace` | Confirmation with file size, or error if search string not found |
| `get` | `filename` | File content as string |
| `list` | (none) | List of artifact filenames with MIME types and sizes |
| `delete` | `filename` | Confirmation |

**`write`** is an upsert — creates the file if it doesn't exist, replaces content if it does. Creates the artifacts directory if needed.

**`patch`** is a targeted find-replace edit. More token-efficient than `write` for small changes to large files. Replaces only the first occurrence. The tool description strongly encourages the agent to prefer `patch` over `write` for edits.

Implemented as a **stateful Omni tool module** — `init/1` receives a keyword list (must include `:session_id`), validates it, and passes it through as state. `call/2` delegates to `OmniUI.Artifacts.FileSystem` functions, passing the opts through. Errors raise (caught by `Omni.Tool.Runner`, returned to the agent with `is_error: true`).

The tool description includes structured guidance on commands, "prefer patch over write" directive, filename rules, and HTML artifact best practices (self-contained, CDN imports, explicit backgrounds).

```elixir
# Created when session_id is known:
tool = OmniUI.Artifacts.Tool.new(session_id: session_id)
```

### HTTP Serving (ArtifactPlug)

`OmniUI.Artifacts.Plug` serves artifact files over HTTP. The developer mounts it in their router **outside** the `:browser` pipeline — the Plug handles its own headers and doesn't need sessions, CSRF protection, or layouts. Mounting inside `pipe_through :browser` will break cross-artifact script loading (CSRF protection blocks cross-origin JS from sandboxed iframes) and `put_secure_browser_headers` sets `x-frame-options` which blocks iframe rendering.

```elixir
# Must be outside pipe_through :browser
forward "/omni_artifacts", OmniUI.Artifacts.Plug

scope "/" do
  pipe_through :browser
  live "/", MyAppWeb.AgentLive
end
```

Routes:

```
GET /omni_artifacts/{token}/{filename}
```

URLs use **signed tokens** (`Phoenix.Token`) that encode the session ID. The LiveView signs the token when building URLs; the Plug verifies it on each request. This prevents unauthorized access to other sessions' artifacts without shared state.

Token signing, verification, and URL construction are centralised in `OmniUI.Artifacts.URL`:

```elixir
# In LiveView (Phase 4 components will use this):
url = OmniUI.Artifacts.URL.artifact_url(socket.endpoint, session_id, "dashboard.html")
# => "/omni_artifacts/SFMyNTY.../dashboard.html"
```

Cross-artifact relative paths work naturally — `dashboard.html` can load `./data.json` because both share the same token prefix in the URL.

The Plug:
- Verifies the signed token via `OmniUI.Artifacts.URL.verify_token/3` (returns 401 on failure)
- Resolves the artifacts directory via `FileSystem.artifacts_dir(session_id: session_id)`
- **Path containment check** — expands the resolved path and verifies it is inside the artifacts directory (prevents `../` traversal, returns 404)
- Sets `Content-Type` from `MIME.from_path/1` (without charset suffix for binary types)
- Sets `Content-Disposition`: `inline` for browser-renderable types (`text/*`, `image/*`, `application/json`, `application/pdf`), `attachment` for everything else
- Sets `Cache-Control: no-store` (artifacts are mutable)
- Serves files via `Plug.Conn.send_file/3` (zero-copy sendfile in production)
- Returns 400 for malformed paths (not exactly two segments)

**Why a Plug route instead of `srcdoc`?** Three reasons:
1. **Cross-artifact references** — `dashboard.html` can load `data.json` via relative path `./data.json` because both are served from the same base URL.
2. **Binary artifacts** — Excel files, images, PDFs can be downloaded via a link to the route.
3. **Memory** — artifact content stays on disk, not in the LiveView socket.

### UI

Side panel, similar to Claude's artifacts panel. Implemented as a self-contained LiveComponent (`OmniUI.Artifacts.PanelComponent`) that manages all artifact state internally — AgentLive has zero artifact assigns.

**PanelComponent assigns (internal):**

| Assign | Type | Purpose |
|--------|------|---------|
| `@artifacts` | `%{filename => %Artifact{}}` | Metadata map, scanned from disk |
| `@active_artifact` | `String.t() \| nil` | Currently viewed artifact filename |
| `@content` | `Phoenix.HTML.safe() \| nil` | Pre-rendered HTML for code view mode |
| `@token` | `String.t() \| nil` | Signed Phoenix.Token, cached per session |

**Assigns from parent (AgentLive):**

| Assign | Type | Purpose |
|--------|------|---------|
| `session_id` | `String.t()` | Current session ID — triggers rescan on change |

**Communication:** AgentLive notifies the component of artifact changes via `send_update(PanelComponent, id: "artifacts-panel", action: :rescan)` in its `agent_event(:tool_result, ...)` callback.

**Panel layout:** Index/detail single-view pattern. When `@active_artifact` is nil, shows a list of all artifacts sorted by filename. When set, shows the artifact viewer with a back button. No sub-sidebar within the panel.

**Rendering modes** (determined by `mime_type`):

| Mode | MIME types | How |
|------|-----------|-----|
| Preview | `text/html`, `image/svg+xml` | `<iframe src="/omni_artifacts/{token}/{file}">` with `sandbox="allow-scripts"` |
| View | `text/*`, `application/json` | Syntax-highlighted code via `Lumis.highlight!/2` with `catppuccin_macchiato` theme (inline styles, no external CSS needed) |
| Download | everything else | Download link to the Plug route (+ inline image preview for `image/*` types) |

No special React/JSX rendering — JSX files are displayed as code. If the agent wants a rendered React component, it creates its own HTML artifact that loads React via CDN and references the JSX file. Cross-artifact references make this work naturally (the HTML file can load the JSX file via relative path). Native React rendering could be added later as an enhancement.

---

## Code Sandbox

### What is the Sandbox?

An Elixir execution environment where the agent can run code and collect output. The agent sends code as a string; the sandbox evaluates it, captures everything printed to stdout and the raw return value of the last expression, and returns both.

### Execution Model

**One peer node per execution.** Each tool invocation:

1. Starts a fresh Erlang peer node via `:peer.start/1`
2. Initialises the peer (inject code paths, boot Elixir, suppress OTP log noise)
3. Creates a StringIO on the **host** node for IO capture
4. Evaluates setup code (if any) then the user's code via `:erpc.call/3` with the host StringIO as the group leader
5. Collects captured stdout and the raw return value
6. Stops the peer node and closes the StringIO
7. Returns output + result to the caller

**Why per-execution?** Clean slate each time. No state drift between invocations. And critically: `Mix.install/1` can only be called once per VM — a fresh peer per execution allows each invocation to install different dependencies.

**Peer initialisation** requires three steps discovered during implementation:
- **Code paths** — peers do NOT inherit the host's code paths. Must inject explicitly via `:erpc.call(node, :code, :add_pathsa, [:code.get_path()])`.
- **Elixir boot** — `defmodule` and other Elixir features need internal ETS tables. Must call `:application.ensure_all_started(:elixir)` on the peer.
- **Logger level** — set to `:warning` to suppress OTP application shutdown notices that would leak to the host console.

**IO capture** uses a StringIO process on the host node (not the peer). The host StringIO pid is set as the group leader for the peer's eval process via `Process.group_leader/2` — Erlang distribution routes IO messages cross-node transparently. Keeping StringIO on the host means partial output is always accessible on timeout or peer crash without a second erpc call.

```elixir
# StringIO lives on the host — always accessible
{:ok, io} = StringIO.open("")

:erpc.call(node, fn ->
  Process.group_leader(self(), io)

  try do
    {result, _bindings} = Code.eval_string(code)
    {_, output} = StringIO.contents(io)
    {:ok, %{output: output, result: result}}
  catch
    kind, reason ->
      {_, output} = StringIO.contents(io)
      {:error, {kind, reason, __STACKTRACE__}, %{output: output}}
  end
end, timeout)

# On timeout, partial output is still readable:
{_, partial} = StringIO.contents(io)
```

**Distribution requirement** — `:peer` requires the host to be a distributed Erlang node. The sandbox auto-starts distribution with shortnames if `Node.alive?()` is false. Peer name type (short vs long) is detected via `:net_kernel.longnames()` to match the host.

### Tool Definition

Single Omni tool (`OmniUI.REPL.Tool`):

- **Input:** `title` (active-form description, e.g. "Calculating average score") and `code` (Elixir code string). Both required.
- **Success format:** `output\n=> inspect(result, pretty: true)`. Always shows the result, even `:ok`. If no IO output, just `=> result`.
- **Error handling:** All errors raise, producing `is_error: true` tool results. Code errors formatted with `Exception.format/3`, timeout/noconnection with descriptive messages. Partial output prepended when present.
- **init/1:** Accepts optional `:timeout`, `:max_output`, `:extensions` (list of `{module, opts}` sandbox extensions), and `:extra_description`.

### Environment-Aware Tool Description

The tool uses the `description/1` callback on `Omni.Tool` (receives state from `init/1`) to build a dynamic description. The description is a single heredoc with interpolation at two logical seams:

1. **Environment section** — `Code.ensure_loaded?(Mix)` switches between dev guidance (pre-installed libraries + Mix.install for extras) and release guidance (host deps only, Mix unavailable).
2. **Extension section** — each sandbox extension contributes a description fragment documenting the APIs it injects.

An optional `:extra_description` string fragment can also be passed through `init/1` opts, appended at the end.

### Mix.install in Releases

Mix is excluded from production releases by default. For deployments that want `Mix.install` support (VPS, Docker), options:

1. **Don't use a release** — run `mix phx.server` directly (Mix is available).
2. **Include Mix in the release** — add `applications: [mix: :permanent, hex: :permanent]` to the release config. Requires a writable filesystem and (for NIF deps) a C compiler on the host.
3. **Accept the limitation** — the sandbox works without `Mix.install`, using only the host app's existing dependencies. The tool description communicates this to the agent.

### Sandbox-Artifact Bridge

The sandbox can create and modify artifacts via a top-level `Artifacts` facade module injected into the peer node. The module is defined as AST (via `quote`) by `OmniUI.Artifacts.REPLExtension`, a sandbox extension that implements the `OmniUI.REPL.SandboxExtension` behaviour. It wraps `OmniUI.Artifacts.FileSystem` functions with the session's opts baked in via `unquote` into a module attribute:

```elixir
# Available in sandbox code:
Artifacts.write("chart.html", html_content)   #=> %Artifact{}
Artifacts.read("data.csv")                    #=> "csv,content..."
Artifacts.patch("chart.html", "old", "new")   #=> %Artifact{}
Artifacts.list()                               #=> [%Artifact{}, ...]
Artifacts.delete("temp.txt")                   #=> :ok
```

Under the hood, these delegate to `OmniUI.Artifacts.FileSystem` functions (available in the peer via shared code paths). `base_path` is pre-resolved on the host at tool construction time (via `FileSystem.base_path/1`) and baked into the facade, so the peer doesn't need host app config. Errors raise — the sandbox's `catch` formats them as `is_error: true` tool results. No IO confirmations; return values provide metadata (e.g. `%Artifact{}` from write/patch).

The LiveView picks up artifact changes when it handles the REPL tool result — `agent_event(:tool_result, %{name: "repl"}, socket)` triggers a rescan of the artifacts directory via `send_update(PanelComponent, action: :rescan)`.

### Security

This is a personal-use tool, not a secure multi-tenant sandbox. Documented as: *"The sandbox executes arbitrary code with full system access. For personal and development use only."*

| Mitigation | Approach |
|-----------|----------|
| Timeout | `:erpc.call/3` timeout, configurable (default 60s) |
| Crash isolation | Peer node crash does not affect the host application |
| Resource limits | Not implemented — peer has full system access |
| Filesystem | Not jailed — full read/write access |
| Network | Not restricted — agent needs network for scraping, APIs, etc. |

---

## Tool Lifecycle

OmniUI does not auto-register any tools. The developer explicitly adds tools in their LiveView callbacks — some tools may go in `mount/3` (if they don't need session context), others in `handle_params/3` (if they depend on session_id or URL params).

Artifact tools need a `session_id`, which comes from `handle_params`. The REPL tool receives `session_id` indirectly via its extensions (e.g. `{OmniUI.Artifacts.REPLExtension, session_id: session_id}`). Both are created together in `handle_params` via a `create_tools/1` helper.

**Flow:**

1. `mount/3` — `start_agent(socket, model: model, tool_timeout: 120_000)`. The `tool_timeout` is necessary because `Omni.Agent` defaults to 5s, which is too short for sandbox execution (default 60s + peer startup). `start_agent/2` passes `:tool_timeout` through to `Omni.Agent.start_link`.
2. `handle_params/3` — session_id is determined. `create_tools(session_id)` builds both artifact and REPL tools. Replace all tools via `update_agent(socket, tools: create_tools(session_id))`. PanelComponent receives the new `session_id` and scans for existing artifacts automatically.
3. Session switch (new `handle_params`) — replace all tools with new session_id. PanelComponent detects the session change in `update/2` and rescans.

The agent doesn't have artifact/sandbox tools until `handle_params` runs. In practice this is fine — the user can't submit a message until the page is connected and `handle_params` has executed.

**Syncing assigns after tool execution:**

The tool handlers run in the Agent process (not the LiveView process). When a tool executes, the LiveView receives an `{:agent, pid, :tool_result, result}` event. `AgentLive`'s `agent_event(:tool_result, %{name: tool_name}, socket) when tool_name in ["artifacts", "repl"]` callback matches on either tool name and sends `send_update(PanelComponent, action: :rescan)`. The component rescans the artifacts directory internally. This lives in `AgentLive`, not in the macro or Handlers — tooling is not baked into the shared infrastructure.

---

## Scope Boundaries

### Doing

- Artifact CRUD via a single tool (write, patch, get, list, delete)
- Disk-based artifact storage, co-located with session data
- Plug route for serving artifacts (enables cross-artifact references, binary downloads)
- Three rendering modes: iframe preview, code viewer, download
- Per-execution Elixir sandbox via `:peer`
- IO capture and timeout
- Environment-aware tool descriptions (Mix.install in dev, deps list in prod)
- Sandbox artifact bridge (filesystem-based) via generic extension mechanism
- Cross-tool description guidance (artifacts vs REPL pipeline)

### Not Doing

- Branch-aware artifact state (too complex, marginal value)
- Native React/JSX rendering (agent can create its own HTML+React artifacts manually)
- Secure multi-tenant sandboxing (Docker, syscall filtering, resource limits)
- Artifact versioning UI (history/diff view)
- Multiple simultaneous iframe previews
- Sandbox state persistence between executions
- Artifact collaboration / real-time sync
- Macro-managed tool registration (developer manages all tools explicitly)
- Scope-aware artifact paths (use separate `base_path` per tenant instead)

---

## Implementation Plan

### Phase 1: Artifact Data Layer ✓

Artifact data structures, filesystem operations, and Omni tool. No UI or agent wiring.

1. **`OmniUI.Artifacts.Artifact` struct** — `filename`, `mime_type`, `size`, `updated_at`. `new/1` auto-derives `mime_type` and `updated_at`; `new/2` builds from filename + `File.Stat`.
2. **`OmniUI.Artifacts.FileSystem` module** — filesystem operations with path resolution:
   - `artifacts_dir(opts)` — resolves `{base_path}/{session_id}/artifacts/` from opts, app config, or default
   - `write(filename, content, opts)` — write file (mkdir_p if needed), return `{:ok, %Artifact{}}`
   - `read(filename, opts)` — read file content
   - `patch(filename, search, replace, opts)` — find-replace (first occurrence only)
   - `list(opts)` — scan directory, return sorted `[%Artifact{}]` (ignores dotfiles/subdirs)
   - `delete(filename, opts)` — remove file
   - All functions accept `opts` keyword list as final argument with required `:session_id` and optional `:base_path`
   - Filename validation (reject `/`, `\`, `..`, null bytes, dotfiles, empty)
   - Configuration: `config :omni_ui, OmniUI.Artifacts, base_path: "..."` (defaults to `priv/omni/sessions`, same as `Store.Filesystem`)
3. **`OmniUI.Artifacts.Tool` module** — Omni tool (stateful):
   - Flat schema: `command`, `filename`, `content`, `search`, `replace`
   - `init/1` receives keyword opts (validates `:session_id`, passes through as state)
   - `call/2` dispatches on command, delegates to FileSystem (passing opts through), raises on errors
   - Detailed tool description with "prefer patch over write" guidance and HTML artifact best practices

### Phase 2: Artifact Wiring ✓

Connect the artifact tool to the agent lifecycle and keep assigns in sync.

4. **`handle_params` integration in `AgentLive`** — create tool with `Tool.new(session_id: session_id)` when session_id is known. Replace all tools via `update_agent(socket, tools: [tool])`. On session switch, replace tools with new session_id.
5. **Session load** — PanelComponent scans the artifacts directory automatically when it receives a new `session_id` via its `update/2` callback.
6. **Artifact sync** — `AgentLive.agent_event(:tool_result, %{name: "artifacts"}, socket)` sends `send_update(PanelComponent, action: :rescan)`. The component rescans internally. Tooling is application-level, not framework-level.

### Phase 3: Artifact Serving ✓

Enable HTTP access to artifacts for iframe rendering and downloads.

7. **`OmniUI.Artifacts.URL` module** — Token signing (`sign_token/2`), verification (`verify_token/3`), and URL construction (`artifact_url/3`). Centralises the `"omni_ui:artifact"` salt. Default token max age: 86,400s (24 hours).
8. **`OmniUI.Artifacts.Plug`** — Plug module that verifies signed tokens, resolves files via `FileSystem.artifacts_dir/1`, performs path containment checks, and serves files with `send_file/3`. Sets Content-Type, Content-Disposition (inline vs attachment), and `Cache-Control: no-store`.
9. **Developer integration** — developer adds `forward "/omni_artifacts", OmniUI.Artifacts.Plug` to their router.

### Phase 4: Artifact UI ✓

Built the panel as a self-contained LiveComponent. Moved all artifact state out of AgentLive.

10. **`OmniUI.Artifacts.PanelComponent`** — LiveComponent receiving only `session_id` from AgentLive. Owns `@artifacts`, `@active_artifact`, `@content`, `@token`. Custom `update/2` handles session changes (full reset + rescan + token sign), rescan actions (via `send_update`), and no-op re-renders. Index/detail single-view pattern.
11. **Iframe preview mode** — `<iframe>` loading from ArtifactPlug route with `sandbox="allow-scripts"`. URLs built from cached signed token.
12. **Code viewer mode** — syntax-highlighted via `Lumis.highlight!/2` with `catppuccin_macchiato` theme (inline styles). Content loaded on demand from disk when artifact is selected.
13. **Download mode** — download link to ArtifactPlug route for binary types. Inline image preview for `image/*` types.
14. **AgentLive simplification** — removed `@artifacts` assign, `scan_artifacts/1` helper, artifact scanning from `handle_params`. `agent_event(:tool_result, ...)` now does `send_update(PanelComponent, action: :rescan)`.
15. **Router requirement** — ArtifactPlug must be mounted outside `pipe_through :browser` to avoid CSRF and x-frame-options conflicts with sandboxed iframes.

### Phase 5: Sandbox Engine ✓

Built `OmniUI.REPL.Sandbox` as a standalone module with no Omni or agent dependencies.

15. **`OmniUI.REPL.Sandbox` module** — execution engine:
    - `run(code, opts)` — single public function. Starts peer, inits, evals, captures IO, stops peer.
    - **IO capture via host-local StringIO** — the StringIO process lives on the host node, set as the group leader for the peer's eval process. Cross-node IO routing is transparent via Erlang distribution. This means partial output is always readable on timeout or peer crash.
    - Returns **raw data** — `result` is the raw term (not inspected), errors are `{kind, reason, stacktrace}` triples (not formatted). The Tool layer (Phase 6) handles all stringification.
    - Uses `catch kind, reason` (not `rescue`) to catch throws and exits in addition to errors.
    - `:setup` option — code string evaluated in the peer before IO capture begins (used by Phase 7 for the Artifacts bridge module). Setup errors propagate as erpc exceptions.
    - `:timeout` option — default 60s. `:max_output` option — default 50KB. Both configurable via `config :omni_ui, OmniUI.REPL` or runtime opts.
    - **Peer init** requires explicit code path injection and Elixir boot (neither happens automatically). Peer logger set to `:warning` to suppress OTP shutdown noise.
    - **Distribution** — auto-starts with shortnames if host isn't distributed. Peer name type (short/long) matches host via `:net_kernel.longnames()` detection.
    - Return type: `{:ok, %{output: String.t(), result: term()}} | {:error, :timeout | :noconnection, %{output: String.t()}} | {:error, {atom(), term(), Exception.stacktrace()}, %{output: String.t()}}`
    - `test/test_helper.exs` updated to start distribution for peer node tests.

### Phase 6: REPL Tool + Wiring ✓

Wrapped the sandbox in an Omni tool and connected to AgentLive.

16. **`OmniUI.REPL.Tool` module** — Omni tool following the `Artifacts.Tool` pattern:
    - `use Omni.Tool` with name `"repl"`, schema accepting `title` (string, active-form description) and `code` (string), both required
    - `init/1` accepts optional `:timeout` and `:max_output`, passes through as state. No `:session_id` — deferred to Phase 7 when the artifact bridge needs it
    - `call/2` delegates to `Sandbox.run/2`. Success formatted as `output\n=> inspect(result, pretty: true)` (always shows result, even `:ok`). All errors raise (producing `is_error: true` tool results): code errors formatted with `Exception.format/3`, timeout/noconnection with descriptive messages. Partial output prepended to error messages when present
    - Dynamic description via `description/1` callback with `##` sections (When to Use, Environment, Adding Packages, Output, Example, Important Notes). Environment section switches on Mix availability. Extension descriptions appended automatically. Pre-installed libraries (Req, Jason) explicitly marked to prevent unnecessary Mix.install
17. **Wired into agent lifecycle** — `create_tools/1` helper builds both artifact and REPL tools. `agent_event` uses a single clause with guard: `when tool_name in ["artifacts", "repl"]` to trigger artifact panel rescan. `start_agent` in mount passes `tool_timeout: 120_000` (the default 5s was too short for sandbox execution). Added `:tool_timeout` passthrough in `OmniUI.start_agent/2`.

### Phase 7: Sandbox-Artifact Bridge ✓

Connected the sandbox to the artifact system via a generic extension mechanism, and updated tool descriptions with environment awareness and cross-tool guidance.

18. **`OmniUI.REPL.SandboxExtension` behaviour** — generic extension contract with two callbacks: `code/1` (returns AST or string to evaluate in the peer) and `description/1` (returns markdown fragment for the tool description). `REPL.Tool.init/1` accepts `:extensions` as a list of `{module, opts}` or bare modules.
19. **`OmniUI.Artifacts.REPLExtension`** — implements `SandboxExtension`. `code/1` returns a quoted `defmodule Artifacts` block that delegates to `FileSystem` functions with pre-resolved `base_path` and `session_id` baked in via `unquote`. `description/1` documents the five-function API. No IO confirmations — return values (`%Artifact{}`, `:ok`, content strings) provide feedback silently.
20. **Sandbox AST support** — `Sandbox.run/2` now accepts AST and lists (in addition to strings) for the `:setup` option via `eval_setup/1` dispatch. Multiple extensions each contribute a setup item; all are evaluated sequentially before user code.
21. **Dynamic REPL tool description** — `description/1` override builds a heredoc with `environment_section/0` (switches on `Code.ensure_loaded?(Mix)` for dev vs release guidance) and `extension_section/1` (collects fragments from extensions). Pre-installed libraries (Req, Jason) explicitly marked as "do NOT Mix.install these". `FileSystem.base_path/1` made public to support host-side path resolution.
22. **Artifacts.Tool cross-reference** — static "Artifacts vs REPL" section added to the artifacts tool description with the optimal data-visualisation pipeline: REPL saves data.json → artifacts tool authors HTML that loads it.
23. **AgentLive wiring** — `create_tools/1` passes `{REPLExtension, session_id: session_id}` in the `:extensions` opt. Artifact sync on REPL tool result was already wired in Phase 6.

### Phase 8: Polish

21. **Custom tool-use components (framework) ✓** — `content_block/1`'s `ToolUse` clause is now a dispatcher that consults a `@tool_components` map (`%{tool_name => (assigns -> rendered)}`) before falling back to a built-in `default_tool_use/1` renderer. Registration is via a mixed `:tools` list on `start_agent`/`update_agent`: either a bare `%Omni.Tool{}` (default rendering) or `{%Omni.Tool{}, component: fun}` (custom rendering). A private `normalise_tools/1` in `OmniUI` splits the list into the flat tool list for `Omni.Agent` and the components map assigned to `:tool_components`. Threaded through `AgentLive → TurnComponent → assistant_message → content_block`. Custom components receive a normalised assigns map: `@tool_use`, `@tool_result` (pre-resolved, nil if pending), `@streaming`. Event handling uses standard `phx-click` bubbling up through the `TurnComponent` to the parent LiveView. See architecture.md → "Custom Tool-Use Components".
22. **Artifacts tool-use component ✓** — `OmniUI.Artifacts.ChatUI.tool_use/1` wraps `OmniUI.Components.tool_use/1` and fills its `:aside` slot with command-specific content: for `write`/`patch` a button labelled with the filename that dispatches a `view_artifact` event, for `get`/`delete` a short status label referencing the filename, for `list` a "Listed artifacts" label. The aside only renders once the tool has produced a result; during streaming and execution the default component renders unmodified. Required adding an `:aside` slot to `expandable/1` (positioned outside the click target) and exposing the same slot on `tool_use/1` so custom components can add per-tool controls without replacing the default rendering. `AgentLive.handle_event("view_artifact", ...)` calls `send_update(PanelComponent, action: {:view, filename})`; `PanelComponent.update/2` gained a matching clause that mirrors the `select_artifact` handler. Wired via `{OmniUI.Artifacts.Tool.new(...), component: &OmniUI.Artifacts.ChatUI.tool_use/1}` in `create_tools/1`. Stale view buttons (artifact deleted mid-session) currently silently no-op to avoid crashing; see Error handling below for the follow-up.
23. **REPL tool-use component** — build a custom tool-use component for the REPL tool surfacing the agent-provided `title` field (active-form description like "Calculating average score") in place of the raw tool name. Wire via `{OmniUI.REPL.Tool.new(...), component: &OmniUI.REPL.ChatUI.tool_use/1}` in `create_tools/1`. May require exposing a `:toggle` override on `Components.tool_use/1` so custom components can replace the default tool-name label.
24. **Panel visibility toggle** — the panel is currently always visible. Decide on: `@artifacts_open` boolean, toggle button, and auto-open behaviour (auto-open on first artifact creation vs manual-only vs notification badge). See Open Question #3.
25. **Error handling** — graceful handling of disk errors, missing files, sandbox crashes.
    - **Stale artifact view buttons** — when an artifact is created and then deleted later in the same session, the "View" button in the earlier chat message still points to the deleted file. `PanelComponent.update({:view, filename})` currently silently no-ops on missing files to avoid crashing. Should render an inline error/notice in the panel explaining that the artifact has been deleted, auto-clearing on the next successful view or rescan that brings the file back.
26. **Documentation** — developer-facing docs for setting up artifacts and sandbox. Must include the router requirement (ArtifactPlug outside `:browser` pipeline).

---

## Open Questions

### 1. Artifact base path configuration ✓ (Resolved)

**Decision:** Independent config on `OmniUI.Artifacts` with the same default as `Store.Filesystem`:

```elixir
config :omni_ui, OmniUI.Artifacts, base_path: "/custom/path"
```

Defaults to `priv/omni/sessions`. Path resolution lives in `OmniUI.Artifacts.FileSystem.artifacts_dir/1`, which all FileSystem functions and the Plug use internally. The developer can also pass `:base_path` at runtime in opts. This decouples artifacts from the Store adapter while co-locating by default.

### 2. Sandbox result format ✓ (Resolved)

**Decision:** Tagged tuples with raw data. The sandbox returns unformatted values — the Tool layer handles stringification.

```elixir
{:ok, %{output: String.t(), result: term()}}
{:error, :timeout | :noconnection, %{output: String.t()}}
{:error, {kind, reason, stacktrace}, %{output: String.t()}}
```

`output` is captured IO (always present, may be empty). `result` is the raw return value (not inspected). Error tuples use `{kind, reason, stacktrace}` triples from `catch` (not formatted strings). All error paths include partial output captured before the failure. The Tool module calls `inspect/2` and `Exception.format/3` when building the agent-facing string.

### 3. Panel auto-open behaviour

Whether the artifact panel opens automatically when the first artifact is created, stays manual-only, or uses a notification badge. Defer to UI implementation phase.

### 4. Inline artifact indicators ✓ (Resolved)

**Decision:** `content_block/1`'s `ToolUse` clause is a dispatcher that supports custom per-tool components via a `@tool_components` map. The map is built at tool registration time from a mixed `:tools` list where entries can be bare `%Omni.Tool{}` structs or `{tool, component: fun}` tuples. Custom components receive a normalised `%{tool_use, tool_result, streaming}` assigns map. The framework plumbing is built; the actual artifacts tool-use component (filename pill + "View" button) is a Phase 8 follow-up. See architecture.md → "Custom Tool-Use Components".

### 5. Artifact Plug URL prefix ✓ (Resolved)

**Decision:** Configurable on the same `OmniUI.Artifacts` config key, with a convention-based default:

```elixir
config :omni_ui, OmniUI.Artifacts, url_prefix: "/omni_artifacts"
```

Components read `url_prefix` from config when building iframe `src` URLs via `OmniUI.Artifacts.URL.artifact_url/3`. Zero-config works if the developer follows the documented convention of mounting the Plug at `/omni_artifacts`.

### 6. Artifact URL authorization ✓ (Resolved)

**Decision:** Signed tokens via `Phoenix.Token`. The LiveView signs the session ID into a token when building artifact URLs; the Plug verifies the token on each request. This prevents access to other sessions' artifacts without shared state between the LiveView and Plug. Cross-artifact relative paths work because files share the same token prefix in the URL. Token max age defaults to 24 hours, configurable via `:max_age` option on the Plug.

### 7. Scope support ✓ (Resolved)

**Decision:** Not supported in the artifact system for now. If a developer uses scope for multi-tenancy, they can configure a different `base_path` per tenant. Scope can be revisited as a first-class concern later if real demand shows up.
