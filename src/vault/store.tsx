// The client's single source of truth, and the only thing that talks to the API.
//
// This is the port of `VaultStore`: one snapshot, derived indexes rebuilt from it, and every
// mutation funnelled through one place so what is on screen and what is on disk cannot drift.

import type { ReactNode } from 'react'
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type {
  AnyEntity,
  EntityID,
  EntityKind,
  ProjectMembership,
  VaultSnapshot,
} from '../../shared/types.ts'
import * as api from './api.ts'
import type { BacklinkIndex, OrganizationGroup } from './derived.ts'
import { buildBacklinks, peopleGroupedByOrganization } from './derived.ts'

const EMPTY: VaultSnapshot = {
  people: {},
  organizations: {},
  projects: {},
  logoIDs: { person: [], organization: [], project: [] },
  issues: [],
}

export interface VaultContextValue {
  snapshot: VaultSnapshot
  backlinks: BacklinkIndex
  groups: OrganizationGroup[]
  loading: boolean
  error: string | null
  vaultRoot: string
  /** Bumped on every logo write so an unchanged image URL still refreshes. */
  logoVersion: number
  hasLogo: (kind: EntityKind, id: EntityID) => boolean
  clearError: () => void
  reload: () => Promise<void>
  setVaultRoot: (path: string) => Promise<void>
  create: (entity: AnyEntity) => Promise<EntityID | undefined>
  update: (entity: AnyEntity) => Promise<void>
  remove: (kind: EntityKind, id: EntityID) => Promise<void>
  rename: (kind: EntityKind, id: EntityID, to: string) => Promise<EntityID | undefined>
  resolvePlaceholder: (
    id: EntityID,
    identity: { firstname?: string; lastname?: string; email?: string },
  ) => Promise<EntityID | undefined>
  setParticipants: (projectID: EntityID, roster: ProjectMembership[]) => Promise<void>
  setLogo: (kind: EntityKind, id: EntityID, png: Uint8Array) => Promise<void>
  removeLogo: (kind: EntityKind, id: EntityID) => Promise<void>
}

const VaultContext = createContext<VaultContextValue | null>(null)

export function useVault(): VaultContextValue {
  const value = useContext(VaultContext)
  if (!value) throw new Error('useVault outside a VaultProvider')
  return value
}

export function VaultProvider({ children }: { children: ReactNode }) {
  const [snapshot, setSnapshot] = useState<VaultSnapshot>(EMPTY)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [vaultRoot, setRoot] = useState('')
  const [logoVersion, setLogoVersion] = useState(0)

  const reload = useCallback(async () => {
    setLoading(true)
    try {
      const [next, config] = await Promise.all([api.fetchVault(), api.fetchConfig()])
      setSnapshot(next)
      setRoot(config.vaultRoot)
      setError(null)
    } catch (thrown) {
      setError(message(thrown))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void reload()
  }, [reload])

  /** Every mutation lands here: run it, take the fresh snapshot, or surface why it did not. */
  const apply = useCallback(async (call: () => Promise<api.Mutation>) => {
    try {
      const result = await call()
      setSnapshot(result.snapshot)
      setError(null)
      return result.id
    } catch (thrown) {
      setError(message(thrown))
      return undefined
    }
  }, [])

  const backlinks = useMemo(() => buildBacklinks(snapshot), [snapshot])
  const groups = useMemo(() => peopleGroupedByOrganization(snapshot), [snapshot])
  const logoSets = useMemo(
    () => ({
      person: new Set(snapshot.logoIDs.person),
      organization: new Set(snapshot.logoIDs.organization),
      project: new Set(snapshot.logoIDs.project),
    }),
    [snapshot],
  )

  const value: VaultContextValue = {
    snapshot,
    backlinks,
    groups,
    loading,
    error,
    vaultRoot,
    logoVersion,
    hasLogo: (kind, id) => logoSets[kind].has(id),
    clearError: () => setError(null),
    reload,
    setVaultRoot: async (path) => {
      try {
        const config = await api.saveConfig(path)
        setRoot(config.vaultRoot)
        await reload()
      } catch (thrown) {
        setError(message(thrown))
      }
    },
    create: (entity) => apply(() => api.createEntity(entity)),
    update: async (entity) => void (await apply(() => api.updateEntity(entity))),
    remove: async (kind, id) => void (await apply(() => api.deleteEntity(kind, id))),
    rename: (kind, id, to) => apply(() => api.renameEntity(kind, id, to)),
    resolvePlaceholder: (id, identity) => apply(() => api.resolvePlaceholder(id, identity)),
    setParticipants: async (projectID, roster) =>
      void (await apply(() => api.setParticipants(projectID, roster))),
    setLogo: async (kind, id, png) => {
      await apply(() => api.putLogo(kind, id, png))
      setLogoVersion((version) => version + 1)
    },
    removeLogo: async (kind, id) => {
      await apply(() => api.deleteLogo(kind, id))
      setLogoVersion((version) => version + 1)
    },
  }

  return <VaultContext.Provider value={value}>{children}</VaultContext.Provider>
}

function message(thrown: unknown): string {
  return thrown instanceof Error ? thrown.message : String(thrown)
}
