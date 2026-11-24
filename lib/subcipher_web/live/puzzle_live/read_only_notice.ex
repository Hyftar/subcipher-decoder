defmodule SubcipherWeb.PuzzleLive.ReadOnlyNotice do
  @moduledoc "Tells visitors of a shared puzzle that they can't change it."
  use SubcipherWeb, :html

  def read_only_notice(assigns) do
    ~H"""
    <div
      id="read-only"
      class="flex items-center gap-3 rounded-xl bg-info/10 px-4 py-3 text-sm"
    >
      <.icon name="hero-eye" class="size-5 shrink-0 text-info" />
      <p>
        A puzzle shared by someone else: you can look around, but not change it.
      </p>
    </div>
    """
  end
end
