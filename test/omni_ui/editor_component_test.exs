defmodule OmniUI.EditorComponentTest do
  use OmniUI.ComponentCase, async: true

  alias OmniUI.EditorComponent

  describe "render" do
    test "renders textarea with placeholder" do
      html = render_component(EditorComponent, id: "editor")

      assert html =~ "Type your message here..."
      assert html =~ "<textarea"
      assert html =~ ~s(name="input")
    end

    test "renders submit button" do
      html = render_component(EditorComponent, id: "editor")

      assert html =~ ~s(type="submit")
    end

    test "renders attach label" do
      html = render_component(EditorComponent, id: "editor")

      assert html =~ "Attach"
    end

    test "renders form with correct events" do
      html = render_component(EditorComponent, id: "editor")

      assert html =~ ~s(phx-submit="submit")
      assert html =~ ~s(phx-change="change")
    end

    test "renders drop target" do
      html = render_component(EditorComponent, id: "editor")

      assert html =~ "phx-drop-target"
      assert html =~ "Drop files here"
    end

    test "does not render attachment tiles when no uploads" do
      html = render_component(EditorComponent, id: "editor")

      # The attachment section should not be rendered (it has :if guard)
      refute html =~ "cancel-upload"
    end
  end
end
