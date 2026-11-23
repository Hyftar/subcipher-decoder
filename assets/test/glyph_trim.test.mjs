// Run with:  mix test.js
import { test } from "node:test"
import assert from "node:assert/strict"
import { contextRegion, keyMove, moveEdge } from "../js/glyph_trim.js"

test("the region shown around a glyph includes its detected box and a margin", () => {
  const box = { x: 50, y: 40, w: 10, h: 20 }
  assert.deepEqual(contextRegion(box, null, 200, 100), { x: 38, y: 28, w: 34, h: 44 })

  // A trimmed glyph: its detected box stays in view, to widen it again.
  const detected = { x: 45, y: 40, w: 15, h: 20 }
  assert.deepEqual(contextRegion(box, detected, 200, 100), { x: 33, y: 28, w: 39, h: 44 })

  // Kept inside the picture.
  assert.deepEqual(contextRegion({ x: 2, y: 1, w: 10, h: 10 }, null, 15, 12), { x: 0, y: 0, w: 15, h: 12 })
})

test("moving an edge keeps at least a pixel and stays in the picture", () => {
  const box = { x: 10, y: 10, w: 10, h: 10 }
  const bounds = { x: 0, y: 0, w: 40, h: 30 }
  assert.deepEqual(moveEdge(box, "left", 13.4, bounds), { x: 13, y: 10, w: 7, h: 10 })
  assert.deepEqual(moveEdge(box, "right", 25, bounds), { x: 10, y: 10, w: 15, h: 10 })
  assert.deepEqual(moveEdge(box, "top", 50, bounds), { x: 10, y: 19, w: 10, h: 1 })
  assert.deepEqual(moveEdge(box, "bottom", 99, bounds), { x: 10, y: 10, w: 10, h: 20 })
  assert.deepEqual(moveEdge(box, "left", -5, bounds), { x: 0, y: 10, w: 20, h: 10 })
})

test("arrow keys move the focused edge across it", () => {
  assert.equal(keyMove("left", "ArrowRight", false), 1)
  assert.equal(keyMove("right", "ArrowLeft", true), -5)
  assert.equal(keyMove("top", "ArrowDown", false), 1)
  assert.equal(keyMove("bottom", "ArrowLeft", false), null)
  assert.equal(keyMove("left", "Enter", false), null)
})
