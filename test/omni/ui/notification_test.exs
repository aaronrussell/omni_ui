defmodule Omni.UI.NotificationTest do
  use ExUnit.Case, async: true

  alias Omni.UI.Notification

  describe "new/3" do
    test "builds a notification with defaults" do
      notif = Notification.new(:info, "hello")

      assert %Notification{} = notif
      assert notif.level == :info
      assert notif.message == "hello"
      assert notif.timeout == 20_000
      assert is_integer(notif.id) and notif.id > 0
    end

    test "accepts all valid levels" do
      for level <- [:info, :success, :warning, :error] do
        notif = Notification.new(level, "msg")
        assert notif.level == level
      end
    end

    test "generates unique ids" do
      ids = for _ <- 1..10, do: Notification.new(:info, "msg").id
      assert Enum.uniq(ids) == ids
    end

    test "accepts a custom timeout" do
      notif = Notification.new(:info, "msg", timeout: 5_000)
      assert notif.timeout == 5_000
    end
  end
end
