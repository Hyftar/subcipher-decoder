defmodule SubcipherWeb.Components.Accordion do
  @moduledoc """
  A collapsible section: a clickable header and content shown when open.

  Opening and closing happens in the browser only (`Phoenix.LiveView.JS`,
  no server round-trip). LiveView keeps the changes made by JS commands
  across server patches, so a section stays open while the page updates.
  The header button's `aria-expanded` holds the state; the styles follow it
  (`group-aria-expanded:`).
  """
  use Phoenix.Component

  import SubcipherWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string,
    required: true,
    doc: "the header button is `<id>-toggle`, the content `<id>-content`"

  attr :open, :boolean, default: false, doc: "open on first render"
  attr :icon, :string, default: nil, doc: "hero icon before the title"

  attr :class, :any,
    default: "rounded-2xl border border-base-300 bg-base-100",
    doc: "classes of the section (its frame)"

  slot :title, required: true
  slot :hint, doc: "shown next to the title while closed"
  slot :inner_block, required: true

  def accordion(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "min-w-0 transition-colors duration-200 has-[>button:hover]:border-base-content/20",
        @class
      ]}
    >
      <button
        type="button"
        id={"#{@id}-toggle"}
        phx-click={toggle(@id)}
        aria-expanded={to_string(@open)}
        aria-controls={"#{@id}-content"}
        class={[
          "group w-full flex items-center justify-between gap-3 px-4 py-3 text-left text-sm font-semibold",
          "cursor-pointer select-none transition-colors duration-200 hover:bg-base-200/70",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary/50",
          "rounded-[inherit] aria-expanded:rounded-b-none"
        ]}
      >
        <span class="flex items-center gap-2 min-w-0">
          <.icon
            :if={@icon}
            name={@icon}
            class="size-4 shrink-0 text-base-content/60 transition-colors duration-200 group-hover:text-primary"
          />
          <span class="shrink-0">{render_slot(@title)}</span>
          <span
            :if={@hint != []}
            class="max-sm:hidden group-aria-expanded:hidden truncate text-xs font-normal text-base-content/50"
          >
            {render_slot(@hint)}
          </span>
        </span>
        <span class="grid place-items-center size-7 shrink-0 rounded-full text-base-content/60 transition-colors duration-200 group-hover:bg-base-300/70 group-hover:text-base-content">
          <.icon
            name="hero-chevron-down"
            class="size-4 transition-transform duration-200 group-aria-expanded:rotate-180"
          />
        </span>
      </button>
      <div
        id={"#{@id}-content"}
        class={["px-4 pb-4 pt-1 space-y-3", !@open && "hidden"]}
      >
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  defp toggle(id) do
    JS.toggle_attribute({"aria-expanded", "true", "false"})
    |> JS.toggle_class("hidden", to: "##{id}-content")
  end
end
