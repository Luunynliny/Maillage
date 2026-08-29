// A logo is always a 512×512 centre-cropped PNG, whatever went in. One place decides the format,
// the size and the crop, so a wide wordmark loses its ends rather than being squashed, and nothing
// is ever resampled twice.
//
// ponytail: the browser's own decoders, so what can be imported is what this browser can display —
// PNG, JPEG, WebP, AVIF, GIF, SVG, and HEIC only on Safari. Server-side decoding would need a
// native image library; add one if a format someone actually has turns out to be missing.

const SIZE = 512

export async function squarePNG(file: File | Blob): Promise<Uint8Array> {
  const bitmap = await decode(file)
  const canvas = document.createElement('canvas')
  canvas.width = SIZE
  canvas.height = SIZE
  const context = canvas.getContext('2d')
  if (!context) throw new Error('this browser would not give us a canvas to draw on')

  // Centre-crop and scale in one draw: take the largest square the source contains, put it in the
  // whole canvas.
  const side = Math.min(bitmap.width, bitmap.height)
  context.imageSmoothingQuality = 'high'
  context.drawImage(
    bitmap,
    (bitmap.width - side) / 2,
    (bitmap.height - side) / 2,
    side,
    side,
    0,
    0,
    SIZE,
    SIZE,
  )

  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'))
  if (!blob) throw new Error('could not encode that image as PNG')
  return new Uint8Array(await blob.arrayBuffer())
}

/**
 * `createImageBitmap` handles every raster format the browser knows but refuses most SVGs, which
 * have no intrinsic pixel size. An `<img>` element rasterises those, so try it as the fallback.
 */
async function decode(
  file: File | Blob,
): Promise<CanvasImageSource & { width: number; height: number }> {
  try {
    return await createImageBitmap(file)
  } catch {
    const url = URL.createObjectURL(file)
    try {
      const image = new Image()
      image.width = SIZE
      image.height = SIZE
      await new Promise<void>((resolve, reject) => {
        image.onload = () => resolve()
        image.onerror = () => reject(new Error('that file is not an image this browser can read'))
        image.src = url
      })
      return image
    } finally {
      URL.revokeObjectURL(url)
    }
  }
}
