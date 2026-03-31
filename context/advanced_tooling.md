# Advanced Tooling Design

Two interrelated systems: **Artifacts** (persistent files the agent creates and the UI renders) and a **Code Sandbox** (Elixir REPL the agent can execute code in). The sandbox can create artifacts, and artifacts can reference each other, making the two systems complementary.

---

## Artifacts

### What is an Artifact?

A file created by the agent, persisted in the session. Examples: HTML pages, data files, reports, images, Excel spreadsheets. Artifacts are **session-scoped** and **not branch-aware** — the conversation tree captures the history of artifact operations via tool calls, but navigating conversation branches does not rewind artifact state. This is a deliberate simplification; the alternative (reconstructing artifact state by replaying tool calls along the active path) is significantly more complex and not worth the tradeoff.

### Data Model

```elixir
%OmniUI.Artifacts.Artifact{
  id: String.t(),            # Filename (eg "report.html", "data.json")
  type: String.t(),          # Freeform, derived from file extension
  size: non_neg_integer(),   # File size in bytes
  updated_at: DateTime.t()   # From File.stat mtime
}
```

- Artifact **content** lives on disk (not in assigns).
- Artifact **metadata** lives in assigns as `%{id => %Artifact{}}` — a lightweight cached view of what's on disk.
- Metadata is **recovered by scanning** the session's artifacts directory on load. No separate metadata persistence needed.
- The `type` is freeform and derived from the file extension (`.html` -> `"html"`, `.jsx` -> `"jsx"`, `.xlsx` -> `"xlsx"`). Unknown types are fine — rendering falls back to download mode.

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
| `write` | `id`, `content`, `type` (optional) | Confirmation with file size |
| `patch` | `id`, `search`, `replace` | Confirmation, or error if search string not found |
| `get` | `id` | File content as string |
| `list` | (none) | List of artifact filenames with types and sizes |
| `delete` | `id` | Confirmation |

**`write`** is an upsert — creates the file if it doesn't exist, replaces content if it does. Type is derived from the file extension unless explicitly provided.

**`patch`** is a targeted find-replace edit. More token-efficient than `write` for small changes to large files. Returns an error result (not an exception) if the search string isn't found, so the agent can adjust.

Implemented as a **stateful Omni tool module** — `init/1` receives the session's artifacts directory path, `call/2` performs filesystem operations and returns text results.

```elixir
# Created when session_id is known:
tool = OmniUI.Artifacts.Tool.new(artifacts_path)
```

### HTTP Serving (ArtifactPlug)

`OmniUI.Artifacts.Plug` serves artifact files over HTTP. The developer mounts it in their router:

```elixir
forward "/omni_artifacts", OmniUI.Artifacts.Plug, base_path: "priv/omni/sessions"
```

Routes:

```
GET /omni_artifacts/{session_id}/{filename}
```

The Plug:
- Reads the file from disk
- Sets `Content-Type` based on file extension
- Sets `Content-Disposition: attachment` for binary types (triggers download in browser)
- Returns 404 for missing files
- **Sanitises the filename** to prevent directory traversal (`../` attacks)

**Why a Plug route instead of `srcdoc`?** Three reasons:
1. **Cross-artifact references** — `dashboard.html` can load `data.json` via relative path `./data.json` because both are served from the same base URL.
2. **Binary artifacts** — Excel files, images, PDFs can be downloaded via a link to the route.
3. **Memory** — artifact content stays on disk, not in the LiveView socket.

### UI

Side panel, similar to Claude's artifacts panel.

**Assigns:**

| Assign | Type | Purpose |
|--------|------|---------|
| `@artifacts` | `%{id => %Artifact{}}` | Metadata map, recovered from disk |
| `@active_artifact` | `String.t() \| nil` | Currently viewed artifact ID |
| `@artifacts_open` | `boolean` | Panel visibility |

**Panel components:**
- **Artifacts button** — visible when artifacts exist, toggles panel open/closed
- **Artifact list** — sidebar within the panel listing all artifacts by name
- **Artifact viewer** — renders the active artifact in the appropriate mode

**Rendering modes** (determined by file type):

| Mode | Types | How |
|------|-------|-----|
| Preview | `html`, `svg` | `<iframe src="/omni_artifacts/{session}/{file}">` with `sandbox="allow-scripts"` |
| View | text, code, `md`, `json`, `csv`, `jsx` | Syntax-highlighted code viewer |
| Download | `xlsx`, `pdf`, images, other binary | Download link to the Plug route (+ image preview for image types) |

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

Artifact and sandbox tools need the session's filesystem path, which depends on `session_id`. Since `session_id` comes from `handle_params`, these tools are added there:

**Flow:**

1. `mount/3` — `start_agent(socket, model: model)` with any session-independent tools
2. `handle_params/3` — session_id is determined. Create artifact/sandbox tools with the correct path. Add them to the agent via `Omni.Agent.add_tools/2`.
3. Session switch (new `handle_params`) — remove old tools, add new ones with the updated path.

The agent doesn't have artifact/sandbox tools until `handle_params` runs. In practice this is fine — the user can't submit a message until the page is connected and `handle_params` has executed.

**Syncing assigns after tool execution:**

The tool handlers run in the Agent process (not the LiveView process). When a tool executes, the LiveView receives an `{:agent, pid, :tool_result, result}` event. OmniUI's handler checks the tool name: if it's the artifacts or sandbox tool, it rescans the artifacts directory to update `@artifacts`.

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

---

## Implementation Plan

### Phase 1: Artifact Data Layer

Build the artifact data structures and filesystem operations. No UI, no agent integration yet — just the foundation that everything else builds on.

1. **`OmniUI.Artifacts.Artifact` struct** — id, type, size, updated_at. Constructor from `File.Stat`.
2. **`OmniUI.Artifacts.FileSystem` module** — filesystem operations:
   - `write(dir, id, content, opts)` — write file, return `%Artifact{}`
   - `read(dir, id)` — read file content
   - `patch(dir, id, search, replace)` — find-replace in file
   - `list(dir)` — scan directory, return `[%Artifact{}]`
   - `delete(dir, id)` — remove file
   - Path sanitisation (reject `..`, absolute paths, null bytes)
3. **`OmniUI.Artifacts.Tool` module** — Omni tool (stateful):
   - `use Omni.Tool` with schema defining the command discriminator
   - `init/1` receives artifacts directory path
   - `call/2` dispatches on command, delegates to `OmniUI.Artifacts.FileSystem`

### Phase 2: Artifact Wiring

Connect the artifact tool to the agent lifecycle and keep assigns in sync.

4. **Tool lifecycle helpers** — functions to create artifact (and later sandbox) tools with the correct session path. Called from `handle_params`.
5. **`handle_params` integration** — add tools when session_id is known, update on session change. Initially in `AgentLive`; later consider whether the macro should handle this.
6. **Artifact sync in Handlers** — when `:tool_result` fires for the artifacts tool, rescan the artifacts directory and update `@artifacts` assign.
7. **Session load** — scan the artifacts directory when loading an existing session, populate `@artifacts`.

### Phase 3: Artifact Serving

Enable HTTP access to artifacts for iframe rendering and downloads.

8. **`OmniUI.Artifacts.Plug`** — Plug module that serves files from the session's artifacts directory. Path sanitisation, content-type detection, 404 handling.
9. **Developer integration** — document the `forward` route the developer adds to their router.

### Phase 4: Artifact UI

Build the panel and rendering components.

10. **Artifact panel component** — panel layout with artifact list and viewer area. Panel toggle button. Assigns: `@artifacts`, `@active_artifact`, `@artifacts_open`.
11. **Iframe preview mode** — `<iframe>` loading from ArtifactPlug route. `sandbox="allow-scripts"` attribute.
12. **Code viewer mode** — syntax-highlighted `<pre>` block for text/code artifacts. Load content on demand (read from disk when artifact is selected).
13. **Download mode** — download link to ArtifactPlug route for binary types. Image preview for image types.
14. **Panel events** — `handle_event` clauses for opening/closing panel, selecting artifacts. These are UI-only events (no agent involvement).

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

### Phase 6: Sandbox-Artifact Bridge

Connect the sandbox to the artifact system.

18. **Artifacts API module for sandbox** — module injected into the peer node that performs file operations on the session's artifacts directory. Mirrors the tool commands (write, get, list, patch, delete).
19. **Artifact sync on sandbox result** — when the sandbox tool result comes back, rescan artifacts directory (same mechanism as Phase 2, step 6).

### Phase 7: Polish

20. **Inline artifact indicators** — when a `content_block` renders an artifact tool use, show a richer UI (artifact name, type icon, preview thumbnail) instead of raw JSON.
21. **Error handling** — graceful handling of disk errors, missing files, sandbox crashes.
22. **Documentation** — developer-facing docs for setting up artifacts and sandbox.

---

## Open Questions

To be resolved during implementation:

### 1. Artifact base path configuration

Currently proposed: derive from `Store.Filesystem`'s configured `base_path`, adding `/artifacts` under each session directory. This co-locates artifacts with session data, which is clean.

But this couples the artifact system to the filesystem adapter's path convention. If a developer uses a custom store adapter, or wants artifacts stored elsewhere, this doesn't work.

Options:
- **A.** Follow Store.Filesystem config (simple, co-located, coupled)
- **B.** Independent config: `config :omni_ui, OmniUI.Artifacts, base_path: "..."` (flexible, separate)
- **C.** Pass as option when creating the tool (explicit, per-LiveView)

Leaning toward **A** as default with **B** as override. Since the developer creates the tool explicitly and passes the path to `new/1`, they have full control regardless.

### 2. Sandbox result format

What the sandbox tool returns to the agent. Options range from plain stdout string to a structured envelope with status, output, error, and list of artifacts modified. The right format will become clearer during implementation — start simple and enrich as needed.

### 3. Panel auto-open behaviour

Whether the artifact panel opens automatically when the first artifact is created, stays manual-only, or uses a notification badge. Defer to UI implementation phase.

### 4. Inline artifact indicators

Whether `content_block/1` should render artifact tool uses differently from generic tool uses (eg show artifact name, type icon, "View" button). Deferred to Phase 7 polish — the default tool use rendering works as a starting point.
