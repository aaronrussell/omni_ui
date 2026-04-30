defmodule OmniUI.TitleTest do
  use ExUnit.Case, async: true

  alias OmniUI.Title

  @model {:anthropic, "claude-haiku-4-5"}

  defp user(text), do: Omni.message(role: :user, content: text)
  defp assistant(text), do: Omni.message(role: :assistant, content: text)

  defp stub_fixture(stub_name, fixture_path) do
    Req.Test.stub(stub_name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, File.read!(fixture_path))
    end)
  end

  defp stub_opts(stub_name), do: [api_key: "test-key", plug: {Req.Test, stub_name}]

  # ── generate/3 with nil model (heuristic) ──────────────────────────

  describe "generate/3 with nil model" do
    test "returns the first user message text" do
      messages = [user("Deep dive into Elixir"), assistant("Sure!")]
      assert Title.generate(nil, messages) == {:ok, "Deep dive into Elixir"}
    end

    test "uses the first message's text regardless of role" do
      assert Title.generate(nil, [assistant("Hello")]) == {:ok, "Hello"}
    end

    test "trims surrounding whitespace" do
      assert Title.generate(nil, [user("  Hello world  ")]) == {:ok, "Hello world"}
    end

    test "truncates at word boundary when text exceeds 50 characters" do
      msg = user("What is Elixir and why should I use it for web development?")

      assert Title.generate(nil, [msg]) ==
               {:ok, "What is Elixir and why should I use it for web..."}
    end

    test "hard-slices a single word that is longer than 50 characters" do
      long = String.duplicate("a", 60)

      assert Title.generate(nil, [user(long)]) ==
               {:ok, String.duplicate("a", 50) <> "..."}
    end

    test "keeps full last word when slice ends exactly on a word boundary" do
      # Length before the trailing word is 50 chars; regex-based truncation
      # would have dropped "stuff" unnecessarily. reduce_while keeps it.
      text = "Hello world wonderful programming stuff wonderful! stuff"

      assert Title.generate(nil, [user(text)]) ==
               {:ok, "Hello world wonderful programming stuff wonderful!..."}
    end

    test "returns {:error, :no_text} for an empty messages list" do
      assert Title.generate(nil, []) == {:error, :no_text}
    end

    test "normalises whitespace so newlines between text blocks collapse to single spaces" do
      msg =
        Omni.message(
          role: :user,
          content: [
            %Omni.Content.Text{text: "hello"},
            %Omni.Content.Text{text: "world"}
          ]
        )

      assert Title.generate(nil, [msg]) == {:ok, "hello world"}
    end

    test "collapses internal whitespace runs (tabs, newlines, double spaces)" do
      assert Title.generate(nil, [user("hello\n\n\tworld   today")]) ==
               {:ok, "hello world today"}
    end

    test "ignores any opts passed" do
      assert Title.generate(nil, [user("Hello")], foo: :bar) == {:ok, "Hello"}
    end
  end

  # ── generate/3 with a model ────────────────────────────────────────

  describe "generate/3 with a model" do
    test "returns {:error, :no_text} when conversation has no text content (no HTTP call)" do
      image_msg =
        Omni.message(
          role: :user,
          content: [%Omni.Content.Attachment{media_type: "image/png", source: {:base64, "x"}}]
        )

      assert Title.generate({:anthropic, "claude-haiku-4-5"}, [image_msg]) ==
               {:error, :no_text}
    end

    test "returns the generated title from a stubbed LLM response" do
      stub_fixture(:title_clean, "test/support/fixtures/anthropic_title.sse")

      messages = [user("Tell me about Phoenix"), assistant("It's a web framework...")]

      assert Title.generate(@model, messages, stub_opts(:title_clean)) ==
               {:ok, "Phoenix framework intro"}
    end

    test "normalises whitespace in the model's response" do
      stub_fixture(:title_messy, "test/support/fixtures/anthropic_title_messy.sse")

      messages = [user("Intro to Elixir"), assistant("...")]

      assert Title.generate(@model, messages, stub_opts(:title_messy)) ==
               {:ok, "Elixir web basics"}
    end
  end
end
