defmodule Omni.UI.CoreUITest do
  use Omni.UI.ComponentCase, async: true

  alias Omni.UI.Notification

  # ── panel/1 ──────────────────────────────────────────────────────

  describe "panel/1" do
    test "renders title via default panel_header" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel title="Files">
          <p>body</p>
        </.panel>
        """)

      assert html =~ "Files"
      assert html =~ "body"
    end

    test "custom header slot replaces default panel_header" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel>
          <:header><div class="custom-hdr">Custom</div></:header>
          <p>body</p>
        </.panel>
        """)

      assert html =~ "custom-hdr"
      assert html =~ "Custom"
      refute html =~ "panel_header"
    end

    test "passes body_class to body container" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel title="T" body_class="p-6">
          <p>body</p>
        </.panel>
        """)

      assert html =~ "p-6"
    end
  end

  # ── panel_header/1 ───────────────────────────────────────────────

  describe "panel_header/1" do
    test "renders title text" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="Sessions" />
        """)

      assert html =~ "Sessions"
    end

    test "center alignment uses three-column grid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="T" align="center" />
        """)

      assert html =~ "grid-cols-[1fr_auto_1fr]"
    end

    test "left alignment uses auto-width grid" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="T" align="left" />
        """)

      assert html =~ "grid-cols-[auto_1fr_auto]"
    end

    test "renders left slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="T">
          <:left><button>Back</button></:left>
        </.panel_header>
        """)

      assert html =~ "Back"
    end

    test "renders right slot" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="T">
          <:right><button>Close</button></:right>
        </.panel_header>
        """)

      assert html =~ "Close"
    end

    test "title spans two columns when only right slot given" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.panel_header title="T">
          <:right><button>X</button></:right>
        </.panel_header>
        """)

      assert html =~ "col-span-2"
    end
  end

  # ── select/1 ─────────────────────────────────────────────────────

  describe "select/1" do
    test "renders prompt when no value selected" do
      assigns = %{
        options: [%{label: "Option A", value: "a"}, %{label: "Option B", value: "b"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} event="pick" />
        """)

      assert html =~ "Select..."
    end

    test "renders selected label when value matches" do
      assigns = %{
        options: [%{label: "Option A", value: "a"}, %{label: "Option B", value: "b"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} value="b" event="pick" />
        """)

      assert html =~ "Option B"
    end

    test "renders custom prompt" do
      assigns = %{
        options: [%{label: "A", value: "a"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} prompt="Choose one" event="pick" />
        """)

      assert html =~ "Choose one"
    end

    test "renders flat options as buttons" do
      assigns = %{
        options: [%{label: "Alpha", value: "a"}, %{label: "Beta", value: "b"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} event="pick" />
        """)

      assert html =~ "Alpha"
      assert html =~ "Beta"
    end

    test "renders grouped options with group label" do
      assigns = %{
        options: [
          %{label: "Group 1", options: [%{label: "A", value: "a"}]},
          %{label: "Group 2", options: [%{label: "B", value: "b"}]}
        ]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} event="pick" />
        """)

      assert html =~ "Group 1"
      assert html =~ "Group 2"
      assert html =~ "A"
      assert html =~ "B"
    end

    test "highlights selected option with accent class" do
      assigns = %{
        options: [%{label: "A", value: "a"}, %{label: "B", value: "b"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} value="a" event="pick" />
        """)

      assert html =~ ~r/text-omni-accent-1"[^>]*>\s*A/s
    end

    test "position above renders bottom-full" do
      assigns = %{
        options: [%{label: "A", value: "a"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} event="pick" position="above" />
        """)

      assert html =~ "bottom-full"
    end

    test "position below renders top-full" do
      assigns = %{
        options: [%{label: "A", value: "a"}]
      }

      html =
        rendered_to_string(~H"""
        <.select id="sel" options={@options} event="pick" position="below" />
        """)

      assert html =~ "top-full"
    end
  end

  # ── notifications/1 ──────────────────────────────────────────────

  describe "notifications/1" do
    test "renders notification message" do
      n = Notification.new(:info, "File saved")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "File saved"
    end

    test "renders dismiss button with notification id" do
      n = Notification.new(:info, "Hello")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "omni:dismiss"
      assert html =~ to_string(n.id)
    end

    test "renders info level with info icon" do
      n = Notification.new(:info, "Info msg")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "border-omni-border-2"
    end

    test "renders success level with green border" do
      n = Notification.new(:success, "Done")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "border-green-500/50"
    end

    test "renders warning level with amber border" do
      n = Notification.new(:warning, "Watch out")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "border-amber-500/50"
    end

    test "renders error level with red border" do
      n = Notification.new(:error, "Failed")
      assigns = %{stream: [{"notif-#{n.id}", n}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "border-red-500/50"
    end

    test "renders multiple notifications" do
      n1 = Notification.new(:info, "First")
      n2 = Notification.new(:error, "Second")
      assigns = %{stream: [{"notif-#{n1.id}", n1}, {"notif-#{n2.id}", n2}]}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "First"
      assert html =~ "Second"
    end

    test "renders empty when stream is empty" do
      assigns = %{stream: []}

      html =
        rendered_to_string(~H"""
        <.notifications stream={@stream} />
        """)

      assert html =~ "omni-notifications"
      refute html =~ "omni:dismiss"
    end
  end
end
