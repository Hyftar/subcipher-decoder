// Run with:  node --test assets/test/
// Also (re)generates test/fixtures/*.glyphs.json consumed by the ExUnit suite.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { detectGlyphs } from "../js/glyph_detector.js"

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

test("handles light ink on dark background", () => {
  const { width, height, gray } = load("pangram_clean")
  const inverted = gray.map((v) => 255 - v)
  assert.equal(detectGlyphs(inverted, width, height).length, expectedCount)
})

test("blank image has no glyphs", () => {
  assert.deepEqual(detectGlyphs(new Uint8Array(100 * 50).fill(255), 100, 50), [])
})
