import { inkMask } from "../glyph_detector"

// Pictures and their black and white pass (ink mask), loaded once per path
// and shared by the hooks that draw glyphs.
const images = new Map()
const masks = new Map()

export function loadImage(path) {
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

// {width, height, mask} (mask: 1 = ink) of the picture at `path`.
export function loadMask(path) {
  if (!masks.has(path)) {
    masks.set(
      path,
      loadImage(path).then((img) => {
        const width = img.naturalWidth
        const height = img.naturalHeight
        const canvas = document.createElement("canvas")
        canvas.width = width
        canvas.height = height
        const ctx = canvas.getContext("2d", { willReadFrequently: true })
        ctx.drawImage(img, 0, 0)
        const { data } = ctx.getImageData(0, 0, width, height)
        return { width, height, mask: inkMask(data, width, height) }
      }),
    )
  }
  return masks.get(path)
}
