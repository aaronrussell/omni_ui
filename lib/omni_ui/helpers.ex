defmodule OmniUI.Helpers do
  def markdown(text) do
    text
    |> MDEx.to_html!()
    |> Phoenix.HTML.raw()
  end

  def format_usage(%Omni.Usage{} = usage) do
    [:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :total_cost]
    |> Enum.map(&{&1, Map.get(usage, &1)})
    |> Enum.map(fn
      {:input_tokens, value} -> "↑#{format_token_count(value)}"
      {:output_tokens, value} -> "↓#{format_token_count(value)}"
      {:cache_read_tokens, value} -> "R#{format_token_count(value)}"
      {:cache_write_tokens, value} -> "W#{format_token_count(value)}"
      {:total_cost, value} -> "$#{format_token_cost(value)}"
    end)
    |> Enum.join(" ")
  end

  def format_token_count(count) when count < 1000, do: Integer.to_string(count)
  def format_token_count(count) when count < 10_000, do: "#{Float.round(count / 1000, 1)}k"
  def format_token_count(count), do: "#{round(count / 1000)}k"

  def format_token_cost(cost), do: :erlang.float_to_binary(cost / 1, decimals: 4)
end
