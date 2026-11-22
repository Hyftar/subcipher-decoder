// Keyboard shortcuts on the puzzle page (handled by the LiveView):
//   letter / digit      substitute the selected symbol
//   Backspace / Delete  clear it
//   ← / →               previous / next character of the text
//   ↑ / ↓, Tab          previous / next symbol of the symbol key
//   Escape              deselect
// Ignored while typing in a form field.
//
// The element's `data-scroll-to` names the selected glyph (or key row); it is
// scrolled into view when the selection changes, so keyboard navigation
// never leaves the selection off-screen.
const NAV_KEYS = new Set(["ArrowRight", "ArrowLeft", "ArrowDown", "ArrowUp", "Tab", "Escape", "Backspace", "Delete"])

export const CipherKeys = {
  mounted() {
    this.scrolledTo = this.el.dataset.scrollTo
    this.onKeydown = (e) => {
      if (e.ctrlKey || e.metaKey || e.altKey) return
      const t = e.target
      if (t.closest?.("input, textarea, select, [contenteditable]")) return

      const isChar = e.key.length === 1 && e.key !== " "
      if (!isChar && !NAV_KEYS.has(e.key)) return
      if (e.key === "Tab" && this.el.dataset.selected !== "true") return

      e.preventDefault()
      this.pushEvent("key", { key: e.key, shift: e.shiftKey })
    }
    window.addEventListener("keydown", this.onKeydown)
  },

  updated() {
    const target = this.el.dataset.scrollTo
    if (!target || target === this.scrolledTo) {
      this.scrolledTo = target
      return
    }
    this.scrolledTo = target
    document.getElementById(target)?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown)
  },
}
