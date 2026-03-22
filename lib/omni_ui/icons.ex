defmodule OmniUI.Icons do
  use Phoenix.Component

  attr :rest, :global

  def check(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-check", @rest.class]}>
      <path d="M20 6 9 17l-5-5"/>
    </svg>
    """
  end

  attr :rest, :global

  def chevron_down(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-chevron-down", @rest.class]}>
      <path d="m6 9 6 6 6-6"/>
    </svg>
    """
  end

  attr :rest, :global

  def cog(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-cog", @rest.class]}>
      <path d="M11 10.27 7 3.34"/>
      <path d="m11 13.73-4 6.93"/>
      <path d="M12 22v-2"/>
      <path d="M12 2v2"/>
      <path d="M14 12h8"/>
      <path d="m17 20.66-1-1.73"/>
      <path d="m17 3.34-1 1.73"/>
      <path d="M2 12h2"/>
      <path d="m20.66 17-1.73-1"/>
      <path d="m20.66 7-1.73 1"/>
      <path d="m3.34 17 1.73-1"/>
      <path d="m3.34 7 1.73 1"/>
      <circle cx="12" cy="12" r="2"/>
      <circle cx="12" cy="12" r="8"/>
    </svg>
    """
  end

  attr :rest, :global

  def copy(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-copy", @rest.class]}>
      <rect width="14"height="14" x="8" y="8" rx="2" ry="2"/>
      <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
    </svg>
    """
  end

  attr :rest, :global

  def sparkle(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-sparkle", @rest.class]}>
      <path d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"/>
    </svg>
    """
  end

  attr :rest, :global

  def circle_x(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-circle-x", @rest.class]}>
      <circle cx="12" cy="12" r="10"/>
      <path d="m15 9-6 6"/>
      <path d="m9 9 6 6"/>
    </svg>
    """
  end

  attr :rest, :global

  def arrow_up(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-arrow-up", @rest.class]}>
      <path d="m5 12 7-7 7 7"/>
      <path d="M12 19V5"/>
    </svg>
    """
  end

  attr :rest, :global

  def chart_no_axis(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-chart-no-axes-column", @rest.class]}>
      <path d="M5 21v-6"/>
      <path d="M12 21V3"/>
      <path d="M19 21V9"/>
    </svg>
    """
  end

  attr :rest, :global

  def cache(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-database-zap", @rest.class]}>
      <ellipse cx="12" cy="5" rx="9" ry="3"/>
      <path d="M3 5V19A9 3 0 0 0 15 21.84"/>
      <path d="M21 5V8"/>
      <path d="M21 12L18 17H22L19 22"/>
      <path d="M3 12A9 3 0 0 0 14.59 14.87"/>
    </svg>
    """
  end

  attr :rest, :global

  def send(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-send-horizontal", @rest.class]}>
      <path d="M3.714 3.048a.498.498 0 0 0-.683.627l2.843 7.627a2 2 0 0 1 0 1.396l-2.842 7.627a.498.498 0 0 0 .682.627l18-8.5a.5.5 0 0 0 0-.904z"/>
      <path d="M6 12h16"/>
    </svg>
    """
  end

  attr :rest, :global

  def shell(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-shell-icon lucide-shell", @rest.class]}>
      <path d="M14 11a2 2 0 1 1-4 0 4 4 0 0 1 8 0 6 6 0 0 1-12 0 8 8 0 0 1 16 0 10 10 0 1 1-20 0 11.93 11.93 0 0 1 2.42-7.22 2 2 0 1 1 3.16 2.44"/>
    </svg>
    """
  end

  attr :rest, :global

  def paperclip(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-paperclip", @rest.class]}>
      <path d="m16 6-8.414 8.586a2 2 0 0 0 2.829 2.829l8.414-8.586a4 4 0 1 0-5.657-5.657l-8.379 8.551a6 6 0 1 0 8.485 8.485l8.379-8.551"/>
    </svg>
    """
  end

  attr :rest, :global

  def x(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-x", @rest.class]}>
      <path d="M18 6 6 18"/>
      <path d="m6 6 12 12"/>
    </svg>
    """
  end

  attr :rest, :global

  def rotate(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["lucide lucide-rotate-cw", @rest.class]}>
      <path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/>
      <path d="M21 3v5h-5"/>
    </svg>
    """
  end
end
