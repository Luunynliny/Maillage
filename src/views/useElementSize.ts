// Both graphs lay out from the pane's measured size, the way the SwiftUI original read a
// GeometryReader.

import { useCallback, useEffect, useRef, useState } from 'react'
import type { Size } from '../graph/geometry.ts'

export function useElementSize(): [(node: HTMLDivElement | null) => void, Size] {
  const [size, setSize] = useState<Size>({ width: 0, height: 0 })
  const observer = useRef<ResizeObserver | null>(null)

  useEffect(() => () => observer.current?.disconnect(), [])

  const ref = useCallback((node: HTMLDivElement | null) => {
    observer.current?.disconnect()
    if (!node) return
    observer.current = new ResizeObserver(([entry]) => {
      const box = entry?.contentRect
      if (box) setSize({ width: Math.round(box.width), height: Math.round(box.height) })
    })
    observer.current.observe(node)
  }, [])

  return [ref, size]
}
