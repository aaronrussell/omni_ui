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

  # ── heuristic/1 ────────────────────────────────────────────────────

  describe "heuristic/1" do
    test "returns the first user message text" do
      messages = [user("Deep dive into Elixir"), assistant("Sure!")]
      assert Title.heuristic(messages) == "Deep dive into Elixir"
    end

    test "trims surrounding whitespace" do
      assert Title.heuristic([user("  Hello world  ")]) == "Hello world"
    end

    test "truncates at word boundary when text exceeds 50 characters" do
      msg = user("What is Elixir and why should I use it for web development?")
      assert Title.heuristic([msg]) == "What is Elixir and why should I use it for web..."
    end

    test "hard-slices a single word that is longer than 50 characters" do
      long = String.duplicate("a", 60)
      result = Title.heuristic([user(long)])

      assert result == String.duplicate("a", 50) <> "..."
    end

    test "keeps full last word when slice ends exactly on a word boundary" do
      # Length before the trailing word is 50 chars; regex-based truncation
      # would have dropped "stuff" unnecessarily. reduce_while keeps it.
      text = "Hello world wonderful programming stuff wonderful! stuff"

      assert Title.heuristic([user(text)]) ==
               "Hello world wonderful programming stuff wonderful!..."
    end

    test "returns empty string when there are no user messages" do
      assert Title.heuristic([]) == ""
      assert Title.heuristic([assistant("Hello")]) == ""
    end

    test "returns empty string when the first user message has no text content" do
      image_msg =
        Omni.message(
          role: :user,
          content: [%Omni.Content.Attachment{media_type: "image/png", source: {:base64, "x"}}]
        )

      assert Title.heuristic([image_msg]) == ""
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

      assert Title.heuristic([msg]) == "hello world"
    end

    test "collapses internal whitespace runs (tabs, newlines, double spaces)" do
      assert Title.heuristic([user("hello\n\n\tworld   today")]) == "hello world today"
    end
  end

  # ── generate/3 with :heuristic ─────────────────────────────────────

  describe "generate/3 with :heuristic" do
    test "returns {:ok, title} when user text is present" do
      assert Title.generate(:heuristic, [user("What is Phoenix?")]) ==
               {:ok, "What is Phoenix?"}
    end

    test "returns {:error, :no_text} when there is no extractable text" do
      assert Title.generate(:heuristic, []) == {:error, :no_text}
      assert Title.generate(:heuristic, [assistant("Hi")]) == {:error, :no_text}
    end

    test "ignores any opts passed" do
      assert Title.generate(:heuristic, [user("Hello")], foo: :bar) == {:ok, "Hello"}
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
