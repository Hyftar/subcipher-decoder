// Composes an image of symbol cipher text from glyph crops (the encoded
// output of a pictures algorithm). Pure functions, unit tested with Node
// (assets/test/symbol_image.test.mjs); the SymbolImage hook draws with them.

export function parseHex(hex) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || "")
  return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : null
}

export function toHex(rgb) {
  return "#" + rgb.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("")
}

// Pixels of the `ring`-wide border of an RGBA image: around a glyph crop,
// mostly the background it was written on.
export function borderSamples(data, width, height, ring = 2) {
  const samples = []
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (x >= ring && x < width - ring && y >= ring && y < height - ring) continue
      const i = (y * width + x) * 4
      if (data[i + 3] > 0) samples.push([data[i], data[i + 1], data[i + 2]])
    }
  }
  return samples
}

// The background colour: the per-channel median of the samples (robust to
// the bits of ink touching a crop's border).
export function estimateBackground(samples) {
  if (samples.length === 0) return [255, 255, 255]
  return [0, 1, 2].map((c) => {
    const values = samples.map((s) => s[c]).sort((a, b) => a - b)
    return values[Math.floor(values.length / 2)]
  })
}

const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2])

// Repaints, in place, the pixels close to `from` (the glyphs' background)
// in `to`: fully under `tolerance`, blended up to twice that, so the edges
// of the ink stay smooth.
export function recolor(data, from, to, tolerance = 60) {
  for (let i = 0; i < data.length; i += 4) {
    const pixel = [data[i], data[i + 1], data[i + 2]]
    const d = distance(pixel, from)
    if (d >= 2 * tolerance) continue
    const t = d <= tolerance ? 1 : (2 * tolerance - d) / tolerance
    for (let c = 0; c < 3; c++) data[i + c] = Math.round(pixel[c] * (1 - t) + to[c] * t)
  }
  return data
}

// Lays out lines of tokens:
//   {t: "glyph", w, h, scale}  a glyph crop, drawn at w*scale × h*scale
//   {t: "space"}               a word break
//   {t: "char", c} / {t: "missing", c}  a character drawn as text
// Lines wrap at spaces beyond `maxWidth`. Each line is aligned left,
// center or right; glyphs are centred vertically in their line.
// Returns {width, height, items: [{token, x, y, w, h}]}.
export function layout(lines, opts = {}) {
  const {
    lineHeight = 48,
    gap = 4,
    space = 20,
    margin = 24,
    lineGap = 12,
    maxWidth = 1200,
    align = "center",
  } = opts

  const size = (token) => {
    if (token.t === "glyph") return [token.w * token.scale, token.h * token.scale]
    if (token.t === "space") return [space, 0]
    return [lineHeight * 0.6, lineHeight * 0.8]
  }

  // Wrap: split lines into words, then fill rows up to maxWidth.
  const rows = []
  for (const line of lines) {
    const words = []
    let word = []
    for (const token of line) {
      if (token.t === "space") {
        if (word.length) words.push(word)
        word = []
      } else word.push(token)
    }
    if (word.length) words.push(word)

    const wordWidth = (w) => w.reduce((sum, t) => sum + size(t)[0], 0) + gap * (w.length - 1)
    let row = []
    let rowWidth = 0
    for (const w of words) {
      const width = wordWidth(w)
      const added = row.length ? space + width : width
      if (row.length && rowWidth + added > maxWidth) {
        rows.push(row)
        row = []
        rowWidth = 0
      }
      if (row.length) row.push({ t: "space" })
      row.push(...w)
      rowWidth += row.length > w.length ? space + width : width
    }
    rows.push(row)
  }

  const rowWidth = (row) =>
    row.reduce((sum, t, i) => sum + size(t)[0] + (i > 0 && t.t !== "space" && row[i - 1].t !== "space" ? gap : 0), 0)

  const contentWidth = Math.max(0, ...rows.map(rowWidth))
  const width = Math.ceil(contentWidth + 2 * margin)
  const height = Math.ceil(2 * margin + rows.length * lineHeight + Math.max(0, rows.length - 1) * lineGap)

  const items = []
  rows.forEach((row, r) => {
    const free = contentWidth - rowWidth(row)
    let x = margin + (align === "right" ? free : align === "center" ? free / 2 : 0)
    const top = margin + r * (lineHeight + lineGap)
    row.forEach((token, i) => {
      if (i > 0 && token.t !== "space" && row[i - 1].t !== "space") x += gap
      const [w, h] = size(token)
      if (token.t !== "space") items.push({ token, x, y: top + (lineHeight - h) / 2, w, h })
      x += w
    })
  })

  return { width, height, items }
}
