// Detects individual symbols ("glyphs") in a picture of cipher text.
//
// Pure functions working on a grayscale buffer so they can be unit tested
// with Node (see assets/test/glyph_detector.test.mjs). The LiveView hook in
// hooks/glyph_detector_hook.js feeds it pixels from a <canvas>.
//
// Pipeline:
//   1. adaptive (Bradley) thresholding -> ink mask
//   2. 8-connected component labelling (union-find)
//   3. merge components that make up a single symbol (dots, accents, "=",
//      circled symbols, ...)
//   4. drop specks and frames
//   5. describe each glyph with a scale-invariant 16x16 ink-coverage grid,
//      which the server uses to cluster identical symbols.

export const GRID = 16

export function toGrayscale(rgba, width, height) {
  const gray = new Uint8Array(width * height)
  for (let i = 0, p = 0; i < gray.length; i++, p += 4) {
    const a = rgba[p + 3] / 255
    // Transparent pixels are treated as white paper.
    const lum = 0.299 * rgba[p] + 0.587 * rgba[p + 1] + 0.114 * rgba[p + 2]
    gray[i] = Math.round(lum * a + 255 * (1 - a))
  }
  return gray
}

function median(values) {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
}

// Bradley-Roth adaptive threshold. A pixel is ink when it is `t` percent
// darker than the mean of its neighbourhood. Handles uneven lighting in
// photos much better than a single global threshold.
export function binarize(rawGray, width, height, { t = 0.15, minContrast = 16 } = {}) {
  // A light blur removes sensor noise that would otherwise become specks.
  const blurred = boxBlur3(rawGray, width, height)
  // Light ink on a dark background? Work on the inverted image.
  const gray = inkIsLight(blurred, width, height) ? blurred.map((v) => 255 - v) : blurred

  const half = Math.max(7, Math.round(Math.max(width, height) / 32))
  const mean = localMean(gray, width, height, half)
  const ink = new Uint8Array(width * height)
  for (let i = 0; i < ink.length; i++) {
    if (gray[i] < mean[i] * (1 - t) && mean[i] - gray[i] > minContrast) ink[i] = 1
  }
  return ink
}

// Mean of the (2 * half + 1)² neighbourhood of every pixel (integral image).
export function localMean(gray, width, height, half) {
  const stride = width + 1
  const integral = new Float64Array(stride * (height + 1))
  for (let y = 0; y < height; y++) {
    let rowSum = 0
    for (let x = 0; x < width; x++) {
      rowSum += gray[y * width + x]
      integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum
    }
  }

  const mean = new Float32Array(width * height)
  for (let y = 0; y < height; y++) {
    const y0 = Math.max(0, y - half)
    const y1 = Math.min(height, y + half + 1)
    for (let x = 0; x < width; x++) {
      const x0 = Math.max(0, x - half)
      const x1 = Math.min(width, x + half + 1)
      const sum =
        integral[y1 * stride + x1] - integral[y0 * stride + x1] - integral[y1 * stride + x0] + integral[y0 * stride + x0]
      mean[y * width + x] = sum / ((x1 - x0) * (y1 - y0))
    }
  }
  return mean
}

// Decides the ink polarity. Lighting is first flattened (each pixel minus a
// wide local average) so gradients and shadows don't matter. The background
// is then the most common value, and the ink is whichever side of it
// (darker or lighter) holds more strongly contrasting pixels. Handles dark
// text on paper as well as light symbols with dark outlines/shadows on a
// darker background, where the thin outlines must not be taken for ink.
export function inkIsLight(gray, width, height, { margin = 40 } = {}) {
  const half = Math.max(15, Math.round(Math.max(width, height) / 8))
  const mean = localMean(gray, width, height, half)
  const flat = new Int16Array(gray.length)
  const hist = new Uint32Array(64) // buckets of 8 over [-256, 256)
  for (let i = 0; i < gray.length; i++) {
    flat[i] = Math.round(gray[i] - mean[i])
    hist[Math.min(63, Math.max(0, (flat[i] + 256) >> 3))]++
  }
  let peak = 0
  for (let b = 1; b < hist.length; b++) if (hist[b] > hist[peak]) peak = b
  const background = peak * 8 - 256 + 4

  let darker = 0
  let lighter = 0
  for (let i = 0; i < flat.length; i++) {
    if (flat[i] < background - margin) darker++
    else if (flat[i] > background + margin) lighter++
  }
  return lighter > darker
}

export function boxBlur3(gray, width, height) {
  const out = new Uint8Array(width * height)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0
      let n = 0
      for (let dy = -1; dy <= 1; dy++) {
        const yy = y + dy
        if (yy < 0 || yy >= height) continue
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx
          if (xx < 0 || xx >= width) continue
          sum += gray[yy * width + xx]
          n++
        }
      }
      out[y * width + x] = Math.round(sum / n)
    }
  }
  return out
}


// 8-connected component labelling. Returns per-pixel labels (0 = background)
// and a list of components with bounding boxes.
export function connectedComponents(ink, width, height) {
  const labels = new Int32Array(width * height)
  const parent = [0]
  const find = (a) => {
    while (parent[a] !== a) {
      parent[a] = parent[parent[a]]
      a = parent[a]
    }
    return a
  }
  const union = (a, b) => {
    a = find(a)
    b = find(b)
    if (a !== b) parent[Math.max(a, b)] = Math.min(a, b)
  }

  let next = 1
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x
      if (!ink[i]) continue
      const neighbours = []
      if (x > 0 && labels[i - 1]) neighbours.push(labels[i - 1])
      if (y > 0) {
        const up = i - width
        if (labels[up]) neighbours.push(labels[up])
        if (x > 0 && labels[up - 1]) neighbours.push(labels[up - 1])
        if (x < width - 1 && labels[up + 1]) neighbours.push(labels[up + 1])
      }
      if (neighbours.length === 0) {
        parent.push(next)
        labels[i] = next++
      } else {
        const m = Math.min(...neighbours)
        labels[i] = m
        for (const n of neighbours) union(m, n)
      }
    }
  }

  const compIndex = new Map()
  const components = []
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const i = y * width + x
      if (!labels[i]) continue
      const root = find(labels[i])
      let idx = compIndex.get(root)
      if (idx === undefined) {
        idx = components.length
        compIndex.set(root, idx)
        components.push({ x0: x, y0: y, x1: x, y1: y, area: 0 })
      }
      labels[i] = idx + 1
      const c = components[idx]
      c.area++
      if (x < c.x0) c.x0 = x
      if (x > c.x1) c.x1 = x
      if (y < c.y0) c.y0 = y
      if (y > c.y1) c.y1 = y
    }
  }
  return { labels, components }
}

const w = (b) => b.x1 - b.x0 + 1
const h = (b) => b.y1 - b.y0 + 1

function overlap(a0, a1, b0, b1) {
  return Math.max(0, Math.min(a1, b1) - Math.max(a0, b0) + 1)
}

const mergedBox = (a, b) => ({
  w: Math.max(a.x1, b.x1) - Math.min(a.x0, b.x0) + 1,
  h: Math.max(a.y1, b.y1) - Math.min(a.y0, b.y0) + 1,
})

// One box contains (most of) the other: circled symbols, enclosed marks,
// bits of a symbol cut off by its own inner lines.
function contains(a, b) {
  const ix = overlap(a.x0, a.x1, b.x0, b.x1)
  const iy = overlap(a.y0, a.y1, b.y0, b.y1)
  return ix * iy >= 0.6 * Math.min(w(a) * h(a), w(b) * h(b))
}

// Decide whether two boxes belong to the same symbol.
function shouldMerge(a, b, refH) {
  if (contains(a, b)) return true

  const gapX = Math.max(a.x0, b.x0) - Math.min(a.x1, b.x1) - 1
  const gapY = Math.max(a.y0, b.y0) - Math.min(a.y1, b.y1) - 1
  const merged = mergedBox(a, b)
  if (Math.max(gapX, gapY) <= 0.08 * refH) {
    // A small fragment practically touching a symbol (detached rays,
    // serifs broken by a bad scan...).
    const small = (c) => Math.max(w(c), h(c)) < 0.35 * refH
    if ((small(a) || small(b)) && merged.w <= 1.6 * refH && merged.h <= 1.4 * refH) return true
    // Parts touching or overlapping that together are no bigger than a
    // typical symbol (e.g. two small squares set diagonally).
    if (merged.w <= 1.15 * refH && merged.h <= 1.15 * refH) return true
  }

  // Stacked parts: "i", "j", "=", ":", accents, dotted pigpen glyphs...
  if (overlap(a.x0, a.x1, b.x0, b.x1) < 0.5 * Math.min(w(a), w(b))) return false
  if (gapY > 0.45 * refH) return false
  return merged.h <= 1.5 * refH
}

// Repeatedly merges pairs of boxes accepted by `predicate` until stable.
function mergeWhile(groups, refH, predicate) {
  let changed = true
  while (changed) {
    changed = false
    groups.sort((a, b) => a.x0 - b.x0)
    outer: for (let i = 0; i < groups.length; i++) {
      for (let j = i + 1; j < groups.length; j++) {
        const a = groups[i]
        const b = groups[j]
        // Sorted by x0: nothing further can overlap or be close enough.
        if (b.x0 > a.x1 + 0.08 * refH + 1) break
        if (predicate(a, b, refH)) {
          groups[i] = {
            x0: Math.min(a.x0, b.x0),
            y0: Math.min(a.y0, b.y0),
            x1: Math.max(a.x1, b.x1),
            y1: Math.max(a.y1, b.y1),
            area: a.area + b.area,
            members: a.members.concat(b.members),
          }
          groups.splice(j, 1)
          changed = true
          break outer
        }
      }
    }
  }
  return groups
}

export function mergeComponents(components, refH) {
  const groups = components.map((c, i) => ({ ...c, members: [i] }))
  // Absorb enclosed pieces first, so a crumb of a symbol isn't mistaken for
  // a separate part and glued to a neighbouring symbol.
  return mergeWhile(mergeWhile(groups, refH, contains), refH, shouldMerge)
}

// Scale-invariant description of a glyph: the glyph is fitted (keeping its
// aspect ratio) and centred in a square, then the ink coverage of each of
// the GRID x GRID cells is measured (0-255).
export function coverageGrid(labels, width, group) {
  const members = new Set(group.members.map((m) => m + 1))
  const gw = w(group)
  const gh = h(group)
  const side = Math.max(gw, gh)
  const offX = (side - gw) / 2
  const offY = (side - gh) / 2
  const cells = new Float64Array(GRID * GRID)

  for (let y = group.y0; y <= group.y1; y++) {
    for (let x = group.x0; x <= group.x1; x++) {
      if (!members.has(labels[y * width + x])) continue
      const cx = Math.min(GRID - 1, Math.floor(((x - group.x0 + offX + 0.5) * GRID) / side))
      const cy = Math.min(GRID - 1, Math.floor(((y - group.y0 + offY + 0.5) * GRID) / side))
      cells[cy * GRID + cx]++
    }
  }

  const cellArea = Math.max(1, (side / GRID) ** 2)
  const out = new Uint8Array(GRID * GRID)
  for (let i = 0; i < cells.length; i++) out[i] = Math.min(255, Math.round((cells[i] / cellArea) * 255))
  return out
}

export function toBase64(bytes) {
  let s = ""
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s)
}

// Merges components into glyphs, assuming the symbols of a cipher are all
// about the same size. The typical glyph height drives the merge rules, but
// it can only be measured once pieces are merged: symbols made of several
// pieces (bars, dots, inner fills) make the raw pieces much smaller than a
// glyph. So: estimate it on the pieces, merge, re-measure it on the merged
// glyphs, and merge again until the estimate settles.
export function mergeToGlyphSize(candidates, { maxPasses = 4 } = {}) {
  const glyphHeight = (boxes) => {
    const bigEnough = boxes.filter((c) => c.area >= 12)
    return median((bigEnough.length ? bigEnough : boxes).map(h))
  }

  let refH = glyphHeight(candidates)
  let groups = mergeComponents(candidates, refH)
  for (let pass = 1; pass < maxPasses; pass++) {
    const measured = glyphHeight(groups)
    if (Math.abs(measured - refH) <= Math.max(1, 0.05 * refH)) break
    refH = measured
    groups = mergeComponents(candidates, refH)
  }
  return { refH, groups }
}

export function detectGlyphs(gray, width, height, opts = {}) {
  const ink = binarize(gray, width, height, opts)
  const { labels, components } = connectedComponents(ink, width, height)

  // Drop frames / borders / huge blobs and single-pixel noise.
  const candidates = components.filter(
    (c) => c.area >= 3 && w(c) < 0.5 * width && h(c) < 0.5 * height,
  )
  if (candidates.length === 0) return []

  const { refH, groups: merged } = mergeToGlyphSize(candidates)

  const indexOf = new Map(components.map((c, i) => [c, i]))
  const groups = merged.map((g) => ({
    ...g,
    members: g.members.map((m) => indexOf.get(candidates[m])),
  }))

  // Specks: tiny, isolated marks that weren't merged into a real symbol.
  const refArea = median(groups.map((g) => g.area))
  const glyphs = groups.filter(
    (g) => !(Math.max(w(g), h(g)) < 0.1 * refH && g.area < 0.05 * refArea),
  )

  return glyphs.map((g) => ({
    x: g.x0,
    y: g.y0,
    w: w(g),
    h: h(g),
    f: toBase64(coverageGrid(labels, width, g)),
  }))
}

// The black and white pass of a picture: 1 for ink, 0 for background, by the
// same thresholding as detection (so light-on-dark pictures work too). Used
// as a mask to draw glyphs in any colour.
export function inkMask(rgba, width, height, opts = {}) {
  return binarize(toGrayscale(rgba, width, height), width, height, opts)
}
