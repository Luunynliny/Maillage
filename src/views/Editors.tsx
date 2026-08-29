// Every sheet that writes to the vault.
//
// Two rules hold across all of them. Membership is edited here and nowhere else — the panes are
// display-only — and everything applies on save, so an abandoned sheet writes nothing at all,
// logos and rosters included.

import { useMemo, useState } from 'react'
import { today } from '../../shared/calendarDay.ts'
import type {
  AnyEntity,
  EntityID,
  EntityKind,
  Organization,
  Person,
  Project,
  ProjectMembership,
  ProjectStatus,
} from '../../shared/types.ts'
import { KIND_LABEL, PROJECT_STATUSES, displayName } from '../../shared/types.ts'
import { slugify } from '../../shared/wikilink.ts'
import {
  EntityAvatar,
  FormField,
  Icon,
  IconButton,
  Pill,
  SearchField,
  Sheet,
  TextInput,
} from '../design/components.tsx'
import type { EntityRef } from '../vault/derived.ts'
import {
  allOrganizations,
  allPeople,
  allProjects,
  membersOfOrganization,
  participantsOfProject,
  projectsInOrganization,
  usedRelationLabels,
} from '../vault/derived.ts'
import { squarePNG } from '../vault/image.ts'
import { useVault } from '../vault/store.tsx'
import type { EditorRequest } from '../App.tsx'

export function EditorSheet({
  request,
  onClose,
  onSelect,
}: {
  // Deletion has its own sheet in App; everything else lands here.
  request: Exclude<EditorRequest, { type: 'delete' }>
  onClose: () => void
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()

  if (request.type === 'addRelation') {
    const person = vault.snapshot.people[request.id]
    return person ? <RelationEditor person={person} onClose={onClose} /> : null
  }
  if (request.type === 'resolve') {
    const person = vault.snapshot.people[request.id]
    return person ? <ResolveEditor person={person} onClose={onClose} onSelect={onSelect} /> : null
  }

  const existing =
    request.type === 'edit'
      ? request.ref.kind === 'person'
        ? vault.snapshot.people[request.ref.id]
        : request.ref.kind === 'organization'
          ? vault.snapshot.organizations[request.ref.id]
          : vault.snapshot.projects[request.ref.id]
      : undefined

  const kind: EntityKind = request.type === 'edit' ? request.ref.kind : request.kind
  const placeholder = request.type === 'new' && request.placeholder === true

  if (kind === 'person') {
    return (
      <PersonEditor
        existing={existing as Person | undefined}
        placeholder={placeholder}
        onClose={onClose}
        onSelect={onSelect}
      />
    )
  }
  if (kind === 'organization') {
    return (
      <OrganizationEditor
        existing={existing as Organization | undefined}
        onClose={onClose}
        onSelect={onSelect}
      />
    )
  }
  return (
    <ProjectEditor
      existing={existing as Project | undefined}
      onClose={onClose}
      onSelect={onSelect}
    />
  )
}

// -- staged logo -------------------------------------------------------------------------------

type LogoChange =
  | { kind: 'keep' }
  | { kind: 'set'; png: Uint8Array; preview: string }
  | { kind: 'remove' }

function LogoField({
  entityKind,
  id,
  hasLogo,
  change,
  onChange,
}: {
  entityKind: EntityKind
  id: EntityID
  hasLogo: boolean
  change: LogoChange
  onChange: (change: LogoChange) => void
}) {
  const vault = useVault()
  const [error, setError] = useState<string | null>(null)
  const showing = change.kind === 'set' ? change.preview : null
  const keeping = change.kind === 'keep' && hasLogo

  return (
    <FormField
      label="Logo"
      hint="Anything the browser can decode. Stored as a 512×512 centre-cropped PNG in assets/."
    >
      <div className="logo-field">
        {showing ? (
          <img className="avatar" src={showing} width={64} height={64} alt="" />
        ) : (
          <EntityAvatar
            kind={entityKind}
            id={id}
            size={64}
            hasLogo={keeping}
            version={vault.logoVersion}
          />
        )}
        <div className="logo-actions">
          <label className="button button-secondary">
            Choose…
            <input
              type="file"
              accept="image/*"
              hidden
              onChange={async (event) => {
                const file = event.target.files?.[0]
                if (!file) return
                try {
                  const png = await squarePNG(file)
                  onChange({
                    kind: 'set',
                    png,
                    preview: URL.createObjectURL(
                      new Blob([png as BlobPart], { type: 'image/png' }),
                    ),
                  })
                  setError(null)
                } catch (thrown) {
                  setError(thrown instanceof Error ? thrown.message : String(thrown))
                }
              }}
            />
          </label>
          {(keeping || change.kind === 'set') && (
            <button
              className="button button-secondary button-danger"
              type="button"
              onClick={() => onChange({ kind: 'remove' })}
            >
              Remove
            </button>
          )}
        </div>
      </div>
      {error && <span className="field-error">{error}</span>}
    </FormField>
  )
}

async function applyLogo(
  vault: ReturnType<typeof useVault>,
  kind: EntityKind,
  id: EntityID,
  change: LogoChange,
): Promise<void> {
  if (change.kind === 'set') await vault.setLogo(kind, id, change.png)
  if (change.kind === 'remove') await vault.removeLogo(kind, id)
}

// -- shared pickers ----------------------------------------------------------------------------

/** Free text with the vault's own vocabulary underneath it — whatever labels are already in use,
 * most-used first. Not a picker: a label nobody has typed before is still a valid label. */
function LabelField({
  label,
  value,
  onChange,
  known,
  placeholder,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  known: string[]
  placeholder?: string
}) {
  return (
    <FormField label={label}>
      <TextInput value={value} onChange={onChange} placeholder={placeholder} autoFocus />
      {known.length > 0 && (
        <div className="pill-cloud">
          {known.slice(0, 8).map((suggestion) => (
            <Pill key={suggestion} onClick={() => onChange(suggestion)}>
              {suggestion}
            </Pill>
          ))}
        </div>
      )}
    </FormField>
  )
}

function EntityPicker({
  label,
  options,
  selected,
  onChange,
  single,
  hint,
}: {
  label: string
  options: AnyEntity[]
  selected: EntityID[]
  onChange: (selected: EntityID[]) => void
  single?: boolean
  hint?: string
}) {
  const vault = useVault()
  const [query, setQuery] = useState('')
  const needle = query.trim().toLowerCase()
  const shown = options.filter(
    (option) => !needle || displayName(option).toLowerCase().includes(needle),
  )

  return (
    <FormField label={label} hint={hint}>
      {selected.length > 0 && (
        <div className="pill-cloud">
          {selected.map((id) => {
            const option = options.find((candidate) => candidate.id === id)
            return (
              <Pill
                key={id}
                color={`var(--${option?.kind ?? 'person'})`}
                onRemove={() => onChange(selected.filter((entry) => entry !== id))}
              >
                {option ? displayName(option) : id}
              </Pill>
            )
          })}
        </div>
      )}
      <SearchField value={query} onChange={setQuery} placeholder="Search…" />
      <div className="picker-list">
        {shown.map((option) => (
          <button
            key={option.id}
            type="button"
            className={`picker-row${selected.includes(option.id) ? ' picker-row-on' : ''}`}
            onClick={() =>
              onChange(
                single
                  ? selected.includes(option.id)
                    ? []
                    : [option.id]
                  : selected.includes(option.id)
                    ? selected.filter((entry) => entry !== option.id)
                    : [...selected, option.id],
              )
            }
          >
            <EntityAvatar
              kind={option.kind}
              id={option.id}
              hasLogo={vault.hasLogo(option.kind, option.id)}
              isPlaceholder={option.kind === 'person' && option.placeholder}
              version={vault.logoVersion}
            />
            <span>{displayName(option)}</span>
          </button>
        ))}
        {!shown.length && <p className="muted picker-empty">Nothing matches that.</p>}
      </div>
    </FormField>
  )
}

/** A role per selected entry. Plain free text: a role is what one person does on one project and
 * is nearly always typed fresh, so there is no suggestion menu behind it. */
function RoleRows({
  rows,
  roles,
  onChange,
}: {
  rows: { id: EntityID; label: string }[]
  roles: Record<EntityID, string>
  onChange: (roles: Record<EntityID, string>) => void
}) {
  if (!rows.length) return null
  return (
    <div className="role-rows">
      {rows.map((row) => (
        <label className="role-row" key={row.id}>
          <span>{row.label}</span>
          <input
            className="text-input"
            value={roles[row.id] ?? ''}
            placeholder="Role"
            onChange={(event) => onChange({ ...roles, [row.id]: event.target.value })}
          />
        </label>
      ))}
    </div>
  )
}

// -- person ------------------------------------------------------------------------------------

function PersonEditor({
  existing,
  placeholder,
  onClose,
  onSelect,
}: {
  existing?: Person
  placeholder: boolean
  onClose: () => void
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const unnamed = existing ? existing.placeholder : placeholder

  const [firstname, setFirstname] = useState(existing?.firstname ?? '')
  const [lastname, setLastname] = useState(existing?.lastname ?? '')
  const [descriptor, setDescriptor] = useState(existing?.descriptor ?? '')
  const [email, setEmail] = useState(existing?.email ?? '')
  const [role, setRole] = useState(existing?.role ?? '')
  const [body, setBody] = useState(existing?.body ?? '')
  const [organization, setOrganization] = useState<EntityID[]>(
    existing?.organization ? [existing.organization] : [],
  )
  const [projects, setProjects] = useState<EntityID[]>(
    existing?.projects.map((entry) => entry.to) ?? [],
  )
  const [roles, setRoles] = useState<Record<EntityID, string>>(
    Object.fromEntries(
      (existing?.projects ?? [])
        .filter((entry) => entry.role)
        .map((entry) => [entry.to, entry.role!]),
    ),
  )
  const [logo, setLogo] = useState<LogoChange>({ kind: 'keep' })

  const name = [firstname, lastname].filter((part) => part.trim()).join(' ')
  const valid = unnamed ? descriptor.trim().length > 0 : name.trim().length > 0

  const save = async () => {
    const membership: ProjectMembership[] = projects.map((id) =>
      roles[id]?.trim() ? { to: id, role: roles[id]!.trim() } : { to: id },
    )
    const draft: Person = {
      kind: 'person',
      id: existing?.id ?? (unnamed ? `_${slugify(descriptor)}` : slugify(name)),
      firstname: firstname.trim() || undefined,
      lastname: lastname.trim() || undefined,
      email: email.trim() || undefined,
      role: role.trim() || undefined,
      placeholder: unnamed,
      descriptor: unnamed ? descriptor.trim() || undefined : undefined,
      organization: organization[0],
      projects: membership,
      relations: existing?.relations ?? [],
      created: existing?.created ?? today(),
      body: body.trim(),
    }

    if (existing) {
      await vault.update(draft)
      await applyLogo(vault, 'person', existing.id, logo)
    } else {
      const id = await vault.create(draft)
      if (id) {
        await applyLogo(vault, 'person', id, logo)
        onSelect({ kind: 'person', id })
      }
    }
    onClose()
  }

  return (
    <Sheet
      title={
        existing ? `Edit ${displayName(existing)}` : unnamed ? 'New unnamed person' : 'New person'
      }
      subtitle={
        unnamed
          ? 'For "you should meet the head of legal". No name yet — give them a descriptor, and resolve it once you know who they are.'
          : undefined
      }
      confirmDisabled={!valid}
      onCancel={onClose}
      onConfirm={() => void save()}
      wide
    >
      {unnamed ? (
        <FormField label="Descriptor">
          <TextInput
            value={descriptor}
            onChange={setDescriptor}
            placeholder="Head of Legal at MomCorp"
            autoFocus
          />
        </FormField>
      ) : (
        <div className="field-row">
          <FormField label="First name">
            <TextInput value={firstname} onChange={setFirstname} autoFocus />
          </FormField>
          <FormField label="Last name">
            <TextInput value={lastname} onChange={setLastname} />
          </FormField>
        </div>
      )}

      <div className="field-row">
        <FormField label="Email">
          <TextInput value={email} onChange={setEmail} placeholder="name@example.com" />
        </FormField>
        <FormField label="Role">
          <TextInput value={role} onChange={setRole} placeholder="Head of Engineering" />
        </FormField>
      </div>

      <LogoField
        entityKind="person"
        id={existing?.id ?? 'new'}
        hasLogo={!!existing && vault.hasLogo('person', existing.id)}
        change={logo}
        onChange={setLogo}
      />

      <EntityPicker
        label="Employer"
        hint="One only — the graph clusters people by employer, and a cluster needs exactly one key per person."
        options={allOrganizations(vault.snapshot)}
        selected={organization}
        onChange={setOrganization}
        single
      />

      <EntityPicker
        label="Projects"
        options={allProjects(vault.snapshot)}
        selected={projects}
        onChange={setProjects}
      />
      <RoleRows
        rows={projects.map((id) => ({
          id,
          label: vault.snapshot.projects[id] ? displayName(vault.snapshot.projects[id]!) : id,
        }))}
        roles={roles}
        onChange={setRoles}
      />

      <FormField label="Notes">
        <TextInput
          value={body}
          onChange={setBody}
          multiline
          placeholder="Met at the Paris conference."
        />
      </FormField>
    </Sheet>
  )
}

// -- organization ------------------------------------------------------------------------------

function OrganizationEditor({
  existing,
  onClose,
  onSelect,
}: {
  existing?: Organization
  onClose: () => void
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const [name, setName] = useState(existing?.name ?? '')
  const [domain, setDomain] = useState(existing?.domain ?? '')
  const [body, setBody] = useState(existing?.body ?? '')
  const [logo, setLogo] = useState<LogoChange>({ kind: 'keep' })

  const save = async () => {
    const draft: Organization = {
      kind: 'organization',
      id: existing?.id ?? slugify(name),
      name: name.trim(),
      domain: domain.trim() || undefined,
      created: existing?.created ?? today(),
      body: body.trim(),
    }
    if (existing) {
      await vault.update(draft)
      await applyLogo(vault, 'organization', existing.id, logo)
    } else {
      const id = await vault.create(draft)
      if (id) {
        await applyLogo(vault, 'organization', id, logo)
        onSelect({ kind: 'organization', id })
      }
    }
    onClose()
  }

  return (
    <Sheet
      title={existing ? `Edit ${displayName(existing)}` : 'New organization'}
      confirmDisabled={!name.trim()}
      onCancel={onClose}
      onConfirm={() => void save()}
    >
      <FormField label="Name">
        <TextInput value={name} onChange={setName} placeholder="Acme Corp" autoFocus />
      </FormField>
      <FormField label="Domain">
        <TextInput value={domain} onChange={setDomain} placeholder="acme.com" />
      </FormField>
      <LogoField
        entityKind="organization"
        id={existing?.id ?? 'new'}
        hasLogo={!!existing && vault.hasLogo('organization', existing.id)}
        change={logo}
        onChange={setLogo}
      />
      <FormField label="Notes">
        <TextInput value={body} onChange={setBody} multiline />
      </FormField>
    </Sheet>
  )
}

// -- project -----------------------------------------------------------------------------------

function ProjectEditor({
  existing,
  onClose,
  onSelect,
}: {
  existing?: Project
  onClose: () => void
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const roster = existing ? participantsOfProject(vault.snapshot, existing.id) : []

  const [name, setName] = useState(existing?.name ?? '')
  const [status, setStatus] = useState<ProjectStatus>(existing?.status ?? 'active')
  const [body, setBody] = useState(existing?.body ?? '')
  const [organization, setOrganization] = useState<EntityID[]>(
    existing?.organization ? [existing.organization] : [],
  )
  const [participants, setParticipants] = useState<EntityID[]>(
    roster.map((entry) => entry.person.id),
  )
  const [roles, setRoles] = useState<Record<EntityID, string>>(
    Object.fromEntries(
      roster.filter((entry) => entry.role).map((entry) => [entry.person.id, entry.role!]),
    ),
  )
  const [logo, setLogo] = useState<LogoChange>({ kind: 'keep' })

  const save = async () => {
    const draft: Project = {
      kind: 'project',
      id: existing?.id ?? slugify(name),
      name: name.trim(),
      status,
      organization: organization[0],
      created: existing?.created ?? today(),
      body: body.trim(),
    }
    const id = existing ? (await vault.update(draft), existing.id) : await vault.create(draft)
    if (!id) return onClose()

    // The roster is a diff on the *people*: membership lives on the person, never on the project.
    await vault.setParticipants(
      id,
      participants.map((personID) =>
        roles[personID]?.trim()
          ? { to: personID, role: roles[personID]!.trim() }
          : { to: personID },
      ),
    )
    await applyLogo(vault, 'project', id, logo)
    if (!existing) onSelect({ kind: 'project', id })
    onClose()
  }

  return (
    <Sheet
      title={existing ? `Edit ${displayName(existing)}` : 'New project'}
      confirmDisabled={!name.trim()}
      onCancel={onClose}
      onConfirm={() => void save()}
      wide
    >
      <FormField label="Name">
        <TextInput value={name} onChange={setName} placeholder="Ship Refit" autoFocus />
      </FormField>

      <FormField label="Status">
        <div className="toolbar-group">
          {PROJECT_STATUSES.map((option) => (
            <button
              key={option}
              type="button"
              className={`segment${status === option ? ' segment-on' : ''}`}
              onClick={() => setStatus(option)}
            >
              {option}
            </button>
          ))}
        </div>
      </FormField>

      <LogoField
        entityKind="project"
        id={existing?.id ?? 'new'}
        hasLogo={!!existing && vault.hasLogo('project', existing.id)}
        change={logo}
        onChange={setLogo}
      />

      <EntityPicker
        label="Organization"
        hint="One only — a project belongs to whoever owns the work, so it shows on exactly one board."
        options={allOrganizations(vault.snapshot)}
        selected={organization}
        onChange={setOrganization}
        single
      />

      <EntityPicker
        label="Participants"
        hint="Written to each person's own file, and only for the people whose entry actually changes."
        options={allPeople(vault.snapshot)}
        selected={participants}
        onChange={setParticipants}
      />
      <RoleRows
        rows={participants.map((id) => ({
          id,
          label: vault.snapshot.people[id] ? displayName(vault.snapshot.people[id]!) : id,
        }))}
        roles={roles}
        onChange={setRoles}
      />

      <FormField label="Description">
        <TextInput value={body} onChange={setBody} multiline />
      </FormField>
    </Sheet>
  )
}

// -- relations ---------------------------------------------------------------------------------

function RelationEditor({ person, onClose }: { person: Person; onClose: () => void }) {
  const vault = useVault()
  const [label, setLabel] = useState('')
  const [target, setTarget] = useState<EntityID[]>([])
  const [descriptor, setDescriptor] = useState('')

  const options = useMemo(
    () => allPeople(vault.snapshot).filter((candidate) => candidate.id !== person.id),
    [vault.snapshot, person.id],
  )

  const valid = label.trim().length > 0 && (target.length > 0 || descriptor.trim().length > 0)

  const save = async () => {
    let to = target[0]
    if (!to && descriptor.trim()) {
      // "You should meet the head of AA" — the person you are told about before you know their
      // name is still a node in the graph.
      to = await vault.create({
        kind: 'person',
        id: `_${slugify(descriptor)}`,
        placeholder: true,
        descriptor: descriptor.trim(),
        projects: [],
        relations: [],
        created: today(),
        body: '',
      })
    }
    if (!to) return onClose()

    const relation = { to, label: label.trim() }
    const already = person.relations.some(
      (entry) => entry.to === relation.to && entry.label === relation.label,
    )
    if (!already) await vault.update({ ...person, relations: [...person.relations, relation] })
    onClose()
  }

  return (
    <Sheet
      title={`${displayName(person)} …`}
      subtitle="Relations are one-way. This is written to this person's file only; the other end derives its own 'Referenced by' from it."
      confirmLabel="Add relation"
      confirmDisabled={!valid}
      onCancel={onClose}
      onConfirm={() => void save()}
      wide
    >
      <LabelField
        label="Label"
        value={label}
        onChange={setLabel}
        known={usedRelationLabels(vault.snapshot)}
        placeholder="manager of"
      />

      <EntityPicker
        label="Points at"
        options={options}
        selected={target}
        onChange={setTarget}
        single
      />

      {!target.length && (
        <FormField
          label="Or someone you cannot name yet"
          hint="Creates an unnamed person you can resolve later, without losing the relation."
        >
          <TextInput
            value={descriptor}
            onChange={setDescriptor}
            placeholder="The head of legal at MomCorp"
          />
        </FormField>
      )}
    </Sheet>
  )
}

function ResolveEditor({
  person,
  onClose,
  onSelect,
}: {
  person: Person
  onClose: () => void
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const [firstname, setFirstname] = useState('')
  const [lastname, setLastname] = useState('')
  const [email, setEmail] = useState('')

  return (
    <Sheet
      title="Give them a name"
      subtitle={`${person.descriptor ?? person.id} becomes a real person: the file is renamed and every link that pointed at the placeholder follows it.`}
      confirmLabel="Resolve"
      confirmDisabled={!firstname.trim() && !lastname.trim()}
      onCancel={onClose}
      onConfirm={() => {
        void (async () => {
          const id = await vault.resolvePlaceholder(person.id, {
            firstname: firstname.trim() || undefined,
            lastname: lastname.trim() || undefined,
            email: email.trim() || undefined,
          })
          if (id) onSelect({ kind: 'person', id })
          onClose()
        })()
      }}
    >
      <div className="field-row">
        <FormField label="First name">
          <TextInput value={firstname} onChange={setFirstname} autoFocus />
        </FormField>
        <FormField label="Last name">
          <TextInput value={lastname} onChange={setLastname} />
        </FormField>
      </div>
      <FormField label="Email">
        <TextInput value={email} onChange={setEmail} />
      </FormField>
    </Sheet>
  )
}

// -- deletion ----------------------------------------------------------------------------------

/** Spells out what else changes, because deleting scrubs references rather than leaving them
 * dangling — and that is not obvious from a name and a button. */
export function DeleteConfirmation({
  target,
  onClose,
  onDeleted,
}: {
  target: EntityRef
  onClose: () => void
  onDeleted: () => void
}) {
  const vault = useVault()
  const entity =
    target.kind === 'person'
      ? vault.snapshot.people[target.id]
      : target.kind === 'organization'
        ? vault.snapshot.organizations[target.id]
        : vault.snapshot.projects[target.id]
  if (!entity) return null

  const consequences: string[] = []
  if (target.kind === 'person') {
    const referenced = vault.backlinks[target.id]?.length ?? 0
    if (referenced) consequences.push(`${plural(referenced, 'relation')} pointing at them`)
    const memberships = entity.kind === 'person' ? entity.projects.length : 0
    if (memberships) consequences.push(`${plural(memberships, 'project membership')}`)
  }
  if (target.kind === 'organization') {
    const people = membersOfOrganization(vault.snapshot, target.id).length
    const projects = projectsInOrganization(vault.snapshot, target.id).length
    if (people) consequences.push(`the employer of ${plural(people, 'person', 'people')}`)
    if (projects) consequences.push(`the owner of ${plural(projects, 'project')}`)
  }
  if (target.kind === 'project') {
    const roster = participantsOfProject(vault.snapshot, target.id).length
    if (roster) consequences.push(`${plural(roster, 'person', 'people')} staffed on it`)
  }
  if (vault.hasLogo(target.kind, target.id)) consequences.push('its logo')

  return (
    <Sheet
      title={`Delete ${displayName(entity)}?`}
      subtitle={`${KIND_LABEL[target.kind]} · ${target.id}.md`}
      confirmLabel="Delete"
      danger
      onCancel={onClose}
      onConfirm={() => {
        void (async () => {
          await vault.remove(target.kind, target.id)
          onDeleted()
        })()
      }}
    >
      <p>
        The file is removed from disk. There is no soft delete and no backup copy — the vault is the
        only place this lives.
      </p>
      {consequences.length > 0 && (
        <>
          <p>Also scrubbed, so nothing is left pointing at a file that is gone:</p>
          <ul className="consequences">
            {consequences.map((line) => (
              <li key={line}>
                <Icon name="warning" size={12} /> {line}
              </li>
            ))}
          </ul>
        </>
      )}
    </Sheet>
  )
}

function plural(n: number, singular: string, many = `${singular}s`): string {
  return `${n} ${n === 1 ? singular : many}`
}
