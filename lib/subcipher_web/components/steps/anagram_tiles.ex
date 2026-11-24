defmodule SubcipherWeb.Components.AnagramTiles do
  @moduledoc """
  The characters of an anagram step as tiles, in the current order.
  Reordered by drag and drop, by tapping two tiles, or with ←/→ on a focused
  tile; the `.AnagramTiles` hook sends the new order as "update_step".
  """
  use SubcipherWeb, :html

  alias Subcipher.Steps.Ciphers.Anagram

  import SubcipherWeb.Components.FieldErrors

  attr :field, :map, required: true, doc: "a cipher field spec"
  attr :form_field, Phoenix.HTML.FormField, required: true
  attr :step_id, :integer, required: true
  attr :input, :string, required: true, doc: "the step's input text"
  attr :params, :map, default: %{}, doc: "the step's current (valid) parameters"

  def anagram_tiles(assigns) do
    tiles = Anagram.tiles(assigns.input, assigns.params[:spaces])
    order = Anagram.resolve_order(assigns.form_field.value, length(tiles))
    tiles = List.to_tuple(tiles)
    assigns = assign(assigns, tiles: Enum.map(order, &{&1, elem(tiles, &1)}))

    ~H"""
    <fieldset class="space-y-2">
      <legend class="text-sm font-medium">{@field.label}</legend>
      <input type="hidden" name={@form_field.name} value={@form_field.value} />
      <p :if={@tiles == []} class="text-sm text-base-content/60">Nothing to rearrange yet.</p>
      <ol
        :if={@tiles != []}
        id={"anagram-#{@step_id}"}
        phx-hook=".AnagramTiles"
        data-step-id={@step_id}
        aria-label="Characters, in reading order"
        class="relative flex flex-wrap gap-1.5 select-none"
      >
        <li
          :for={{index, char} <- @tiles}
          id={"tile-#{@step_id}-#{index}"}
          data-index={index}
          draggable="true"
          tabindex="0"
          role="button"
          aria-label={if char =~ ~r/^\s$/u, do: "space", else: char}
          class={[
            "grid place-items-center min-w-10 h-11 px-2 rounded-lg border-2 border-b-4 font-mono text-xl uppercase",
            "cursor-grab active:cursor-grabbing transition-all duration-150",
            "focus:outline-none focus-visible:ring-2 focus-visible:ring-primary",
            if(char =~ ~r/^\s$/u,
              do: "border-dashed border-base-300 text-base-content/30",
              else: "border-base-300 bg-base-100 hover:border-primary/60 hover:-translate-y-0.5"
            )
          ]}
        >
          {if char =~ ~r/^\s$/u, do: "␣", else: char}
        </li>
      </ol>
      <div class="flex flex-wrap items-center gap-3 text-xs text-base-content/60">
        <span>Drag a tile, or tap two tiles; ← / → move a focused tile.</span>
        <button
          type="button"
          id={"anagram-reset-#{@step_id}"}
          class="btn btn-ghost btn-sm"
          phx-click={JS.push("update_step", value: %{step_id: @step_id, step: %{order: ""}})}
        >
          <.icon name="hero-arrow-uturn-left" class="size-4" /> Reset
        </button>
      </div>
      <.field_errors form_field={@form_field} />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AnagramTiles">
        // Reorders the character tiles of an anagram step. The server renders the
        // tiles in the current order; this hook computes a new order and sends it as
        // an "update_step" event.
        //
        //   * drag and drop (mouse): while dragging, the dragged tile becomes a gap
        //     that moves through the row, the other tiles sliding aside to make
        //     room; dropping sends the order, cancelling restores it;
        //   * tap a tile, then another: the first moves to the second's place
        //     (works on touch screens, where HTML5 drag and drop doesn't);
        //   * ←/→ on a focused tile move it one place (keyboard).
        //
        // Every change of position is animated with a bouncy FLIP: tiles are moved
        // in the DOM, then animated from where they were to where they are now.

        const BOUNCE = { duration: 420, easing: "cubic-bezier(0.34, 1.56, 0.64, 1)" }
        const PICKED = ["ring-2", "ring-primary", "-translate-y-1"]
        // The dragged tile, while dragging: an empty slot showing where it will land.
        const GAP = ["opacity-30", "border-dashed", "scale-90"]

        const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

        export default {
          mounted() {
            this.picked = null

            this.el.addEventListener("dragstart", (e) => {
              const tile = this.tile(e.target)
              if (!tile) return
              this.dragged = tile
              this.dropped = false
              this.startOrder = this.order()
              this.clearPicked()
              e.dataTransfer.effectAllowed = "move"
              e.dataTransfer.setData("text/plain", tile.dataset.index)
              // After the browser took its snapshot of the tile for the drag image.
              requestAnimationFrame(() => tile.classList.add(...GAP))
            })

            // Over the whole row (gaps between tiles included): move the gap where
            // the tile would land.
            this.el.addEventListener("dragover", (e) => {
              if (!this.dragged) return
              e.preventDefault()
              e.dataTransfer.dropEffect = "move"
              const before = this.insertionPoint(e)
              const current = this.dragged.nextElementSibling
              if (before === current || before === this.dragged) return
              this.animateReorder(() => this.el.insertBefore(this.dragged, before))
            })

            this.el.addEventListener("drop", (e) => {
              if (!this.dragged) return
              e.preventDefault()
              this.dropped = true
              const order = this.order()
              this.endDrag()
              if (order.join() !== this.startOrder.join()) this.push(order)
            })

            // Dropped outside or cancelled (Escape): back to the original order.
            this.el.addEventListener("dragend", () => {
              if (!this.dragged) return
              if (!this.dropped) this.animateReorder(() => this.applyOrder(this.startOrder))
              this.endDrag()
            })

            this.el.addEventListener("click", (e) => {
              const tile = this.tile(e.target)
              if (!tile) return
              if (!this.picked) {
                this.picked = tile.dataset.index
                tile.classList.add(...PICKED)
              } else if (this.picked === tile.dataset.index) {
                this.clearPicked()
              } else {
                const order = this.order()
                const from = order.indexOf(this.picked)
                const to = order.indexOf(tile.dataset.index)
                order.splice(from, 1)
                order.splice(to, 0, this.picked)
                this.clearPicked()
                this.push(order)
              }
            })

            this.el.addEventListener("keydown", (e) => {
              const tile = this.tile(e.target)
              if (!tile || !["ArrowLeft", "ArrowRight"].includes(e.key)) return
              e.preventDefault()
              const order = this.order()
              const from = order.indexOf(tile.dataset.index)
              const to = from + (e.key === "ArrowLeft" ? -1 : 1)
              if (to < 0 || to >= order.length) return
              order.splice(from, 1)
              order.splice(to, 0, tile.dataset.index)
              this.focusIndex = tile.dataset.index
              this.push(order)
            })
          },

          // The server re-renders tiles in their new order (tap, keyboard, reset…):
          // remember where they were to animate them from there.
          beforeUpdate() {
            this.firstRects = this.rects()
          },

          updated() {
            if (this.firstRects) this.play(this.firstRects)
            this.firstRects = null
            if (this.focusIndex != null) {
              this.byIndex(this.focusIndex)?.focus()
              this.focusIndex = null
            }
          },

          // The tile the dragged one should be inserted before (null: at the end),
          // from the tiles' layout positions (offsetLeft/Top ignore the transforms
          // of running animations, so the gap doesn't flicker back and forth).
          insertionPoint(e) {
            const box = this.el.getBoundingClientRect()
            const x = e.clientX - box.left + this.el.scrollLeft
            const y = e.clientY - box.top + this.el.scrollTop

            for (const t of this.tiles()) {
              if (t === this.dragged) continue
              const top = t.offsetTop
              const bottom = top + t.offsetHeight
              // A row above the pointer's, or the same row and right of it.
              if (y < top || (y <= bottom && x < t.offsetLeft + t.offsetWidth / 2)) return t
            }
            return null
          },

          // FLIP: measure, change the DOM, then animate each tile from its old
          // position to its new one.
          animateReorder(change) {
            const first = this.rects()
            change()
            this.play(first)
          },

          rects() {
            const rects = new Map()
            for (const t of this.tiles()) rects.set(t.dataset.index, t.getBoundingClientRect())
            return rects
          },

          play(first) {
            if (reducedMotion()) return
            for (const t of this.tiles()) {
              const before = first.get(t.dataset.index)
              if (!before) continue
              // Measured where it is now, without the animation in progress.
              for (const a of t.getAnimations()) a.cancel()
              const after = t.getBoundingClientRect()
              const dx = before.left - after.left
              const dy = before.top - after.top
              if (Math.abs(dx) < 1 && Math.abs(dy) < 1) continue
              t.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "translate(0, 0)" }], BOUNCE)
            }
          },

          endDrag() {
            this.dragged?.classList.remove(...GAP)
            this.dragged = null
          },

          clearPicked() {
            if (this.picked) this.byIndex(this.picked)?.classList.remove(...PICKED)
            this.picked = null
          },

          tile(target) {
            const tile = target.closest?.("[data-index]")
            return tile && this.el.contains(tile) ? tile : null
          },

          tiles() {
            return [...this.el.querySelectorAll("[data-index]")]
          },

          byIndex(index) {
            return this.el.querySelector(`[data-index="${index}"]`)
          },

          order() {
            return this.tiles().map((t) => t.dataset.index)
          },

          applyOrder(order) {
            for (const index of order) this.el.appendChild(this.byIndex(index))
          },

          push(order) {
            this.pushEvent("update_step", { step_id: this.el.dataset.stepId, step: { order: order.join(",") } })
          },
        }
      </script>
    </fieldset>
    """
  end
end
