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

export const AnagramTiles = {
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
