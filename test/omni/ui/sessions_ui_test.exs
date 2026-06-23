defmodule Omni.UI.SessionsUITest do
  use Omni.UI.ComponentCase, async: true

  import Omni.UI.SessionsUI

  defp sample_session(overrides \\ %{}) do
    Map.merge(
      %{
        id: "sess-1",
        title: "First chat",
        status: nil,
        updated_at: ~U[2026-03-15 10:00:00Z]
      },
      overrides
    )
  end

  # ── session_list/1 ───────────────────────────────────────────────

  describe "session_list/1" do
    test "renders empty state with default label" do
      assigns = %{sessions: [], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "No sessions yet"
    end

    test "renders empty state with custom label" do
      assigns = %{sessions: [], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} empty_label="Nothing here" />
        """)

      assert html =~ "Nothing here"
    end

    test "renders session titles" do
      sessions = [
        sample_session(%{id: "s1", title: "Chat about Elixir"}),
        sample_session(%{id: "s2", title: "Bug investigation"})
      ]

      assigns = %{sessions: sessions, target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "Chat about Elixir"
      assert html =~ "Bug investigation"
    end

    test "renders Untitled for sessions without a title" do
      assigns = %{sessions: [sample_session(%{title: nil})], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "Untitled"
    end

    test "session rows fire open_session event" do
      assigns = %{sessions: [sample_session()], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ ~s(phx-click="open_session")
      assert html =~ ~s(phx-value-session-id="sess-1")
    end

    test "highlights current session" do
      assigns = %{sessions: [sample_session()], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} current_id="sess-1" target={@target} />
        """)

      assert html =~ "bg-omni-accent-2/10"
    end

    test "does not highlight non-current session" do
      assigns = %{sessions: [sample_session()], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} current_id="other" target={@target} />
        """)

      refute html =~ "bg-omni-accent-2/10"
    end

    test "renders busy status with spinning icon" do
      assigns = %{sessions: [sample_session(%{status: :busy})], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "animate-spin"
    end

    test "renders paused status with amber icon" do
      assigns = %{sessions: [sample_session(%{status: :paused})], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "text-amber-500"
    end

    test "renders idle status icon" do
      assigns = %{sessions: [sample_session(%{status: :idle})], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "text-omni-accent-2"
    end

    test "renders nil status with dashed icon" do
      assigns = %{sessions: [sample_session(%{status: nil})], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      refute html =~ "animate-spin"
      refute html =~ "text-amber-500"
    end

    test "renders rename form with session id" do
      assigns = %{sessions: [sample_session()], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ ~s(id="rename-form-sess-1")
      assert html =~ ~s(phx-submit=)
    end

    test "renders delete button" do
      assigns = %{sessions: [sample_session()], target: nil}

      html =
        rendered_to_string(~H"""
        <.session_list sessions={@sessions} target={@target} />
        """)

      assert html =~ "Delete session"
      assert html =~ "Sure?"
    end
  end
end
