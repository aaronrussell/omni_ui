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

An Elixir execution environment where the agent can run code and collect output. The agent sends code as a string; the sandbox evaluates it, captures everything printed to stdout, and returns the output. This is a REPL, not a function call — the result is IO output, not return values.

### Execution Model

**One peer node per execution.** Each tool invocation:

1. Starts a fresh Erlang peer node via `:peer.start/1`
2. Injects the Artifacts API module into the peer (if artifacts are enabled)
3. Overrides the group leader for IO capture
4. Evaluates the agent's code via `:erpc.call/4` with a timeout
5. Collects captured stdout
6. Stops the peer node
7. Returns output + status to the agent

**Why per-execution?** Clean slate each time. No state drift between invocations. And critically: `Mix.install/1` can only be called once per VM — a fresh peer per execution allows each invocation to install different dependencies.

**IO capture** via group leader override:

```elixir
:erpc.call(node, fn ->
  {:ok, io} = StringIO.open("")
  Process.group_leader(self(), io)

  try do
    Code.eval_string(code)
    {_, output} = StringIO.contents(io)
    {:ok, output}
  rescue
    e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
  end
end, timeout)
```

### Tool Definition

Single Omni tool (`OmniUI.Tools.Sandbox`):

- **Input:** `code` (string of Elixir code)
- **Output:** Structured result with stdout and status

```
%{status: "ok", output: "...captured stdout..."}
%{status: "error", output: "...partial stdout...", error: "** (RuntimeError) ..."}
```

### Environment-Aware Tool Description

The tool description adapts at runtime based on whether `Mix` is available:

```elixir
if Code.ensure_loaded?(Mix) do
  base <> " You can call Mix.install/1 to add any Hex dependency."
else
  base <> " You cannot install additional dependencies. Available libraries: #{available_deps}."
end
```

`Code.ensure_loaded?(Mix)` returns `true` in dev/test, `false` in a production release (unless Mix is explicitly included). This means:

- **In dev:** Agent knows it can use `Mix.install` for any dependency.
- **In production:** Agent knows it's limited to the host app's compiled dependencies, and gets a list of what's available.

The developer curates the production sandbox's capabilities through their own `mix.exs` dependencies.

### Mix.install in Releases

Mix is excluded from production releases by default. For deployments that want `Mix.install` support (VPS, Docker), options:

1. **Don't use a release** — run `mix phx.server` directly (Mix is available).
2. **Include Mix in the release** — add `applications: [mix: :permanent, hex: :permanent]` to the release config. Requires a writable filesystem and (for NIF deps) a C compiler on the host.
3. **Accept the limitation** — the sandbox works without `Mix.install`, using only the host app's existing dependencies. The tool description communicates this to the agent.

### Sandbox-Artifact Bridge

The sandbox can create and modify artifacts. An `Artifacts` module is injected into the peer node before code execution:

```elixir
# Available in sandbox code:
Artifacts.write("chart.html", html_content, type: :html)
Artifacts.get("data.csv")
Artifacts.list()
Artifacts.patch("chart.html", search: "old", replace: "new")
Artifacts.delete("temp.txt")
```

Under the hood, these perform **direct filesystem operations** to the session's artifacts directory. The peer node runs on the same machine with the same filesystem access. No cross-node RPC needed for file I/O.

The LiveView picks up artifact changes when it handles the sandbox tool result — it rescans the artifacts directory to sync the `@artifacts` assign.

### Security

This is a personal-use tool, not a secure multi-tenant sandbox. Documented as: *"The sandbox executes arbitrary code with full system access. For personal and development use only."*

| Mitigation | Approach |
|-----------|----------|
| Timeout | `:erpc.call/4` timeout, configurable (default 30s) |
| Crash isolation | Peer node crash does not affect the host application |
| Resource limits | Not implemented — peer has full system access |
| Filesystem | Not jailed — full read/write access |
| Network | Not restricted — agent needs network for scraping, APIs, etc. |

---

## Tool Lifecycle

OmniUI does not auto-register any tools. The developer explicitly adds tools in their LiveView callbacks — some tools may go in `mount/3` (if they don't need session context), others in `handle_params/3` (if they depend on session_id or URL params).

Artifact and sandbox tools need a `session_id`, which comes from `handle_params`. The tools are created there:

**Flow:**

1. `mount/3` — `start_agent(socket, model: model)` with any session-independent tools.
2. `handle_params/3` — session_id is determined. Create artifact/sandbox tools with `Tool.new(session_id: session_id)`. Replace all tools via `update_agent(socket, tools: [tool])`. PanelComponent receives the new `session_id` and scans for existing artifacts automatically.
3. Session switch (new `handle_params`) — replace all tools with new session_id. PanelComponent detects the session change in `update/2` and rescans.

The agent doesn't have artifact/sandbox tools until `handle_params` runs. In practice this is fine — the user can't submit a message until the page is connected and `handle_params` has executed.

**Syncing assigns after tool execution:**

The tool handlers run in the Agent process (not the LiveView process). When a tool executes, the LiveView receives an `{:agent, pid, :tool_result, result}` event. `AgentLive`'s `agent_event(:tool_result, %{name: "artifacts"}, socket)` callback matches on the tool name and sends `send_update(PanelComponent, action: :rescan)`. The component rescans the artifacts directory internally. This lives in `AgentLive`, not in the macro or Handlers — tooling is not baked into the shared infrastructure.

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
- Sandbox artifact bridge (filesystem-based)

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

### Phase 5: Code Sandbox

Build the execution engine and tool.

15. **`OmniUI.Sandbox` module** — execution engine:
    - `run(code, opts)` — start peer, inject modules, eval code, capture IO, stop peer, return result
    - Group leader override for IO capture
    - Timeout handling
    - Error formatting (compilation errors, runtime exceptions)
16. **`OmniUI.Tools.Sandbox` module** — Omni tool:
    - `use Omni.Tool` with schema accepting `code` string
    - `init/1` receives config (artifacts path, timeout, etc.)
    - `call/2` delegates to `OmniUI.Sandbox.run/2`
    - Environment-aware description (check `Code.ensure_loaded?(Mix)`)
17. **Wire into agent lifecycle** — add sandbox tool in `handle_params` alongside artifacts tool.
18. **Update artifacts tool description** — Add "Artifacts vs Sandbox" guidance to the artifacts tool prompt, similar to Pi's "Artifacts Tool vs REPL" pattern. Key points to cover:
    - Use artifacts tool when the agent is the author (writing notes, HTML pages, reports)
    - Use sandbox when code processes data (scraping, CSV processing, data pipelines)
    - The composable pattern: sandbox generates data → artifacts tool creates HTML that visualizes it
    - Also update sandbox tool description to cross-reference artifacts

### Phase 6: Sandbox-Artifact Bridge

Connect the sandbox to the artifact system.

19. **Artifacts API module for sandbox** — module injected into the peer node that performs file operations on the session's artifacts directory. Mirrors the tool commands (write, get, list, patch, delete).
20. **Artifact sync on sandbox result** — when the sandbox tool result comes back, rescan artifacts directory (same mechanism as Phase 2, step 6).

### Phase 7: Polish

21. **Inline artifact indicators** — when a `content_block` renders an artifact tool use, show a richer UI (artifact name, type icon, preview thumbnail) instead of raw JSON. This is the broader question of custom components per tool type — may be a rabbit hole, scope carefully.
22. **Panel visibility toggle** — the panel is currently always visible. Decide on: `@artifacts_open` boolean, toggle button, and auto-open behaviour (auto-open on first artifact creation vs manual-only vs notification badge). See Open Question #3.
23. **Error handling** — graceful handling of disk errors, missing files, sandbox crashes.
24. **Documentation** — developer-facing docs for setting up artifacts and sandbox. Must include the router requirement (ArtifactPlug outside `:browser` pipeline).

---

## Open Questions

### 1. Artifact base path configuration ✓ (Resolved)

**Decision:** Independent config on `OmniUI.Artifacts` with the same default as `Store.Filesystem`:

```elixir
config :omni_ui, OmniUI.Artifacts, base_path: "/custom/path"
```

Defaults to `priv/omni/sessions`. Path resolution lives in `OmniUI.Artifacts.FileSystem.artifacts_dir/1`, which all FileSystem functions and the Plug use internally. The developer can also pass `:base_path` at runtime in opts. This decouples artifacts from the Store adapter while co-locating by default.

### 2. Sandbox result format

What the sandbox tool returns to the agent. Options range from plain stdout string to a structured envelope with status, output, error, and list of artifacts modified. The right format will become clearer during implementation — start simple and enrich as needed.

### 3. Panel auto-open behaviour

Whether the artifact panel opens automatically when the first artifact is created, stays manual-only, or uses a notification badge. Defer to UI implementation phase.

### 4. Inline artifact indicators

Whether `content_block/1` should render artifact tool uses differently from generic tool uses (eg show artifact name, type icon, "View" button). Deferred to Phase 7 polish — the default tool use rendering works as a starting point.

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
