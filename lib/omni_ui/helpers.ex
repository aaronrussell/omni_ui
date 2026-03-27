defmodule OmniUI.Helpers do
  def attachment_url(%Omni.Content.Attachment{source: {:base64, data}} = content) do
    "data:#{content.media_type};base64,#{data}"
  end

  def attachment_url(%Omni.Content.Attachment{source: {:url, url}}), do: url

  def cls(input) when is_list(input) do
    input
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  def format_json(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, json} -> format_json(json)
      {:error, _} -> str
    end
  end

  def format_json(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(data)
    end
  end

  def format_tool_result(%Omni.Content.ToolResult{} = result) do
    result.content
    |> Enum.filter(&match?(%Omni.Content.Text{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join("\n")
    |> format_json()
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

  def model_key(%Omni.Model{} = model) do
    {provider_id, model_id} = Omni.Model.to_ref(model)
    "#{provider_id}:#{model_id}"
  end

  def sibling_pos(id, siblings) do
    index = Enum.find_index(siblings, &(&1 == id))
    "#{index + 1}/#{length(siblings)}"
  end

  def to_md(text) do
    MDEx.new(markdown: text, streaming: true)
    |> MDExGFM.attach()
    |> MDExMermaid.attach()
    |> MDEx.to_html!(
      syntax_highlight: [
        formatter: {:html_inline, theme: "catppuccin_macchiato"}
      ]
    )
    |> Phoenix.HTML.raw()
  end
end
