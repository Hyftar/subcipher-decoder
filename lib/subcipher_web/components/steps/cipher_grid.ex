defmodule SubcipherWeb.Components.CipherGrid do
  @moduledoc "Every cipher type as a card to choose from."
  use SubcipherWeb, :html

  alias Subcipher.Steps

  import SubcipherWeb.Components.OsrsUsage

  attr :id_prefix, :string, required: true, doc: "card ids: id_prefix <> cipher type"
  attr :event, :string, required: true, doc: "clicked with phx-value-type"
  attr :icon, :string, default: "hero-arrow-right-circle"
  attr :class, :string, default: "sm:grid-cols-2"
  attr :ciphers, :list, default: nil, doc: "the ciphers offered (default: all)"

  attr :locked, :list,
    default: [],
    doc: "types of the ciphers that need an account: shown with a lock"

  @doc "Every cipher type as a card; clicking one sends `event` with its type."
  def cipher_grid(assigns) do
    ~H"""
    <div class={["grid gap-3", @class]}>
      <button
        :for={cipher <- @ciphers || Steps.ciphers()}
        type="button"
        id={@id_prefix <> cipher.type()}
        phx-click={@event}
        phx-value-type={cipher.type()}
        class="group flex flex-col justify-start text-left rounded-xl border border-base-300 bg-base-100 p-4 transition hover:border-primary hover:bg-primary/5 hover:-translate-y-0.5 hover:shadow-sm cursor-pointer"
      >
        <span class="flex items-center justify-between gap-2 font-semibold">
          <span class="flex items-center gap-2">
            {cipher.name()}
            <.icon
              :if={:pictures in cipher.input_kinds()}
              name="hero-photo"
              class="size-6 text-base-content/40"
            />
          </span>
          <.icon
            name={if cipher.type() in @locked, do: "hero-lock-closed", else: @icon}
            class="size-6 shrink-0 text-base-content/30 group-hover:text-primary transition-colors"
          />
        </span>
        <span class="block mt-1 text-sm text-base-content/60">{cipher.description()}</span>
        <.osrs_usage cipher={cipher} class="mt-2" />
        <span
          :if={cipher.type() in @locked}
          id={@id_prefix <> cipher.type() <> "-locked"}
          class="mt-2 inline-flex items-center gap-1.5 self-start rounded-full bg-base-200 px-2 py-0.5 text-xs text-base-content/60"
        >
          <.icon name="hero-user-circle" class="size-3.5" /> Log in to upload pictures
        </span>
      </button>
    </div>
    """
  end
end
