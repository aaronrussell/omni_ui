defmodule OmniUI.Helpers do
  @moduledoc """
  Shared helper functions used across OmniUI components.

  Provides utilities for formatting token usage, building CSS class lists,
  rendering markdown, and working with Omni data structures.
  """

  # Markdown typography styles applied at the chat_interface level via descendant
  # selectors targeting the `.mdex` class. This keeps the markdown component's HTML
  # minimal while defining styles once in the DOM.
  @markdown_styles ~w"""
  [&_.mdex>*:first-child]:mt-0! [&_.mdex>*:last-child]:mb-0!
  [&_.mdex_p,ul,ol,h1,h2,h3,h4,h5,h6]:mb-4 [&_.mdex_p,ul,ol,h1,h2,h3,h4,h5,h6]:max-w-prose
  [&_.mdex_h1,h2]:mt-12 [&_.mdex_h3]:mt-6
  [&_.mdex_h1,h2,h4,h5,h6]:font-bold [&_.mdex_h3,h5]:italic
  [&_.mdex_h1]:text-3xl [&_.mdex_h1]:font-black
  [&_.mdex_h2]:text-2xl [&_.mdex_h2]:font-bold
  [&_.mdex_h3]:text-xl [&_.mdex_h3]:font-bold
  [&_.mdex_h4]:text-lg [&_.mdex_h4]:font-bold
  [&_.mdex_h5]:font-bold
  [&_.mdex_h6]:font-medium [&_.mdex_h6]:italic
  [&_.mdex_ul]:list-disc [&_.mdex_ul]:pl-5
  [&_.mdex_ol]:list-decimal [&_.mdex_ol]:pl-5
  [&_.mdex_li]:my-0.5
  [&_.mdex_table,pre,img,hr]:my-6
  [&_.mdex_table]:w-full [&_.mdex_table]:table-fixed [&_.mdex_table]:text-sm
  [&_.mdex_table]:border [&_.mdex_table]:border-separate [&_.mdex_table]:border-spacing-0 [&_.mdex_table]:rounded-xl
  [&_.mdex_table]:border-omni-border-3
  [&_.mdex_thead_th]:border-b [&_.mdex_thead_th]:border-omni-border-3
  [&_.mdex_th,td]:text-left [&_.mdex_th,td]:p-2.5
  [&_.mdex_tbody>tr]:odd:bg-omni-bg-2
  [&_.mdex_pre]:-mx-6 [&_.mdex_pre]:px-6 [&_.mdex_pre]:py-5 [&_.mdex_pre]:rounded-xl [&_.mdex_pre]:overflow-auto
  [&_.mdex_hr]:h-px [&_.mdex_hr]:bg-omni-border-2 [&_.mdex_hr]:border-none
  [&_.mdex_a]:font-medium [&_.mdex_a]:hover:underline [&_.mdex_a]:transition-colors
  [&_.mdex_a]:text-omni-accent-1 [&_.mdex_a]:hover:text-omni-accent-2
  [&_.mdex_code]:text-sm [&_.mdex_code]:leading-[1.625] [&_.mdex_code]:font-mono
  [&_.mdex_:not(pre)>code]:px-1 [&_.mdex_:not(pre)>code]:py-0.5 [&_.mdex_:not(pre)>code]:rounded-sm
  [&_.mdex_:not(pre)>code]:bg-omni-bg-1
  """

  @doc """
  Returns a URL for an `Omni.Content.Attachment`.

  For base64-encoded attachments, returns a data URI. For URL-sourced
  attachments, returns the URL as-is.

  ## Examples

      iex> attachment = %Omni.Content.Attachment{media_type: "image/png", source: {:base64, "abc123"}}
      iex> OmniUI.Helpers.attachment_url(attachment)
      "data:image/png;base64,abc123"

      iex> attachment = %Omni.Content.Attachment{media_type: "image/png", source: {:url, "https://example.com/img.png"}}
      iex> OmniUI.Helpers.attachment_url(attachment)
      "https://example.com/img.png"
  """
  @spec attachment_url(Omni.Content.Attachment.t()) :: String.t()
  def attachment_url(%Omni.Content.Attachment{source: {:base64, data}} = content) do
    "data:#{content.media_type};base64,#{data}"
  end

  def attachment_url(%Omni.Content.Attachment{source: {:url, url}}), do: url

  @doc """
  Builds a CSS class string from various input formats.

  Accepts a string, a list, or a map:

  - **String** — returned as-is.
  - **List** — falsy values (`nil`, `false`) are filtered out, remaining
    entries are joined with spaces.
  - **Map** — keys whose values are truthy are included, joined with spaces.

  ## Examples

      iex> OmniUI.Helpers.cls("foo bar")
      "foo bar"

      iex> OmniUI.Helpers.cls(["foo", nil, "bar", false])
      "foo bar"

      iex> OmniUI.Helpers.cls(%{"active" => true, "hidden" => false})
      "active"
  """
  @spec cls(String.t()) :: String.t()
  @spec cls(list()) :: String.t()
  @spec cls(map()) :: String.t()
  def cls(input) when is_binary(input), do: input

  def cls(input) when is_list(input) do
    input
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  def cls(input) when is_map(input) do
    input
    |> Enum.flat_map(fn {key, value} -> if value, do: [key], else: [] end)
    |> Enum.join(" ")
  end

  @doc """
  Pretty-prints a value as JSON.

  When given a string, attempts to decode it as JSON first. If decoding
  succeeds, re-encodes it with pretty formatting. If the input is already
  a decoded data structure, encodes it directly. Falls back to the original
  string or `inspect/1` if encoding fails.

  ## Examples

      iex> OmniUI.Helpers.format_json(~s|{"a":1}|)
      ~s|{\\n  "a": 1\\n}|

      iex> OmniUI.Helpers.format_json("not json")
      "not json"

      iex> OmniUI.Helpers.format_json(%{"key" => "value"})
      ~s|{\\n  "key": "value"\\n}|
  """
  @spec format_json(String.t() | term()) :: String.t()
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

  @doc """
  Extracts and pretty-prints the text content from a tool result.

  Filters for `Omni.Content.Text` entries in the result's content list,
  joins their text, and formats the combined string as JSON.

  ## Examples

      iex> result = %Omni.Content.ToolResult{tool_use_id: "1", name: "search", content: [%Omni.Content.Text{text: ~s|{"ok":true}|}]}
      iex> OmniUI.Helpers.format_tool_result(result)
      ~s|{\\n  "ok": true\\n}|
  """
  @spec format_tool_result(Omni.Content.ToolResult.t()) :: String.t()
  def format_tool_result(%Omni.Content.ToolResult{} = result) do
    result.content
    |> Enum.filter(&match?(%Omni.Content.Text{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join("\n")
    |> format_json()
  end

  @doc """
  Formats a token count for compact display.

  Counts under 1,000 are shown as-is. Counts from 1,000–9,999 are shown
  with one decimal place (e.g. `"1.5k"`). Counts of 10,000+ are rounded
  to the nearest thousand (e.g. `"42k"`). Returns `"-"` for `nil`.

  ## Examples

      iex> OmniUI.Helpers.format_token_count(500)
      "500"

      iex> OmniUI.Helpers.format_token_count(1_500)
      "1.5k"

      iex> OmniUI.Helpers.format_token_count(42_000)
      "42k"

      iex> OmniUI.Helpers.format_token_count(nil)
      "-"
  """
  @spec format_token_count(non_neg_integer() | nil) :: String.t()
  def format_token_count(nil), do: "-"
  def format_token_count(count) when count < 1000, do: Integer.to_string(count)
  def format_token_count(count) when count < 10_000, do: "#{Float.round(count / 1000, 1)}k"
  def format_token_count(count), do: "#{round(count / 1000)}k"

  @doc """
  Formats a token cost as a dollar amount with 4 decimal places.

  Returns `"-"` for `nil`.

  ## Examples

      iex> OmniUI.Helpers.format_token_cost(0.0123)
      "0.0123"

      iex> OmniUI.Helpers.format_token_cost(nil)
      "-"
  """
  @spec format_token_cost(number() | nil) :: String.t()
  def format_token_cost(nil), do: "-"

  def format_token_cost(cost) do
    :erlang.float_to_binary(cost * 1.0, decimals: 4)
  end

  @doc """
  Syntax-highlights a code string as HTML.

  Uses Lumis with inline styles (catppuccin_macchiato theme) so the output
  is self-contained — no external CSS needed. When `lang` is `nil`, Lumis
  auto-detects the language. The `lang` value can be a language name
  (`"elixir"`, `"json"`) or a filename (`"report.html"`).

  Returns a `Phoenix.HTML.safe/0` tuple for direct use in HEEx templates.
  """
  @spec highlight_code(String.t(), String.t() | nil) :: Phoenix.HTML.safe()
  def highlight_code(code, lang \\ nil) do
    formatter = {:html_inline, theme: "catppuccin_macchiato"}

    code
    |> String.trim()
    |> Lumis.highlight!(language: lang, formatter: formatter)
    |> Phoenix.HTML.raw()
  end

  @doc """
  Returns a string key for an `Omni.Model` in `"provider:model"` format.

  Uses `Omni.Model.to_ref/1` to resolve the provider atom and model ID,
  then joins them with a colon.
  """
  @spec model_key(Omni.Model.t()) :: String.t()
  def model_key(%Omni.Model{} = model) do
    {provider_id, model_id} = Omni.Model.to_ref(model)
    "#{provider_id}:#{model_id}"
  end

  @doc """
  Returns a human-readable position string like `"2/5"` for an element
  among its siblings.

  ## Examples

      iex> OmniUI.Helpers.sibling_pos(:b, [:a, :b, :c])
      "2/3"
  """
  @spec sibling_pos(term(), list()) :: String.t()
  def sibling_pos(id, siblings) do
    index = Enum.find_index(siblings, &(&1 == id))
    "#{index + 1}/#{length(siblings)}"
  end

  @doc """
  TODO
  """
  @spec md_styles() :: String.t()
  def md_styles(), do: @markdown_styles

  @doc """
  Converts a markdown string to HTML using MDEx with GFM and Mermaid support.

  Returns a `Phoenix.HTML.safe/0` tuple for direct use in HEEx templates.

  ## Options

    * `:streaming` - when `true`, enables MDEx streaming mode for incremental
      rendering of in-progress content. Defaults to `false`.
  """
  @spec to_md(String.t(), keyword()) :: Phoenix.HTML.safe()
  def to_md(text, opts \\ []) do
    streaming = Keyword.get(opts, :streaming, false)

    MDEx.new(markdown: text, streaming: streaming)
    |> MDExGFM.attach()
    |> MDExMermaid.attach()
    |> MDEx.to_html!(
      syntax_highlight: [
        formatter: {:html_inline, theme: "catppuccin_macchiato"}
      ]
    )
    |> Phoenix.HTML.raw()
  end

  @doc """
  Formats a list of `Omni.Model` structs into grouped select options.

  Groups models by provider name, sorts both groups and models alphabetically,
  and returns a list of `%{label: provider, options: [%{value: key, label: name}]}` maps
  suitable for the `select` component. Returns `nil` for `nil` or empty input.
  """
  @spec format_model_options([Omni.Model.t()] | nil) :: [map()] | nil
  def format_model_options(nil), do: nil
  def format_model_options([]), do: nil

  def format_model_options(models) do
    models
    |> Enum.group_by(&(&1.provider |> Module.split() |> List.last()))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {provider_name, provider_models} ->
      %{
        label: provider_name,
        options:
          provider_models
          |> Enum.sort_by(& &1.name)
          |> Enum.map(&%{value: model_key(&1), label: &1.name})
      }
    end)
  end

  @doc """
  Finds the label for a value in a flat or grouped options list.

  Searches through options of the form `%{value: v, label: l}` or grouped
  options `%{options: [%{value: v, label: l}]}`. Returns the matching label
  or `nil` if not found.

  ## Examples

      iex> options = [%{value: "a", label: "Alpha"}, %{value: "b", label: "Beta"}]
      iex> OmniUI.Helpers.find_option_label(options, "b")
      "Beta"

      iex> grouped = [%{label: "Group", options: [%{value: "x", label: "X-ray"}]}]
      iex> OmniUI.Helpers.find_option_label(grouped, "x")
      "X-ray"

      iex> OmniUI.Helpers.find_option_label([%{value: "a", label: "A"}], "z")
      nil
  """
  @spec find_option_label([map()], String.t() | nil) :: String.t() | nil
  def find_option_label(options, value) do
    Enum.find_value(options, fn
      %{value: v, label: label} ->
        if(v == value, do: label)

      %{options: items} ->
        Enum.find_value(items, fn %{value: v, label: label} -> if(v == value, do: label) end)
    end)
  end
end
