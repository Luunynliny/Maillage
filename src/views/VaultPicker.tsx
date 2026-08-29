// Which folder is the vault.
//
// A path typed in rather than a folder chooser: the browser's own picker hands back a sandboxed
// handle, not a path, and the process that has to open the folder is the server, not the page.

import { useState } from 'react'
import { FormField, Sheet, TextInput } from '../design/components.tsx'
import { useVault } from '../vault/store.tsx'

export function VaultPicker({ onClose }: { onClose: () => void }) {
  const vault = useVault()
  const [path, setPath] = useState(vault.vaultRoot)

  return (
    <Sheet
      title="Vault folder"
      subtitle="One folder, one markdown file per person, organization and project. It is created if it does not exist yet."
      confirmLabel="Open"
      confirmDisabled={!path.trim() || path.trim() === vault.vaultRoot}
      onCancel={onClose}
      onConfirm={() => {
        void vault.setVaultRoot(path.trim())
        onClose()
      }}
    >
      <FormField
        label="Path"
        hint="`~` is expanded. The server reads and writes this folder directly."
      >
        <TextInput value={path} onChange={setPath} placeholder="~/Documents/Maillage" autoFocus />
      </FormField>
    </Sheet>
  )
}
