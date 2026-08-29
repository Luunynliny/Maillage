// Typed wrappers over the server. Every mutation answers with the whole vault, so callers replace
// their snapshot rather than patching it — there is no client-side cache to invalidate.

import type {
  AnyEntity,
  EntityID,
  EntityKind,
  ProjectMembership,
  VaultSnapshot,
} from '../../shared/types.ts'

export interface Mutation {
  id?: EntityID
  snapshot: VaultSnapshot
}

export interface Config {
  vaultRoot: string
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init)
  const body: unknown = await response.json().catch(() => ({}))
  if (!response.ok) {
    const message =
      (body as { error?: string }).error ?? `${response.status} ${response.statusText}`
    throw new Error(message)
  }
  return body as T
}

const json = (body: unknown): RequestInit => ({
  method: 'PUT',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
})

export function fetchVault(): Promise<VaultSnapshot> {
  return request('/api/vault')
}

export function fetchConfig(): Promise<Config> {
  return request('/api/config')
}

export function saveConfig(vaultRoot: string): Promise<Config> {
  return request('/api/config', json({ vaultRoot }))
}

export function createEntity(entity: AnyEntity): Promise<Mutation> {
  return request(`/api/entity/${entity.kind}`, { ...json(entity), method: 'POST' })
}

export function updateEntity(entity: AnyEntity): Promise<Mutation> {
  return request(`/api/entity/${entity.kind}/${encodeURIComponent(entity.id)}`, json(entity))
}

export function deleteEntity(kind: EntityKind, id: EntityID): Promise<Mutation> {
  return request(`/api/entity/${kind}/${encodeURIComponent(id)}`, { method: 'DELETE' })
}

export function renameEntity(kind: EntityKind, id: EntityID, to: string): Promise<Mutation> {
  return request(`/api/entity/${kind}/${encodeURIComponent(id)}/rename`, {
    ...json({ to }),
    method: 'POST',
  })
}

export function resolvePlaceholder(
  id: EntityID,
  identity: { firstname?: string; lastname?: string; email?: string },
): Promise<Mutation> {
  return request(`/api/entity/person/${encodeURIComponent(id)}/resolve`, {
    ...json(identity),
    method: 'POST',
  })
}

export function setParticipants(
  projectID: EntityID,
  roster: ProjectMembership[],
): Promise<Mutation> {
  return request(`/api/participants/${encodeURIComponent(projectID)}`, json(roster))
}

export function putLogo(kind: EntityKind, id: EntityID, png: Uint8Array): Promise<Mutation> {
  return request(`/api/logo/${kind}/${encodeURIComponent(id)}`, {
    method: 'PUT',
    headers: { 'content-type': 'image/png' },
    body: png as BodyInit,
  })
}

export function deleteLogo(kind: EntityKind, id: EntityID): Promise<Mutation> {
  return request(`/api/logo/${kind}/${encodeURIComponent(id)}`, { method: 'DELETE' })
}
