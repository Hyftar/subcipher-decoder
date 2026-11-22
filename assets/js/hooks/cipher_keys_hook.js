// Keyboard shortcuts on the puzzle page: type a letter to substitute the
// selected symbol, Backspace/Delete to clear it, arrows/Tab to move between
// symbols, Escape to deselect. Ignored while typing in a form field.
const NAV_KEYS = new Set(["ArrowRight", "ArrowLeft", "ArrowDown", "ArrowUp", "Tab", "Escape", "Backspace", "Delete"])

export const CipherKeys = {
  mounted() {
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

  destroyed() {
    window.removeEventListener("keydown", this.onKeydown)
  },
}
