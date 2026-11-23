// Run with:  mix test.js
import { test } from "node:test"
import assert from "node:assert/strict"
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
} from "../js/symbol_image.js"

const glyph = (w, h = 40, scale = 1) => ({ t: "glyph", w, h, scale })

test("hex colours", () => {
  assert.deepEqual(parseHex("#6b5a3c"), [107, 90, 60])
  assert.equal(toHex([107, 90, 60]), "#6b5a3c")
  assert.equal(parseHex("auto"), null)
})

test("the background is the median of the border of the crops", () => {
  // 4x4 brown image with a pink pixel on the border and pink ink inside.
  const brown = [107, 90, 60, 255]
  const pink = [250, 160, 160, 255]
  const data = []
  for (let y = 0; y < 4; y++)
    for (let x = 0; x < 4; x++) data.push(...((x === 0 && y === 0) || (x === 1 && y === 1) ? pink : brown))

  const samples = borderSamples(data, 4, 4, 1)
  assert.equal(samples.length, 12)
  assert.deepEqual(estimateBackground(samples), [107, 90, 60])
  assert.deepEqual(estimateBackground([]), [255, 255, 255])
})

test("recolor repaints the background, keeps the ink, blends in between", () => {
  const data = new Uint8ClampedArray([107, 90, 60, 255, 250, 160, 160, 255, 160, 120, 100, 255])
  recolor(data, [107, 90, 60], [255, 255, 255], 60)
  assert.deepEqual([...data.slice(0, 3)], [255, 255, 255]) // background
  assert.deepEqual([...data.slice(4, 7)], [250, 160, 160]) // ink, far from the background
  const blended = [...data.slice(8, 11)]
  assert.ok(blended[0] > 160 && blended[0] < 255) // in between: partly repainted
})

test("layout aligns each line left, center or right", () => {
  const lines = [[glyph(100)], [glyph(40)]]
  for (const [align, x] of [["left", 24], ["center", 24 + 30], ["right", 24 + 60]]) {
    const { width, items } = layout(lines, { align, margin: 24, gap: 0 })
    assert.equal(width, 100 + 48)
    assert.equal(items[0].x, 24)
    assert.equal(items[1].x, x, align)
  }
})

test("layout spaces words, scales glyphs and centres them vertically", () => {
  const { items, height } = layout([[glyph(10), glyph(10), { t: "space" }, glyph(10, 20, 2)]], {
    gap: 4, space: 20, margin: 0, lineHeight: 48, align: "left",
  })
  assert.deepEqual(items.map((i) => i.x), [0, 14, 44])
  assert.deepEqual([items[2].w, items[2].h], [20, 40])
  assert.equal(items[0].y, 4) // (48 - 40) / 2
  assert.equal(height, 48)
})

test("layout wraps long lines at spaces", () => {
  const words = Array.from({ length: 10 }, () => [glyph(100), { t: "space" }]).flat()
  const { items, width } = layout([words], { maxWidth: 350, margin: 0, space: 20, align: "left" })
  const rows = new Set(items.map((i) => i.y))
  assert.equal(rows.size, 4) // 3 words of 100 + 2 spaces = 340 per row
  assert.ok(width <= 350)
})

test("a glyph's mask: cropped to its box, painted in the ink colour", () => {
  // 5x4 mask, ink at (1,1), (2,1) and (4,3) (outside the box).
  const mask = new Uint8Array(20)
  mask[1 * 5 + 1] = 1
  mask[1 * 5 + 2] = 1
  mask[3 * 5 + 4] = 1
  const crop = cropMask(mask, 5, { x: 1, y: 1, w: 2, h: 2 }, 1)
  assert.equal(crop.w, 4)
  assert.equal(crop.h, 4)
  assert.deepEqual([...crop.data], [0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])

  const painted = paintMask(crop, [200, 10, 20])
  assert.deepEqual([...painted.slice(5 * 4, 6 * 4)], [200, 10, 20, 255])
  assert.equal(painted[0 * 4 + 3], 0) // transparent elsewhere

  // The ink colour comes from the pixels under the mask.
  const pixels = new Uint8ClampedArray(16 * 4).fill(90)
  pixels.set([250, 120, 200, 255], 5 * 4)
  pixels.set([240, 110, 190, 255], 6 * 4)
  assert.deepEqual(estimateBackground(inkSamples(pixels, crop)), [250, 120, 200])
})
