// The one process. It serves the client and owns the vault, so there is no proxy to configure, no
// CORS, and no second terminal: `npm run dev` and `npm start` both start exactly this.
//
// Bound to loopback on purpose. The vault is a folder of personal notes on someone's own machine;
// nothing here authenticates, because nothing else can reach it.

import { readFile, stat } from 'node:fs/promises'
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http'
import { extname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { slugify } from '../shared/wikilink.ts'
import type { AnyEntity, EntityKind, Person, ProjectMembership } from '../shared/types.ts'
import { KIND_DIRECTORY } from '../shared/types.ts'
import { readConfig, writeConfig } from './config.ts'
import {
  VaultError,
  assertSafeID,
  createEntity,
  deleteEntity,
  ensureSkeleton,
  isEntityKind,
  readLogo,
  readVault,
  removeLogo,
  renameEntity,
  resolvePlaceholder,
  setParticipants,
  writeEntity,
  writeLogo,
} from './vault.ts'

const ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)))
const DIST = join(ROOT, 'dist')
const PORT = Number(process.env.PORT ?? 3000)
const DEV = process.env.MAILLAGE_DEV === '1'

const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.json': 'application/json; charset=utf-8',
}

// -- api --------------------------------------------------------------------------------------

/**
 * Every mutation answers with the whole vault, freshly read. At this size a re-read is a couple of
 * milliseconds, and it means the client can never hold a snapshot that disagrees with the disk —
 * no cache invalidation, no partial updates, no drift after a rename touches thirty files.
 *
 * ponytail: full re-read per write. Return a delta if a vault ever gets big enough to notice.
 */
async function api(request: IncomingMessage, response: ServerResponse, path: string) {
  const { vaultRoot } = await readConfig()
  const method = request.method ?? 'GET'
  const segments = path.split('/').filter(Boolean).slice(1) // drop "api"

  if (segments[0] === 'config') {
    if (method === 'GET') return send(response, 200, await readConfig())
    if (method === 'PUT') {
      const body = (await readJSON(request)) as { vaultRoot?: string }
      if (!body.vaultRoot?.trim()) throw new VaultError('a vault path is required')
      const config = await writeConfig({ vaultRoot: body.vaultRoot })
      await ensureSkeleton(config.vaultRoot)
      return send(response, 200, config)
    }
  }

  if (segments[0] === 'vault' && method === 'GET') {
    await ensureSkeleton(vaultRoot)
    return send(response, 200, await readVault(vaultRoot))
  }

  if (segments[0] === 'entity') {
    const kind = segments[1] ?? ''
    if (!isEntityKind(kind)) throw new VaultError(`unknown kind: ${kind}`)
    const id = segments[2]

    if (method === 'POST' && !id) {
      const created = await createEntity(vaultRoot, ofKind(await readJSON(request), kind))
      return send(response, 200, { id: created.id, snapshot: await readVault(vaultRoot) })
    }
    if (method === 'PUT' && id) {
      const entity = ofKind(await readJSON(request), kind)
      entity.id = assertSafeID(id)
      await writeEntity(vaultRoot, entity)
      return send(response, 200, { id, snapshot: await readVault(vaultRoot) })
    }
    if (method === 'DELETE' && id) {
      await deleteEntity(vaultRoot, kind, assertSafeID(id))
      return send(response, 200, { snapshot: await readVault(vaultRoot) })
    }
    if (method === 'POST' && id && segments[3] === 'rename') {
      const body = (await readJSON(request)) as { to?: string }
      const to = await renameEntity(vaultRoot, kind, assertSafeID(id), slugify(body.to ?? ''))
      return send(response, 200, { id: to, snapshot: await readVault(vaultRoot) })
    }
    if (method === 'POST' && id && segments[3] === 'resolve') {
      const body = (await readJSON(request)) as Pick<Person, 'firstname' | 'lastname' | 'email'>
      const slug = slugify([body.firstname, body.lastname].filter(Boolean).join(' '))
      const to = await resolvePlaceholder(vaultRoot, assertSafeID(id), body, slug)
      return send(response, 200, { id: to, snapshot: await readVault(vaultRoot) })
    }
  }

  if (segments[0] === 'participants' && segments[1] && method === 'PUT') {
    const roster = (await readJSON(request)) as ProjectMembership[]
    await setParticipants(vaultRoot, assertSafeID(segments[1]), roster)
    return send(response, 200, { snapshot: await readVault(vaultRoot) })
  }

  if (segments[0] === 'logo' && segments[1] && segments[2]) {
    const kind = segments[1]
    if (!isEntityKind(kind)) throw new VaultError(`unknown kind: ${kind}`)
    const id = assertSafeID(segments[2])
    if (method === 'PUT') {
      await writeLogo(vaultRoot, kind, id, await readBody(request))
      return send(response, 200, { snapshot: await readVault(vaultRoot) })
    }
    if (method === 'DELETE') {
      await removeLogo(vaultRoot, kind, id)
      return send(response, 200, { snapshot: await readVault(vaultRoot) })
    }
  }

  send(response, 404, { error: `no route for ${method} ${path}` })
}

/** The body says what it is; the URL says what it should be. They have to agree. */
function ofKind(body: unknown, kind: EntityKind): AnyEntity {
  const entity = body as AnyEntity | null
  if (!entity || entity.kind !== kind) throw new VaultError(`request body is not a ${kind}`)
  return entity
}

/** `assets/<dir>/<id>.png`, straight off the vault. */
async function serveLogo(response: ServerResponse, path: string): Promise<boolean> {
  const [, , dir, file] = path.split('/')
  const kind = (Object.keys(KIND_DIRECTORY) as EntityKind[]).find(
    (candidate) => KIND_DIRECTORY[candidate] === dir,
  )
  if (!kind || !file?.endsWith('.png')) return false
  const { vaultRoot } = await readConfig()
  const png = await readLogo(vaultRoot, kind, file.slice(0, -'.png'.length))
  if (!png) return false
  // A logo changes only when it is replaced, and a replacement changes nothing about its URL, so
  // the client appends a cache-busting query of its own after a write.
  response.writeHead(200, { 'content-type': 'image/png', 'cache-control': 'no-cache' })
  response.end(png)
  return true
}

// -- static -----------------------------------------------------------------------------------

async function serveStatic(response: ServerResponse, path: string): Promise<boolean> {
  const file = join(DIST, path)
  if (!file.startsWith(DIST)) return false
  try {
    if (!(await stat(file)).isFile()) return false
  } catch {
    return false
  }
  response.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' })
  response.end(await readFile(file))
  return true
}

// -- plumbing ---------------------------------------------------------------------------------

function send(response: ServerResponse, status: number, body: unknown): void {
  const json = JSON.stringify(body)
  response.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  response.end(json)
}

async function readBody(request: IncomingMessage): Promise<Uint8Array> {
  const chunks: Uint8Array[] = []
  for await (const chunk of request) chunks.push(chunk as Uint8Array)
  return Buffer.concat(chunks)
}

async function readJSON(request: IncomingMessage): Promise<unknown> {
  const raw = Buffer.from(await readBody(request)).toString('utf8')
  return raw ? JSON.parse(raw) : {}
}

async function start(): Promise<void> {
  // Vite is a devDependency, so it is only ever imported on the development path.
  const vite = DEV
    ? await (
        await import('vite')
      ).createServer({
        server: { middlewareMode: true },
        appType: 'custom',
      })
    : undefined

  const server = createServer((request, response) => {
    void (async () => {
      const path = new URL(request.url ?? '/', 'http://localhost').pathname
      try {
        if (path.startsWith('/api/')) return await api(request, response, path)
        if (path.startsWith('/assets/') && (await serveLogo(response, path))) return

        if (vite) {
          return vite.middlewares(request, response, () => {
            void servePage(response, vite.transformIndexHtml.bind(vite), request.url ?? '/')
          })
        }
        if (await serveStatic(response, path)) return
        await servePage(response, undefined, path)
      } catch (error) {
        const status = error instanceof VaultError ? 400 : 500
        send(response, status, { error: error instanceof Error ? error.message : String(error) })
      }
    })()
  })

  const { vaultRoot } = await readConfig()
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`maillage → http://localhost:${PORT}`)
    console.log(`vault    → ${vaultRoot}`)
  })
}

async function servePage(
  response: ServerResponse,
  transform: ((url: string, html: string) => Promise<string>) | undefined,
  url: string,
): Promise<void> {
  const source = await readFile(join(transform ? ROOT : DIST, 'index.html'), 'utf8')
  const html = transform ? await transform(url, source) : source
  response.writeHead(200, { 'content-type': MIME['.html']! })
  response.end(html)
}

await start()
