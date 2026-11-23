// Reorders the character tiles of an anagram step. The server renders the
// tiles in the current order; this hook only computes a new order and sends
// it as an "update_step" event, the server re-renders.
//
//   * drag and drop (mouse): drop on the left/right half of a tile to place
//     the dragged tile before/after it;
//   * tap a tile, then another: the first moves to the second's place
//     (works on touch screens, where HTML5 drag and drop doesn't);
//   * ←/→ on a focused tile move it one place (keyboard).
const MARKERS = ["ring-2", "ring-primary", "-translate-y-1", "opacity-40", "border-l-primary!", "border-r-primary!"]

export const AnagramTiles = {
  mounted() {
    this.picked = null

    this.el.addEventListener("dragstart", (e) => {
      const tile = this.tile(e.target)
      if (!tile) return
      this.dragged = tile
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("text/plain", tile.dataset.index)
      requestAnimationFrame(() => tile.classList.add("opacity-40"))
    })

    this.el.addEventListener("dragover", (e) => {
      const tile = this.tile(e.target)
      if (!this.dragged || !tile || tile === this.dragged) return
      e.preventDefault()
      this.clearMarkers()
      tile.classList.add(this.after(e, tile) ? "border-r-primary!" : "border-l-primary!")
    })

    this.el.addEventListener("drop", (e) => {
      const tile = this.tile(e.target)
      if (!this.dragged || !tile || tile === this.dragged) return
      e.preventDefault()
      this.moveTo(this.dragged, tile, this.after(e, tile))
    })

    this.el.addEventListener("dragend", () => {
      this.dragged = null
      this.clearMarkers()
    })

    this.el.addEventListener("click", (e) => {
      const tile = this.tile(e.target)
      if (!tile) return
      if (!this.picked) {
        this.picked = tile.dataset.index
        tile.classList.add("ring-2", "ring-primary", "-translate-y-1")
      } else if (this.picked === tile.dataset.index) {
        this.picked = null
        this.clearMarkers()
      } else {
        const picked = this.byIndex(this.picked)
        this.picked = null
        // Moving right: land after the target, moving left: before it.
        const order = this.order()
        const after = order.indexOf(picked.dataset.index) < order.indexOf(tile.dataset.index)
        this.moveTo(picked, tile, after)
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

  updated() {
    // Keep the keyboard focus on the moved tile after the re-render.
    if (this.focusIndex != null) {
      this.byIndex(this.focusIndex)?.focus()
      this.focusIndex = null
    }
  },

  tile(target) {
    const tile = target.closest?.("[data-index]")
    return tile && this.el.contains(tile) ? tile : null
  },

  byIndex(index) {
    return this.el.querySelector(`[data-index="${index}"]`)
  },

  order() {
    return [...this.el.querySelectorAll("[data-index]")].map((t) => t.dataset.index)
  },

  after(e, tile) {
    const box = tile.getBoundingClientRect()
    return e.clientX > box.left + box.width / 2
  },

  moveTo(moving, target, after) {
    const order = this.order().filter((i) => i !== moving.dataset.index)
    const at = order.indexOf(target.dataset.index) + (after ? 1 : 0)
    order.splice(at, 0, moving.dataset.index)
    this.clearMarkers()
    this.push(order)
  },

  clearMarkers() {
    for (const t of this.el.querySelectorAll("[data-index]")) t.classList.remove(...MARKERS)
  },

  push(order) {
    this.pushEvent("update_step", { step_id: this.el.dataset.stepId, step: { order: order.join(",") } })
  },
}
