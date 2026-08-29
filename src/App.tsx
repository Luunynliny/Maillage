// The shell: a sidebar, a centre pane, and whatever sheet is open on top of them.
//
// Selection is one entity reference and it lives here, mirrored into the URL hash so a reload —
// and the browser's own back button — land you where you were.

import { useCallback, useEffect, useState } from 'react'
import type { EntityKind } from '../shared/types.ts'
import { ENTITY_KINDS } from '../shared/types.ts'
import { Icon, IconButton } from './design/components.tsx'
import type { EntityRef } from './vault/derived.ts'
import { lookup } from './vault/derived.ts'
import { useVault } from './vault/store.tsx'
import { CenterPane } from './views/CenterPane.tsx'
import { CommandPalette } from './views/CommandPalette.tsx'
import { DeleteConfirmation, EditorSheet } from './views/Editors.tsx'
import { Sidebar } from './views/Sidebar.tsx'
import { VaultPicker } from './views/VaultPicker.tsx'
import './views/views.css'

export type EditorRequest =
  | { type: 'new'; kind: EntityKind; placeholder?: boolean }
  | { type: 'edit'; ref: EntityRef }
  | { type: 'addRelation'; id: string }
  | { type: 'resolve'; id: string }
  | { type: 'delete'; ref: EntityRef }

export function App() {
  const vault = useVault()
  const [selection, setSelection] = useState<EntityRef | null>(readHash)
  const [editor, setEditor] = useState<EditorRequest | null>(null)
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [pickingVault, setPickingVault] = useState(false)

  useEffect(() => {
    const onHashChange = () => setSelection(readHash())
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  const select = useCallback((ref: EntityRef | null) => {
    setSelection(ref)
    const hash = ref ? `#${ref.kind}/${encodeURIComponent(ref.id)}` : '#'
    if (window.location.hash !== hash) window.history.pushState(null, '', hash)
  }, [])

  // A selection whose file has gone — deleted, or renamed out from under us — falls back to the
  // overview rather than rendering a pane about nothing.
  const selected = lookup(vault.snapshot, selection)
  useEffect(() => {
    if (selection && !vault.loading && !selected) select(null)
  }, [selection, selected, vault.loading, select])

  if (vault.loading && !Object.keys(vault.snapshot.people).length) {
    return <div className="loading">Reading the vault…</div>
  }

  return (
    <div className="app">
      <Sidebar
        selection={selection}
        onSelect={select}
        onNew={(kind, placeholder) => setEditor({ type: 'new', kind, placeholder })}
        onEdit={(ref) => setEditor({ type: 'edit', ref })}
        onDelete={(ref) => setEditor({ type: 'delete', ref })}
        onOpenPalette={() => setPaletteOpen(true)}
        onPickVault={() => setPickingVault(true)}
      />

      <main className="center">
        <CenterPane
          entity={selected}
          onSelect={select}
          onEdit={(ref) => setEditor({ type: 'edit', ref })}
          onAddRelation={(id) => setEditor({ type: 'addRelation', id })}
          onResolve={(id) => setEditor({ type: 'resolve', id })}
        />
      </main>

      {vault.error && (
        <div className="error-banner" role="alert">
          <Icon name="warning" size={14} />
          <span>{vault.error}</span>
          <IconButton icon="close" label="Dismiss" onClick={vault.clearError} size={12} />
        </div>
      )}

      {paletteOpen && (
        <CommandPalette
          onSelect={(ref) => {
            setPaletteOpen(false)
            select(ref)
          }}
          onClose={() => setPaletteOpen(false)}
        />
      )}

      {pickingVault && <VaultPicker onClose={() => setPickingVault(false)} />}

      {editor?.type === 'delete' ? (
        <DeleteConfirmation
          target={editor.ref}
          onClose={() => setEditor(null)}
          onDeleted={() => {
            if (selection?.id === editor.ref.id && selection.kind === editor.ref.kind) select(null)
            setEditor(null)
          }}
        />
      ) : (
        editor && <EditorSheet request={editor} onClose={() => setEditor(null)} onSelect={select} />
      )}
    </div>
  )
}

function readHash(): EntityRef | null {
  const [kind, id] = window.location.hash.replace(/^#/, '').split('/')
  if (!kind || !id) return null
  return (ENTITY_KINDS as readonly string[]).includes(kind)
    ? { kind: kind as EntityKind, id: decodeURIComponent(id) }
    : null
}
