// The reusable primitives. One file rather than fourteen: every one of them is a handful of lines,
// and the SwiftUI original only split them up because each carried a cursor-tracking workaround
// the browser makes unnecessary.

import type { CSSProperties, ReactNode } from 'react'
import { useState } from 'react'
import type { AnyEntity, EntityID, EntityKind } from '../../shared/types.ts'
import { displayName } from '../../shared/types.ts'
import './components.css'

// -- icons ------------------------------------------------------------------------------------

const PATHS: Record<string, string> = {
  person: 'M12 12a5 5 0 100-10 5 5 0 000 10zm0 2c-5 0-9 2.5-9 5.5V21h18v-1.5c0-3-4-5.5-9-5.5z',
  organization:
    'M3 21V7l7-4v4l7-3v17h-4v-5h-3v5H3zm3-3h2v-2H6v2zm0-4h2v-2H6v2zm0-4h2V8H6v2zm7 8h2v-2h-2v2zm0-4h2v-2h-2v2zm0-4h2V8h-2v2z',
  project: 'M3 6a2 2 0 012-2h4l2 2h8a2 2 0 012 2v10a2 2 0 01-2 2H5a2 2 0 01-2-2V6z',
  chevron: 'M9 6l6 6-6 6',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  pencil: 'M4 20h4L20 8l-4-4L4 16v4z',
  arrow: 'M5 12h14M13 6l6 6-6 6',
  search: 'M11 4a7 7 0 105.2 11.7L21 20.5 20.5 21l-4.8-4.8A7 7 0 0011 4z',
  warning: 'M12 3l9 17H3l9-17zm0 6v5m0 3v.01',
  close: 'M6 6l12 12M18 6L6 18',
  reload: 'M20 12a8 8 0 11-2.3-5.6M20 4v5h-5',
  filter: 'M4 5h16l-6 7v6l-4 2v-8L4 5z',
}

export const KIND_ICON: Record<EntityKind, string> = {
  person: 'person',
  organization: 'organization',
  project: 'project',
}

export function Icon({ name, size = 14 }: { name: string; size?: number }) {
  const filled = name === 'person' || name === 'organization' || name === 'project'
  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      aria-hidden="true"
      fill={filled ? 'currentColor' : 'none'}
      stroke={filled ? 'none' : 'currentColor'}
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d={PATHS[name] ?? ''} />
    </svg>
  )
}

// -- avatars and links ------------------------------------------------------------------------

export interface AvatarProps {
  kind: EntityKind
  id: EntityID
  size?: number
  hasLogo?: boolean
  isPlaceholder?: boolean
  /** Overrides the kind hue — the graphs colour a person by employer instead. */
  tint?: string
  fill?: 'wash' | 'solid'
  ring?: string
  /** Bumped after a logo is written, to get past the browser's cache for an unchanged URL. */
  version?: number
}

/**
 * The one thing that stands for an entity, everywhere: a stored logo if there is one, a hollow
 * outline for a placeholder nobody has named yet, else the kind's glyph on a disc in its hue.
 */
export function EntityAvatar({
  kind,
  id,
  size = 20,
  hasLogo = false,
  isPlaceholder = false,
  tint,
  fill = 'wash',
  ring,
  version = 0,
}: AvatarProps) {
  const color = tint ?? `var(--${kind})`
  const style: CSSProperties = {
    width: size,
    height: size,
    borderColor: ring ?? 'transparent',
    borderWidth: ring ? 2 : 0,
  }

  if (hasLogo) {
    return (
      <img
        className="avatar avatar-logo"
        style={style}
        src={`/assets/${directoryOf(kind)}/${encodeURIComponent(id)}.png${version ? `?v=${version}` : ''}`}
        alt=""
      />
    )
  }

  if (isPlaceholder) {
    return (
      <span
        className="avatar avatar-placeholder"
        style={{ ...style, borderColor: 'var(--placeholder)', borderWidth: 2 }}
      />
    )
  }

  return (
    <span
      className={`avatar avatar-${fill}`}
      style={{
        ...style,
        background: fill === 'solid' ? color : 'transparent',
        color: fill === 'solid' ? 'var(--bg-primary)' : color,
        boxShadow: fill === 'wash' ? `inset 0 0 0 ${Math.max(1, size / 14)}px ${color}` : undefined,
      }}
    >
      <Icon name={KIND_ICON[kind]} size={Math.round(size * 0.5)} />
    </span>
  )
}

function directoryOf(kind: EntityKind): string {
  return kind === 'person' ? 'people' : `${kind}s`
}

/** Avatar plus name, underlined on hover. What a link to an entity looks like. */
export function EntityLink({
  entity,
  size = 20,
  hasLogo,
  onClick,
  suffix,
}: {
  entity: AnyEntity
  size?: number
  hasLogo?: boolean
  onClick?: () => void
  suffix?: ReactNode
}) {
  return (
    <button className="entity-link" onClick={onClick} type="button">
      <EntityAvatar
        kind={entity.kind}
        id={entity.id}
        size={size}
        hasLogo={hasLogo}
        isPlaceholder={entity.kind === 'person' && entity.placeholder}
      />
      <span className="entity-link-name">{displayName(entity)}</span>
      {suffix}
    </button>
  )
}

/** For things that are not entities: relation labels, and removable tokens in the editors. */
export function Pill({
  children,
  color = 'var(--text-muted)',
  onClick,
  onRemove,
  title,
}: {
  children: ReactNode
  color?: string
  onClick?: () => void
  onRemove?: () => void
  title?: string
}) {
  const interactive = Boolean(onClick)
  return (
    <span
      className={`pill${interactive ? ' pill-interactive' : ''}`}
      style={{ color, borderColor: color }}
      title={title}
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onClick={onClick}
      onKeyDown={(event) => {
        if (onClick && (event.key === 'Enter' || event.key === ' ')) onClick()
      }}
    >
      {children}
      {onRemove && (
        <button
          className="pill-remove"
          type="button"
          aria-label="Remove"
          onClick={(event) => {
            event.stopPropagation()
            onRemove()
          }}
        >
          <Icon name="close" size={10} />
        </button>
      )}
    </span>
  )
}

// -- structure --------------------------------------------------------------------------------

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <div className={`card ${className}`}>{children}</div>
}

export function SectionHeader({
  title,
  trailing,
  actions,
}: {
  title: string
  trailing?: ReactNode
  actions?: ReactNode
}) {
  return (
    <div className="section-header">
      <span className="section-title">{title}</span>
      {trailing !== undefined && <span className="section-count">{trailing}</span>}
      <span className="section-spacer" />
      {actions}
    </div>
  )
}

export function DisclosureChevron({ open }: { open: boolean }) {
  return (
    <span className={`chevron${open ? ' chevron-open' : ''}`}>
      <Icon name="chevron" size={10} />
    </span>
  )
}

export interface MetadataItem {
  label: string
  value: ReactNode
}

export function MetadataList({ items }: { items: MetadataItem[] }) {
  const shown = items.filter((item) => item.value !== undefined && item.value !== '')
  if (!shown.length) return null
  return (
    <dl className="metadata">
      {shown.map((item) => (
        <div className="metadata-row" key={item.label}>
          <dt>{item.label}</dt>
          <dd>{item.value}</dd>
        </div>
      ))}
    </dl>
  )
}

export function EmptyState({
  icon = 'person',
  title,
  message,
  action,
}: {
  icon?: string
  title: string
  message?: string
  action?: ReactNode
}) {
  return (
    <div className="empty-state">
      <span className="empty-icon">
        <Icon name={icon} size={28} />
      </span>
      <p className="empty-title">{title}</p>
      {message && <p className="empty-message">{message}</p>}
      {action}
    </div>
  )
}

// -- controls ---------------------------------------------------------------------------------

export function PrimaryButton({
  children,
  onClick,
  disabled,
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  disabled?: boolean
  type?: 'button' | 'submit'
}) {
  return (
    <button className="button button-primary" onClick={onClick} disabled={disabled} type={type}>
      {children}
    </button>
  )
}

export function SecondaryButton({
  children,
  onClick,
  disabled,
  danger,
}: {
  children: ReactNode
  onClick?: () => void
  disabled?: boolean
  danger?: boolean
}) {
  return (
    <button
      className={`button button-secondary${danger ? ' button-danger' : ''}`}
      onClick={onClick}
      disabled={disabled}
      type="button"
    >
      {children}
    </button>
  )
}

export function IconButton({
  icon,
  label,
  onClick,
  size = 14,
  danger,
}: {
  icon: string
  label: string
  onClick?: () => void
  size?: number
  danger?: boolean
}) {
  return (
    <button
      className={`icon-button${danger ? ' icon-button-danger' : ''}`}
      onClick={onClick}
      aria-label={label}
      title={label}
      type="button"
    >
      <Icon name={icon} size={size} />
    </button>
  )
}

export function SearchField({
  value,
  onChange,
  placeholder = 'Search…',
  autoFocus,
  onKeyDown,
}: {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  autoFocus?: boolean
  onKeyDown?: (event: React.KeyboardEvent<HTMLInputElement>) => void
}) {
  return (
    <label className="search-field">
      <Icon name="search" size={13} />
      <input
        value={value}
        placeholder={placeholder}
        autoFocus={autoFocus}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={onKeyDown}
      />
      {value && (
        <button
          className="search-clear"
          type="button"
          aria-label="Clear"
          onClick={() => onChange('')}
        >
          <Icon name="close" size={11} />
        </button>
      )}
    </label>
  )
}

export function FormField({
  label,
  children,
  hint,
}: {
  label: string
  children: ReactNode
  hint?: string
}) {
  return (
    <div className="form-field">
      <span className="form-label">{label}</span>
      {children}
      {hint && <span className="form-hint">{hint}</span>}
    </div>
  )
}

export function TextInput({
  value,
  onChange,
  placeholder,
  multiline,
  autoFocus,
}: {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  multiline?: boolean
  autoFocus?: boolean
}) {
  // The box is bigger than the input: padding and border are drawn around it, so a click near the
  // edge would otherwise miss and the field would read as dead. The label element claims all of it.
  return multiline ? (
    <textarea
      className="text-input text-area"
      value={value}
      placeholder={placeholder}
      rows={4}
      onChange={(event) => onChange(event.target.value)}
    />
  ) : (
    <input
      className="text-input"
      value={value}
      placeholder={placeholder}
      autoFocus={autoFocus}
      onChange={(event) => onChange(event.target.value)}
    />
  )
}

export function ToggleField({
  label,
  checked,
  onChange,
}: {
  label: string
  checked: boolean
  onChange: (checked: boolean) => void
}) {
  return (
    <label className="toggle-field">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span>{label}</span>
    </label>
  )
}

export function SidebarRow({
  entity,
  hasLogo,
  selected,
  onClick,
  onEdit,
  onDelete,
}: {
  entity: AnyEntity
  hasLogo?: boolean
  selected: boolean
  onClick: () => void
  onEdit: () => void
  onDelete: () => void
}) {
  const [hovered, setHovered] = useState(false)
  return (
    <div
      className={`sidebar-row${selected ? ' sidebar-row-selected' : ''}`}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <button className="sidebar-row-main" onClick={onClick} type="button">
        <EntityAvatar
          kind={entity.kind}
          id={entity.id}
          size={20}
          hasLogo={hasLogo}
          isPlaceholder={entity.kind === 'person' && entity.placeholder}
        />
        <span className="sidebar-row-name">{displayName(entity)}</span>
      </button>
      {hovered && (
        <span className="sidebar-row-actions">
          <IconButton icon="pencil" label="Edit" onClick={onEdit} size={12} />
          <IconButton icon="close" label="Delete" onClick={onDelete} size={12} danger />
        </span>
      )}
    </div>
  )
}

/** A modal sheet. Escape closes it; an abandoned sheet writes nothing. */
export function Sheet({
  title,
  subtitle,
  children,
  confirmLabel = 'Save',
  onConfirm,
  onCancel,
  confirmDisabled,
  danger,
  wide,
}: {
  title: string
  subtitle?: string
  children: ReactNode
  confirmLabel?: string
  onConfirm: () => void
  onCancel: () => void
  confirmDisabled?: boolean
  danger?: boolean
  wide?: boolean
}) {
  return (
    <div
      className="sheet-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onCancel()
      }}
    >
      <div className={`sheet${wide ? ' sheet-wide' : ''}`} role="dialog" aria-label={title}>
        <header className="sheet-header">
          <h2>{title}</h2>
          {subtitle && <p>{subtitle}</p>}
        </header>
        <div className="sheet-body">{children}</div>
        <footer className="sheet-footer">
          <SecondaryButton onClick={onCancel}>Cancel</SecondaryButton>
          {danger ? (
            <button
              className="button button-primary button-danger"
              onClick={onConfirm}
              type="button"
            >
              {confirmLabel}
            </button>
          ) : (
            <PrimaryButton onClick={onConfirm} disabled={confirmDisabled}>
              {confirmLabel}
            </PrimaryButton>
          )}
        </footer>
      </div>
    </div>
  )
}
