defmodule OmniUI.REPL.Tool do
  @moduledoc """
  Omni tool for executing Elixir code in a sandboxed peer node.

  Each invocation runs in a fresh Erlang peer node with a clean slate.
  IO output is captured and returned alongside the expression result.

  ## Usage

      tool = OmniUI.REPL.Tool.new()
      tool = OmniUI.REPL.Tool.new(timeout: 30_000, max_output: 10_000)

  Then add the tool to the agent via `update_agent(socket, tools: [tool])`.
  """

  use Omni.Tool,
    name: "repl",
    description: """
    Execute Elixir code in a sandboxed peer node.

    ## When to Use
    - Calculations and data transformations
    - Testing code snippets and exploring APIs
    - Processing, analysing, or generating data
    - Verifying assumptions about Elixir behaviour

    ## Environment
    - Full Elixir/Erlang standard library
    - Each invocation is a fresh VM — no state persists between calls
    - Available libraries include Req (HTTP client) and Jason (JSON)

    ## Adding Packages
    Mix.install/1 can add any Hex package. It can only be called once per \
    invocation, so install everything you need in a single call:
    Mix.install([:csv, :explorer, :xlsx_reader])  # CSV, dataframes, Excel

    ## Output
    - IO output (IO.puts, IO.inspect, etc.) is captured and returned to you
    - The return value of the last expression is always shown
    - The user does not see raw output — summarise key findings in your response

    ## Example
    numbers = [10, 20, 15, 25]
    sum = Enum.sum(numbers)
    avg = sum / length(numbers)
    IO.puts("Sum: \#{sum}, Average: \#{avg}")

    ## Important Notes
    - Be intentional about return values — end with :ok if only IO output matters
    - For large data, use IO.inspect(data, limit: 20) rather than returning the full structure
    - Define modules freely — they exist only for the current invocation\
    """

  alias OmniUI.REPL.Sandbox

  @impl Omni.Tool
  def schema do
    import Omni.Schema

    object(
      %{
        title:
          string(
            description:
              "Brief title describing what the code achieves in active form, e.g. 'Calculating average score'"
          ),
        code: string(description: "Elixir code to evaluate")
      },
      required: [:title, :code]
    )
  end

  @impl Omni.Tool
  def init(opts) do
    opts = opts || []
    Keyword.take(opts, [:timeout, :max_output])
  end

  @impl Omni.Tool
  def call(%{code: code}, opts) do
    case Sandbox.run(code, opts) do
      {:ok, %{output: output, result: result}} ->
        format_success(output, result)

      {:error, :timeout, %{output: output}} ->
        raise format_error(output, "Execution timed out")

      {:error, :noconnection, %{output: output}} ->
        raise format_error(output, "Sandbox node crashed")

      {:error, {kind, reason, stacktrace}, %{output: output}} ->
        raise format_error(output, Exception.format(kind, reason, stacktrace))
    end
  end

  defp format_success(output, result) do
    inspected = inspect(result, pretty: true)

    case output do
      "" -> "=> #{inspected}"
      _ -> "#{output}\n=> #{inspected}"
    end
  end

  defp format_error("", message), do: message
  defp format_error(output, message), do: "#{output}\n#{message}"
end
