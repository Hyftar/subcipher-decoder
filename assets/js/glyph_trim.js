// Geometry of the glyph crop editor (hooks/glyph_trim_hook.js). Pure
// functions, unit tested with Node (assets/test/glyph_trim.test.mjs).

// The region of the picture shown around a glyph: its box (and the box
// detection found, so a trimmed glyph can be widened again) with a margin,
// kept inside the picture.
export function contextRegion(box, detected, imageWidth, imageHeight) {
  const x0 = Math.min(box.x, detected?.x ?? box.x)
  const y0 = Math.min(box.y, detected?.y ?? box.y)
  const x1 = Math.max(box.x + box.w, detected ? detected.x + detected.w : 0)
  const y1 = Math.max(box.y + box.h, detected ? detected.y + detected.h : 0)
  const margin = Math.max(6, Math.round(Math.max(x1 - x0, y1 - y0) * 0.6))
  const left = Math.max(0, x0 - margin)
  const top = Math.max(0, y0 - margin)
  const right = Math.min(imageWidth, x1 + margin)
  const bottom = Math.min(imageHeight, y1 + margin)
  return { x: left, y: top, w: right - left, h: bottom - top }
}

// Moves one edge ("left", "right", "top" or "bottom") of `box` to `to` (a
// picture coordinate, rounded), keeping at least 1 pixel and staying inside
// `bounds` ({x, y, w, h}).
export function moveEdge(box, edge, to, bounds) {
  const v = Math.round(to)
  let x0 = box.x
  let y0 = box.y
  let x1 = box.x + box.w
  let y1 = box.y + box.h
  if (edge === "left") x0 = Math.min(Math.max(v, bounds.x), x1 - 1)
  if (edge === "right") x1 = Math.max(Math.min(v, bounds.x + bounds.w), x0 + 1)
  if (edge === "top") y0 = Math.min(Math.max(v, bounds.y), y1 - 1)
  if (edge === "bottom") y1 = Math.max(Math.min(v, bounds.y + bounds.h), y0 + 1)
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

// The edge a key moves, and by how much: arrows across a vertical edge
// (left / right) or a horizontal one (top / bottom). Null for other keys.
export function keyMove(edge, key, shift) {
  const step = shift ? 5 : 1
  const horizontal = edge === "left" || edge === "right"
  if (horizontal && key === "ArrowLeft") return -step
  if (horizontal && key === "ArrowRight") return step
  if (!horizontal && key === "ArrowUp") return -step
  if (!horizontal && key === "ArrowDown") return step
  return null
}
