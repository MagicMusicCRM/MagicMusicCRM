import { useMemo, useState } from 'react'
import {
  ArrowsIn,
  ArrowsOut,
  CaretLeft,
  CaretRight,
  CheckCircle,
  ListMagnifyingGlass,
  MagnifyingGlass,
  Monitor,
  SidebarSimple,
  X,
} from '@phosphor-icons/react'
import { roleLabels, type PrototypeRole, type ScreenDefinition, type ScreenState } from './types'

type ScreenCatalogProps = {
  entries: ScreenDefinition[]
  activeId: string
  role: PrototypeRole
  state: ScreenState
  compact: boolean
  open: boolean
  coverage: { total: number; unique: number; valid: boolean }
  onOpenChange: (open: boolean) => void
  onNavigate: (id: string) => void
  onRoleChange: (role: PrototypeRole) => void
  onStateChange: (state: ScreenState) => void
  onCompactChange: (compact: boolean) => void
}

const roles = Object.keys(roleLabels) as PrototypeRole[]

export function ScreenCatalog({ entries, activeId, role, state, compact, open, coverage, onOpenChange, onNavigate, onRoleChange, onStateChange, onCompactChange }: ScreenCatalogProps) {
  const [query, setQuery] = useState('')
  const [group, setGroup] = useState('Все разделы')
  const visible = useMemo(() => entries.filter((entry) => {
    const matchesRole = entry.roles.includes(role)
    const matchesGroup = group === 'Все разделы' || entry.group === group
    const needle = query.trim().toLocaleLowerCase('ru')
    const matchesQuery = !needle || `${entry.title} ${entry.description} ${entry.id}`.toLocaleLowerCase('ru').includes(needle)
    return matchesRole && matchesGroup && matchesQuery
  }), [entries, group, query, role])
  const groups = useMemo(() => ['Все разделы', ...new Set(entries.filter((entry) => entry.roles.includes(role)).map((entry) => entry.group))], [entries, role])
  const currentIndex = entries.findIndex((entry) => entry.id === activeId)
  const previous = entries[(currentIndex - 1 + entries.length) % entries.length]
  const next = entries[(currentIndex + 1) % entries.length]

  if (!open) {
    return <button type="button" className="catalog-fab" onClick={() => onOpenChange(true)}><ListMagnifyingGlass size={20} /><span>{coverage.total} экранов</span><i className={coverage.valid ? 'ok' : ''} /></button>
  }

  return <aside className="screen-catalog" aria-label="Каталог экранов">
    <header>
      <span><b>Каталог экранов</b><small>Визуальный прототип</small></span>
      <button type="button" title="Закрыть каталог" onClick={() => onOpenChange(false)}><X size={20} /></button>
    </header>
    <div className="catalog-coverage"><CheckCircle size={18} weight="fill" /><span><b>{coverage.unique} из {coverage.total}</b><small>{coverage.valid ? 'Все переходы связаны' : 'Найдены несвязанные переходы'}</small></span></div>
    <div className="catalog-controls">
      <label><span>Роль</span><select value={role} onChange={(event) => onRoleChange(event.target.value as PrototypeRole)}>{roles.map((item) => <option value={item} key={item}>{roleLabels[item]}</option>)}</select></label>
      <label><span>Раздел</span><select value={group} onChange={(event) => setGroup(event.target.value)}>{groups.map((item) => <option value={item} key={item}>{item}</option>)}</select></label>
      <label className="catalog-search"><span>Поиск</span><div><MagnifyingGlass size={17} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Экран или действие" /></div></label>
    </div>
    <div className="catalog-view-controls">
      <button type="button" className={!compact ? 'active' : ''} onClick={() => onCompactChange(false)}><Monitor size={17} />ПК</button>
      <button type="button" className={compact ? 'active' : ''} onClick={() => onCompactChange(true)}><SidebarSimple size={17} />Узкий</button>
      <button type="button" className={state === 'content' ? 'active' : ''} onClick={() => onStateChange('content')}>Данные</button>
      <button type="button" className={state === 'empty' ? 'active' : ''} onClick={() => onStateChange('empty')}>Пусто</button>
      <button type="button" className={state === 'error' ? 'active' : ''} onClick={() => onStateChange('error')}>Ошибка</button>
    </div>
    <nav className="catalog-list">
      {visible.length ? visible.map((entry) => <button type="button" key={entry.id} className={entry.id === activeId ? 'active' : ''} onClick={() => onNavigate(entry.id)}><span><b>{entry.title}</b><small>{entry.group}{entry.subgroup ? ` · ${entry.subgroup}` : ''}</small></span><i>{entry.kind === 'dialog' ? 'Окно' : entry.kind === 'sheet' ? 'Панель' : 'Экран'}</i></button>) : <div className="catalog-no-results"><MagnifyingGlass size={24} /><b>Ничего не найдено</b><small>Измените роль, раздел или запрос.</small></div>}
    </nav>
    <footer>
      <button type="button" onClick={() => onNavigate(previous.id)} title={previous.title}><CaretLeft size={18} />Предыдущий</button>
      <span>{currentIndex + 1} / {entries.length}</span>
      <button type="button" onClick={() => onNavigate(next.id)} title={next.title}>Следующий<CaretRight size={18} /></button>
    </footer>
  </aside>
}
