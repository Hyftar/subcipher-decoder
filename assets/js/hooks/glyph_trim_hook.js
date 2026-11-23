import { contextRegion, keyMove, moveEdge } from "../glyph_trim"
import { loadImage, loadMask } from "./image_cache"

// The crop editor of the puzzle page's glyphs panel: the picture around a
// glyph, zoomed, with its box. Each edge of the box can be dragged, or
// focused and moved with the arrow keys; the new box is pushed as
// "trim_glyph" {id, x, y, w, h}.
//
// data-glyph-id, data-image (path), data-box and data-detected (JSON boxes,
// the latter the one detection found when the glyph was trimmed) and
// data-view ("original" or "mask": the black and white pass) come from the
// server; the element is phx-update="ignore", so its attributes are watched.
const EDGES = ["left", "right", "top", "bottom"]

export const GlyphTrim = {
  mounted() {
    this.el.innerHTML = ""
    this.canvas = document.createElement("canvas")
    this.canvas.className = "absolute inset-0 m-auto [image-rendering:pixelated]"
    this.frame = document.createElement("div")
    this.frame.className =
      "absolute ring-2 ring-primary shadow-[0_0_0_9999px_rgb(0_0_0/0.45)] transition-[left,top,width,height] duration-75"
    this.dims = document.createElement("span")
    this.dims.className =
      "absolute bottom-1.5 right-1.5 rounded bg-base-100/90 px-1.5 py-0.5 font-mono text-[11px] text-base-content/80 shadow"
    this.el.append(this.canvas, this.frame, this.dims)

    this.handles = Object.fromEntries(EDGES.map((edge) => [edge, this.handle(edge)]))
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.el, { attributes: true, attributeFilter: ["data-glyph-id", "data-box", "data-detected", "data-view"] })
    this.resize = new ResizeObserver(() => this.draw())
    this.resize.observe(this.el)
    this.sync()
  },

  destroyed() {
    this.observer?.disconnect()
    this.resize?.disconnect()
    clearTimeout(this.timer)
  },

  // A draggable, focusable edge of the box.
  handle(edge) {
    const vertical = edge === "left" || edge === "right"
    const el = document.createElement("button")
    el.type = "button"
    el.setAttribute("aria-label", `${edge} edge`)
    el.className = [
      "group absolute z-10 grid place-items-center focus:outline-none",
      vertical ? "w-4 -ml-2 cursor-ew-resize" : "h-4 -mt-2 cursor-ns-resize",
    ].join(" ")
    const grip = document.createElement("span")
    grip.className = [
      "rounded-full bg-primary shadow ring-2 ring-base-100 transition-transform",
      "group-hover:scale-125 group-focus-visible:scale-125 group-focus-visible:ring-primary/40",
      vertical ? "h-6 w-1.5" : "w-6 h-1.5",
    ].join(" ")
    el.appendChild(grip)

    el.addEventListener("pointerdown", (e) => {
      e.preventDefault()
      el.focus()
      el.setPointerCapture(e.pointerId)
      this.dragging = edge
    })
    el.addEventListener("pointermove", (e) => {
      if (this.dragging !== edge) return
      const rect = this.canvas.getBoundingClientRect()
      const to = vertical
        ? this.region.x + (e.clientX - rect.left) / this.scale
        : this.region.y + (e.clientY - rect.top) / this.scale
      this.setBox(moveEdge(this.box, edge, to, this.bounds()))
    })
    const release = () => {
      if (this.dragging !== edge) return
      this.dragging = null
      this.commit()
    }
    el.addEventListener("pointerup", release)
    el.addEventListener("pointercancel", release)
    el.addEventListener("keydown", (e) => {
      const delta = keyMove(edge, e.key, e.shiftKey)
      if (delta === null) return
      e.preventDefault()
      e.stopPropagation()
      const current = { left: this.box.x, right: this.box.x + this.box.w, top: this.box.y, bottom: this.box.y + this.box.h }
      this.setBox(moveEdge(this.box, edge, current[edge] + delta, this.bounds()))
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.commit(), 400)
    })
    this.el.appendChild(el)
    return el
  },

  bounds() {
    return { x: 0, y: 0, w: this.picture.width, h: this.picture.height }
  },

  // Reads the server's attributes; the region shown only changes with the
  // glyph (so it doesn't jump while trimming) or when the box leaves it.
  async sync() {
    const id = this.el.dataset.glyphId
    const box = JSON.parse(this.el.dataset.box)
    const detected = this.el.dataset.detected ? JSON.parse(this.el.dataset.detected) : null
    const path = this.el.dataset.image
    const view = this.el.dataset.view
    const token = (this.token = {})

    const img = await loadImage(path)
    const mask = view === "mask" ? (await loadMask(path)).mask : null
    if (token !== this.token) return // a newer sync is running

    this.picture = { img, mask, width: img.naturalWidth, height: img.naturalHeight }
    const inside = (r, b) => r && b.x >= r.x && b.y >= r.y && b.x + b.w <= r.x + r.w && b.y + b.h <= r.y + r.h
    if (id !== this.glyphId || !inside(this.region, box)) {
      this.region = contextRegion(box, detected, this.picture.width, this.picture.height)
    }
    this.glyphId = id
    this.box = box
    this.view = view
    this.draw()
  },

  draw() {
    if (!this.region || !this.picture) return
    const { region, picture } = this
    const scale = Math.min(this.el.clientWidth / region.w, this.el.clientHeight / region.h)
    this.scale = scale
    this.canvas.width = region.w
    this.canvas.height = region.h
    this.canvas.style.width = `${region.w * scale}px`
    this.canvas.style.height = `${region.h * scale}px`

    const ctx = this.canvas.getContext("2d")
    if (this.view === "mask" && picture.mask) {
      const pixels = ctx.createImageData(region.w, region.h)
      for (let y = 0; y < region.h; y++) {
        for (let x = 0; x < region.w; x++) {
          const ink = picture.mask[(region.y + y) * picture.width + region.x + x]
          const v = ink ? 17 : 255
          pixels.data.set([v, v, v, 255], (y * region.w + x) * 4)
        }
      }
      ctx.putImageData(pixels, 0, 0)
    } else {
      ctx.clearRect(0, 0, region.w, region.h)
      ctx.drawImage(picture.img, region.x, region.y, region.w, region.h, 0, 0, region.w, region.h)
    }
    this.place()
  },

  // Positions the frame, the handles and the size label on the box.
  place() {
    const { box, region, scale } = this
    const offsetX = (this.el.clientWidth - region.w * scale) / 2
    const offsetY = (this.el.clientHeight - region.h * scale) / 2
    const left = offsetX + (box.x - region.x) * scale
    const top = offsetY + (box.y - region.y) * scale
    const width = box.w * scale
    const height = box.h * scale
    Object.assign(this.frame.style, { left: `${left}px`, top: `${top}px`, width: `${width}px`, height: `${height}px` })

    const h = this.handles
    Object.assign(h.left.style, { left: `${left}px`, top: `${top}px`, height: `${height}px` })
    Object.assign(h.right.style, { left: `${left + width}px`, top: `${top}px`, height: `${height}px` })
    Object.assign(h.top.style, { left: `${left}px`, top: `${top}px`, width: `${width}px` })
    Object.assign(h.bottom.style, { left: `${left}px`, top: `${top + height}px`, width: `${width}px` })
    this.dims.textContent = `${box.w} × ${box.h} px`
  },

  setBox(box) {
    this.box = box
    this.place()
  },

  commit() {
    clearTimeout(this.timer)
    const { x, y, w, h } = this.box
    const server = JSON.parse(this.el.dataset.box)
    if (server.x === x && server.y === y && server.w === w && server.h === h) return
    this.pushEvent("trim_glyph", { id: this.el.dataset.glyphId, x, y, w, h })
  },
}
