defmodule OmniUI.Notification do
  @moduledoc """
  A single notification shown in the OmniUI toaster.

  Built via `OmniUI.notify/2` or `OmniUI.notify/3`. The id is generated on
  construction and used by the stream + FIFO-cap bookkeeping.
  """

  @type level :: :info | :success | :warning | :error

  @type t :: %__MODULE__{
          id: integer(),
          level: level(),
          message: String.t(),
          timeout: non_neg_integer()
        }

  @default_timeout 20_000

  @enforce_keys [:id, :level, :message, :timeout]
  defstruct [:id, :level, :message, :timeout]

  @doc """
  Builds a notification.

  ## Options

    * `:timeout` — ms until auto-dismiss (default `#{@default_timeout}`).
  """
  @spec new(level(), String.t(), keyword()) :: t()
  def new(level, message, opts \\ [])
      when level in [:info, :success, :warning, :error] and is_binary(message) do
    %__MODULE__{
      id: System.unique_integer([:positive]),
      level: level,
      message: message,
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end
end
