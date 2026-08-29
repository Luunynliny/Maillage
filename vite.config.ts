import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// The client is built into dist/ and served by server/index.ts. In development that same server
// mounts Vite in middleware mode, so there is one process and one port either way — no proxy, no
// second terminal, no CORS.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true },
  test: {
    environment: 'node',
    include: ['{shared,server,src}/**/*.test.ts'],
  },
})
