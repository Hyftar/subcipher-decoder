defmodule SubcipherWeb.VisibilityComponents do
  @moduledoc "The public / private switch of puzzles and algorithms."
  use Phoenix.Component

  import SubcipherWeb.CoreComponents, only: [icon: 1]

  attr :public, :boolean, required: true
  attr :event, :string, default: "toggle_public"

  @doc """
  Shows whether the page's puzzle or algorithm is public or private; a
  click switches (sends `event`).
  """
  def visibility_toggle(assigns) do
    ~H"""
    <button
      type="button"
      id="visibility"
      phx-click={@event}
      aria-pressed={to_string(@public)}
      title={
        if @public,
          do: "Public: everyone can see it, read-only. Click to make it private.",
          else: "Private: only you can see it. Click to make it public."
      }
      class={[
        "btn btn-sm gap-1.5 transition-colors",
        if(@public, do: "btn-soft btn-success", else: "btn-ghost")
      ]}
    >
      <.icon name={if @public, do: "hero-globe-alt", else: "hero-lock-closed"} class="size-4" />
      {if @public, do: "Public", else: "Private"}
    </button>
    """
  end
end
