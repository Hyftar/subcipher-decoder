import {
  borderSamples,
  cropMask,
  estimateBackground,
  inkSamples,
  layout,
  paintMask,
  parseHex,
  recolor,
  toHex,
} from "../symbol_image"
import { loadImage, loadMask } from "./image_cache"

// Draws the encoded output of a pictures algorithm as a single image, from
// the glyph crops of its symbol key (data-spec, JSON):
//   {images: [path], lines: [[token]], style: "original" | "mask",
//    background: "auto" | "#rrggbb", ink: "auto" | "#rrggbb",
//    transparent: boolean, align, line_height}
// where a token is {t: "glyph", i, x, y, w, h, scale}, {t: "space"},
// {t: "char", c} or {t: "missing", c}.
//
// "original" draws the crops as they are; with another background chosen,
// their background pixels are repainted in it. "mask" draws the black and
// white pass of the pictures (their ink mask) as a font: the ink in one
// colour on a plain (or transparent) background.
//
// The colours detected in the crops (background: median of their border;
// ink: median of the inked pixels) are sent as "detected_colours".
// The canvas lives in the [data-canvas] child (phx-update="ignore").
const PAD = 2
const FALLBACK_INK = [31, 41, 55]

const cropId = (t) => `${t.i}:${t.x}:${t.y}:${t.w}:${t.h}`

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
    const mask = spec.style === "mask"
    const [loaded, masks] = await Promise.all([
      Promise.all(spec.images.map(loadImage)),
      mask ? Promise.all(spec.images.map(loadMask)) : null,
    ])
    if (raw !== this.rendered) return // a newer spec is being drawn

    // One crop (with a small margin) per distinct glyph.
    const crops = new Map()
    for (const t of spec.lines.flat()) {
      if (t.t !== "glyph" || crops.has(cropId(t))) continue
      const w = t.w + 2 * PAD
      const h = t.h + 2 * PAD
      const canvas = document.createElement("canvas")
      canvas.width = w
      canvas.height = h
      const ctx = canvas.getContext("2d", { willReadFrequently: true })
      ctx.drawImage(loaded[t.i], t.x - PAD, t.y - PAD, w, h, 0, 0, w, h)
      const pixels = ctx.getImageData(0, 0, w, h)
      const inked = masks && cropMask(masks[t.i].mask, masks[t.i].width, t, PAD)
      crops.set(cropId(t), { canvas, ctx, w, h, pixels, inked })
    }

    const detected = estimateBackground(
      [...crops.values()].flatMap((c) => borderSamples(c.pixels.data, c.w, c.h, PAD)),
    )
    const inkPixels = mask ? [...crops.values()].flatMap((c) => inkSamples(c.pixels.data, c.inked)) : []
    const detectedInk = inkPixels.length ? estimateBackground(inkPixels) : null
    this.report(crops.size > 0 && detected, detectedInk)

    const background = parseHex(spec.background) || detected
    const ink = parseHex(spec.ink) || detectedInk || FALLBACK_INK
    const transparent = mask && spec.transparent

    for (const c of crops.values()) {
      if (mask) {
        c.ctx.putImageData(new ImageData(paintMask(c.inked, ink), c.w, c.h), 0, 0)
      } else if (toHex(background) !== toHex(detected)) {
        recolor(c.pixels.data, detected, background)
        c.ctx.putImageData(c.pixels, 0, 0)
      }
    }

    const lines = spec.lines.map((line) =>
      line.map((t) => (t.t === "glyph" ? { ...t, w: t.w + 2 * PAD, h: t.h + 2 * PAD } : t)),
    )
    const lay = layout(lines, { align: spec.align, lineHeight: spec.line_height || 56 })

    const ctx = this.canvas.getContext("2d")
    this.canvas.width = lay.width
    this.canvas.height = lay.height
    ctx.clearRect(0, 0, lay.width, lay.height)
    if (!transparent) {
      ctx.fillStyle = toHex(background)
      ctx.fillRect(0, 0, lay.width, lay.height)
    }
    this.canvas.classList.toggle("checkerboard", !!transparent)
    ctx.imageSmoothingEnabled = true
    ctx.imageSmoothingQuality = "high"

    const [r, g, b] = background
    const textInk = mask ? toHex(ink) : 0.299 * r + 0.587 * g + 0.114 * b > 140 ? "#1f2937" : "#f3f4f6"
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"

    for (const item of lay.items) {
      const t = item.token
      if (t.t === "glyph") {
        const crop = crops.get(cropId({ ...t, w: t.w - 2 * PAD, h: t.h - 2 * PAD }))
        ctx.drawImage(crop.canvas, item.x, item.y, item.w, item.h)
      } else {
        ctx.font = `${Math.round(item.h * 0.7)}px ui-monospace, monospace`
        ctx.fillStyle = t.t === "missing" ? "#dc2626" : textInk
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

  // Sends the detected colours when they change (the ink only in mask
  // style, where it is measured; the last one is kept otherwise).
  report(background, ink) {
    const colours = {
      background: background ? toHex(background) : this.reported?.background || null,
      ink: ink ? toHex(ink) : this.reported?.ink || null,
    }
    if (colours.background === this.reported?.background && colours.ink === this.reported?.ink) return
    this.reported = colours
    this.pushEvent("detected_colours", colours)
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
