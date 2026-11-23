import { borderSamples, estimateBackground, layout, parseHex, recolor, toHex } from "../symbol_image"

// Draws the encoded output of a pictures algorithm as a single image, from
// the glyph crops of its symbol key (data-spec, JSON):
//   {images: [path], lines: [[token]], background: "auto" | "#rrggbb", align}
// where a token is {t: "glyph", i, x, y, w, h, scale}, {t: "space"},
// {t: "char", c} or {t: "missing", c}.
//
// The glyphs' background colour is estimated from the border of their
// crops; with another background chosen, the crops' background pixels are
// repainted in it. The detected colour is sent as "detected_background".
// The canvas lives in the [data-canvas] child (phx-update="ignore").
const PAD = 2
const images = new Map()

const loadImage = (path) => {
  if (!images.has(path)) {
    images.set(
      path,
      new Promise((resolve, reject) => {
        const img = new Image()
        img.onload = () => resolve(img)
        img.onerror = reject
        img.src = path
      }),
    )
  }
  return images.get(path)
}

export const SymbolImage = {
  mounted() {
    this.canvas = document.createElement("canvas")
    this.canvas.className = "max-w-full h-auto rounded-lg shadow-sm"
    this.el.querySelector("[data-canvas]").appendChild(this.canvas)
    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-download]")) this.download()
    })
    this.render()
  },

  updated() {
    this.render()
  },

  async render() {
    const raw = this.el.dataset.spec
    if (raw === this.rendered) return
    this.rendered = raw
    const spec = JSON.parse(raw)
    const loaded = await Promise.all(spec.images.map(loadImage))
    if (raw !== this.rendered) return // a newer spec is being drawn

    // One crop (with a small margin) per distinct glyph.
    const crops = new Map()
    const tokens = spec.lines.flat()
    for (const t of tokens) {
      if (t.t !== "glyph") continue
      const id = `${t.i}:${t.x}:${t.y}:${t.w}:${t.h}`
      if (crops.has(id)) continue
      const w = t.w + 2 * PAD
      const h = t.h + 2 * PAD
      const canvas = document.createElement("canvas")
      canvas.width = w
      canvas.height = h
      const ctx = canvas.getContext("2d", { willReadFrequently: true })
      ctx.drawImage(loaded[t.i], t.x - PAD, t.y - PAD, w, h, 0, 0, w, h)
      crops.set(id, { canvas, ctx, w, h })
    }

    const samples = [...crops.values()].flatMap((c) =>
      borderSamples(c.ctx.getImageData(0, 0, c.w, c.h).data, c.w, c.h, PAD),
    )
    const detected = estimateBackground(samples)
    if (crops.size > 0 && toHex(detected) !== this.reported) {
      this.reported = toHex(detected)
      this.pushEvent("detected_background", { color: this.reported })
    }

    const background = parseHex(spec.background) || detected
    if (toHex(background) !== toHex(detected)) {
      for (const c of crops.values()) {
        const image = c.ctx.getImageData(0, 0, c.w, c.h)
        recolor(image.data, detected, background)
        c.ctx.putImageData(image, 0, 0)
      }
    }

    const lines = spec.lines.map((line) =>
      line.map((t) => (t.t === "glyph" ? { ...t, w: t.w + 2 * PAD, h: t.h + 2 * PAD } : t)),
    )
    const lay = layout(lines, { align: spec.align, lineHeight: spec.line_height || 56 })

    const ctx = this.canvas.getContext("2d")
    this.canvas.width = lay.width
    this.canvas.height = lay.height
    ctx.fillStyle = toHex(background)
    ctx.fillRect(0, 0, lay.width, lay.height)

    const [r, g, b] = background
    const ink = 0.299 * r + 0.587 * g + 0.114 * b > 140 ? "#1f2937" : "#f3f4f6"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"

    for (const item of lay.items) {
      const t = item.token
      if (t.t === "glyph") {
        const crop = crops.get(`${t.i}:${t.x}:${t.y}:${t.w - 2 * PAD}:${t.h - 2 * PAD}`)
        ctx.drawImage(crop.canvas, item.x, item.y, item.w, item.h)
      } else {
        ctx.font = `${Math.round(item.h * 0.7)}px ui-monospace, monospace`
        ctx.fillStyle = t.t === "missing" ? "#dc2626" : ink
        ctx.fillText(t.c, item.x + item.w / 2, item.y + item.h / 2)
        if (t.t === "missing") {
          ctx.strokeStyle = "#dc2626"
          ctx.setLineDash([4, 3])
          ctx.strokeRect(item.x + 1, item.y + 1, item.w - 2, item.h - 2)
          ctx.setLineDash([])
        }
      }
    }
  },

  download() {
    this.canvas.toBlob((blob) => {
      const link = document.createElement("a")
      link.href = URL.createObjectURL(blob)
      link.download = (this.el.dataset.filename || "cipher") + ".png"
      link.click()
      setTimeout(() => URL.revokeObjectURL(link.href), 1000)
    }, "image/png")
  },
}
