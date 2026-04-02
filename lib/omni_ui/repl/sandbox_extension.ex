defmodule OmniUI.REPL.SandboxExtension do
  @moduledoc """
  Behaviour for extending the REPL sandbox environment.

  Extensions inject code and documentation into the sandbox. The code is
  evaluated in the peer node before the user's code runs. The description
  is appended to the REPL tool's description so the agent knows what
  additional capabilities are available.

  ## Implementing an extension

      defmodule MyApp.SandboxExtension do
        @behaviour OmniUI.REPL.SandboxExtension

        @impl true
        def code(opts) do
          api_key = Keyword.fetch!(opts, :api_key)

          quote do
            defmodule MyAPI do
              def fetch(path) do
                Req.get!(path, headers: [{"authorization", unquote(api_key)}]).body
              end
            end
          end
        end

        @impl true
        def description(_opts) do
          \"""
          ## MyAPI (in sandbox)
          - `MyAPI.fetch(path)` — authenticated GET request
          \"""
        end
      end

  ## Using extensions

  Pass extensions to `OmniUI.REPL.Tool.new/1`:

      REPL.Tool.new(extensions: [{MyApp.SandboxExtension, api_key: "sk-..."}])

  Bare modules (without opts) are also accepted:

      REPL.Tool.new(extensions: [MyApp.SandboxExtension])
  """

  @typedoc "Code to evaluate in the sandbox — AST (preferred) or a string."
  @type setup_code :: String.t() | Macro.t()

  @doc """
  Returns code to evaluate in the sandbox before the user's code.

  Receives the opts from the `{module, opts}` tuple in the extensions list.
  Return a quoted expression (preferred) or a code string. The code is
  evaluated in the peer node before IO capture begins.
  """
  @callback code(opts :: keyword()) :: setup_code()

  @doc """
  Returns a description fragment appended to the REPL tool description.

  Receives the same opts as `code/1`. The returned string should document
  the APIs made available by `code/1` so the agent knows how to use them.
  """
  @callback description(opts :: keyword()) :: String.t()
end
