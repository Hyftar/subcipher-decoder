// Run with:  node --test assets/test/
// Also (re)generates test/fixtures/*.glyphs.json consumed by the ExUnit suite.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { detectGlyphs, inkIsLight, toGrayscale } from "../js/glyph_detector.js"

const fixtures = fileURLToPath(new URL("../../test/fixtures/", import.meta.url))
const plain = readFileSync(fixtures + "pangram.txt", "utf8")
const expectedCount = plain.replace(/\s/g, "").length

function load(name) {
  const [width, height] = readFileSync(`${fixtures}${name}.size`, "utf8").trim().split(" ").map(Number)
  const gray = new Uint8Array(readFileSync(`${fixtures}${name}.gray`))
  return { width, height, gray }
}

for (const name of ["pangram_clean", "pangram_photo"]) {
  test(`detects one glyph per cipher symbol in ${name}`, () => {
    const { width, height, gray } = load(name)
    const glyphs = detectGlyphs(gray, width, height)
    writeFileSync(`${fixtures}${name}.glyphs.json`, JSON.stringify({ width, height, glyphs }))
    assert.equal(glyphs.length, expectedCount)
    for (const g of glyphs) assert.equal(Buffer.from(g.f, "base64").length, 256)
  })
}

test("light pixel-art symbols with dark outlines and shadows", () => {
  // Symbols are light pink with thin black inner lines and a black drop
  // shadow, on a darker brown background: the ink is the pink, not the black.
  const [width, height] = readFileSync(fixtures + "pixel_glyphs.size", "utf8").trim().split(" ").map(Number)
  const gray = toGrayscale(new Uint8Array(readFileSync(fixtures + "pixel_glyphs.rgba")), width, height)
  assert.equal(inkIsLight(gray, width, height), true)

  const glyphs = detectGlyphs(gray, width, height)
  writeFileSync(fixtures + "pixel_glyphs.glyphs.json", JSON.stringify({ width, height, glyphs }))
  assert.equal(glyphs.length, 89)

  // Two-part symbols are kept whole: two small squares touching diagonally,
  // and a diamond overlapping a small square.
  const at = (x, y) => glyphs.find((g) => g.x === x && g.y === y)
  assert.deepEqual([at(137, 211).w, at(137, 211).h], [32, 32])
  assert.deepEqual([at(166, 107).w, at(166, 107).h], [32, 32])
  // A crumb of a symbol isn't glued to the symbol below it.
  assert.equal(at(214, 64).h, 32)
})

test("multi-part symbols are merged to the typical glyph size", () => {
  // Second picture of the same cipher: many symbols are made of several
  // pieces (bars, inner fills), so raw pieces are much smaller than glyphs.
  // The "two small squares" symbol must still come out whole (3 times).
  const [width, height] = readFileSync(fixtures + "pixel_glyphs_2.size", "utf8").trim().split(" ").map(Number)
  const gray = toGrayscale(new Uint8Array(readFileSync(fixtures + "pixel_glyphs_2.rgba")), width, height)
  const glyphs = detectGlyphs(gray, width, height)
  writeFileSync(fixtures + "pixel_glyphs_2.glyphs.json", JSON.stringify({ width, height, glyphs }))

  assert.equal(glyphs.length, 32)
  // Every glyph is glyph-sized except the large emblem at the bottom.
  const undersized = glyphs.filter((g) => Math.max(g.w, g.h) < 24)
  assert.deepEqual(undersized, [])
  const oversized = glyphs.filter((g) => Math.max(g.w, g.h) > 40)
  assert.deepEqual(oversized.map((g) => [g.w, g.h]), [[61, 60]])
})

test("handles light ink on dark background", () => {
  const { width, height, gray } = load("pangram_clean")
  const inverted = gray.map((v) => 255 - v)
  assert.equal(detectGlyphs(inverted, width, height).length, expectedCount)
})

test("blank image has no glyphs", () => {
  assert.deepEqual(detectGlyphs(new Uint8Array(100 * 50).fill(255), 100, 50), [])
})
