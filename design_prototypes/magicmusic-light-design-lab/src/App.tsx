import { useEffect, useMemo, useState } from 'react'
import type { CSSProperties, ReactNode } from 'react'
import {
  AddressBook,
  Archive,
  ArrowClockwise,
  Bell,
  Buildings,
  CalendarBlank,
  CaretLeft,
  CaretRight,
  ChartBar,
  ChatsCircle,
  Check,
  CheckCircle,
  CheckSquare,
  ChalkboardTeacher,
  Clock,
  CreditCard,
  DotsThree,
  DownloadSimple,
  FileText,
  Funnel,
  GearSix,
  GraduationCap,
  House,
  Info,
  ListChecks,
  LockKey,
  MagnifyingGlass,
  MapPin,
  MusicNotes,
  PaperPlaneTilt,
  PencilSimple,
  Plus,
  Receipt,
  ShieldCheck,
  SlidersHorizontal,
  Sparkle,
  TrendUp,
  UserCircle,
  UserPlus,
  UsersThree,
  Warning,
  WarningCircle,
  X,
} from '@phosphor-icons/react'
import appLogo from '../../../assets/icon.png'
import { ScreenCatalog } from './catalog/ScreenCatalog'
import { VisualSurface } from './catalog/VisualSurface'
import { screenById, screenManifest, validateScreenManifest } from './catalog/screenManifest'
import type { PrototypeRole, ScreenState } from './catalog/types'

type Role = PrototypeRole
type RouteKey =
  | 'chat'
  | 'overview'
  | 'schedule'
  | 'clients'
  | 'tasks'
  | 'analytics'
  | 'settings'
  | 'teacherStudents'
  | 'clientLessons'
  | 'clientSubscription'
  | 'clientProfile'
  | 'clientCard'

type NavItem = {
  key: RouteKey
  label: string
  icon: typeof House
}

type ModalName =
  | 'lesson'
  | 'recurring'
  | 'task'
  | 'taskNew'
  | 'lead'
  | 'student'
  | 'version'
  | null

const routeLabels: Record<RouteKey, string> = {
  chat: 'Чат',
  overview: 'Обзор',
  schedule: 'Расписание',
  clients: 'Клиенты',
  tasks: 'Задачи',
  analytics: 'Аналитика',
  settings: 'Настройки',
  teacherStudents: 'Ученики',
  clientLessons: 'Занятия',
  clientSubscription: 'Абонемент',
  clientProfile: 'Профиль',
  clientCard: 'Лид · София Крылова',
}

const navByRole: Record<Role, NavItem[]> = {
  director: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'overview', label: 'Обзор', icon: House },
    { key: 'schedule', label: 'Расписание', icon: CalendarBlank },
    { key: 'clients', label: 'Клиенты', icon: UsersThree },
    { key: 'tasks', label: 'Задачи', icon: CheckSquare },
    { key: 'analytics', label: 'Аналитика', icon: ChartBar },
    { key: 'settings', label: 'Настройки', icon: GearSix },
  ],
  manager: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'overview', label: 'Обзор', icon: House },
    { key: 'schedule', label: 'Расписание', icon: CalendarBlank },
    { key: 'clients', label: 'Клиенты', icon: UsersThree },
    { key: 'tasks', label: 'Задачи', icon: CheckSquare },
    { key: 'analytics', label: 'Аналитика', icon: ChartBar },
    { key: 'settings', label: 'Настройки', icon: GearSix },
  ],
  admin: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'schedule', label: 'Расписание', icon: CalendarBlank },
    { key: 'clients', label: 'Клиенты', icon: UsersThree },
    { key: 'tasks', label: 'Задачи', icon: CheckSquare },
  ],
  teacher: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'schedule', label: 'Расписание', icon: CalendarBlank },
    { key: 'teacherStudents', label: 'Ученики', icon: GraduationCap },
  ],
  client: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'clientLessons', label: 'Занятия', icon: CalendarBlank },
    { key: 'clientSubscription', label: 'Абонемент', icon: CreditCard },
    { key: 'clientProfile', label: 'Профиль', icon: UserCircle },
  ],
  system_admin: [
    { key: 'chat', label: 'Чат', icon: ChatsCircle },
    { key: 'overview', label: 'Обзор', icon: House },
    { key: 'schedule', label: 'Расписание', icon: CalendarBlank },
    { key: 'clients', label: 'Клиенты', icon: UsersThree },
    { key: 'tasks', label: 'Задачи', icon: CheckSquare },
    { key: 'analytics', label: 'Аналитика', icon: ChartBar },
    { key: 'settings', label: 'Настройки', icon: GearSix },
  ],
}

const clients = [
  { name: 'Алиса Воронцова', phone: '+7 999 418-22-17', course: 'Фортепиано', teacher: 'Анна Лебедева', state: 'Активен', balance: '4 занятия' },
  { name: 'Матвей Соколов', phone: '+7 921 744-30-08', course: 'Гитара', teacher: 'Илья Морозов', state: 'Нужна оплата', balance: '0 занятий' },
  { name: 'София Крылова', phone: '+7 915 208-44-63', course: 'Вокал', teacher: 'Мария Орлова', state: 'Пробное', balance: '1 занятие' },
  { name: 'Лев Фролов', phone: '+7 903 551-72-19', course: 'Барабаны', teacher: 'Денис Волков', state: 'Активен', balance: '7 занятий' },
  { name: 'Вера Мельникова', phone: '+7 926 155-82-11', course: 'Скрипка', teacher: 'Анна Лебедева', state: 'Приостановлен', balance: '2 занятия' },
]

const lessons = [
  { id: 1, day: 0, start: 9, span: 2, title: 'Алиса Воронцова', sub: 'Фортепиано · Анна', room: 'Аудитория 2', tone: 'gold' },
  { id: 2, day: 1, start: 11, span: 2, title: 'Группа «Ритм»', sub: 'Сольфеджио · Мария', room: 'Аудитория 4', tone: 'blue' },
  { id: 3, day: 2, start: 10, span: 1.5, title: 'Матвей Соколов', sub: 'Гитара · Илья', room: 'Аудитория 1', tone: 'green' },
  { id: 4, day: 2, start: 10.5, span: 1.5, title: 'София Крылова', sub: 'Вокал · Мария', room: 'Аудитория 1', tone: 'danger', conflict: true },
  { id: 5, day: 3, start: 14, span: 2, title: 'Лев Фролов', sub: 'Барабаны · Денис', room: 'Студия', tone: 'purple' },
  { id: 6, day: 4, start: 16, span: 1.5, title: 'Вера Мельникова', sub: 'Скрипка · Анна', room: 'Аудитория 3', tone: 'gold' },
  { id: 7, day: 5, start: 12, span: 2, title: 'Пробное занятие', sub: 'Вокал · Мария', room: 'Аудитория 2', tone: 'blue' },
]

const taskRows = [
  { title: 'Позвонить по заявке с сайта', owner: 'Елена Смирнова', due: 'Сегодня, 12:30', priority: 'Высокий', state: 'В работе' },
  { title: 'Согласовать перенос занятия', owner: 'Анна Лебедева', due: 'Сегодня, 15:00', priority: 'Обычный', state: 'Новая' },
  { title: 'Проверить задолженности за август', owner: 'Олег Романов', due: 'Завтра, 10:00', priority: 'Высокий', state: 'Новая' },
  { title: 'Подготовить аудиторию к концерту', owner: 'Денис Волков', due: '18 августа', priority: 'Обычный', state: 'В работе' },
  { title: 'Обновить график преподавателей', owner: 'Елена Смирнова', due: '20 августа', priority: 'Низкий', state: 'Готово' },
]

function cn(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(' ')
}

const visualButtonTargets: Record<string, string> = {
  'Найти занятие': 'schedule.search',
  'Часовой пояс': 'schedule.timezone',
  'Уведомления': 'system.notifications',
  'Расширенные фильтры': 'tasks.list',
  'Сегодня': 'tasks.calendar.day',
  '01.03.2026 - 15.08.2026': 'analytics.export',
  'Новый пользователь': 'settings.user.create',
  'Новый абонемент': 'settings.package.create',
  'Выдать абонемент': 'clients.subscription.issue',
  'Добавить оплату': 'clients.payment.create',
  'Изменить и пересчитать': 'clients.subscription.replace',
  'Прикрепить к ученику': 'clients.link-student',
  'Добавить контактное лицо': 'clients.contact.create',
  'Пригласить': 'clients.access.invite',
  'Связать': 'clients.link-student',
  'Добавить получателя': 'settings.users',
  'Новый филиал': 'settings.branch.create',
  'Новая группа': 'settings.group.create',
  'Новый сотрудник': 'settings.staff.create',
  'Новый преподаватель': 'settings.teacher.create',
  'Проверить и опубликовать': 'settings.crm.publish',
  'Настроить воронки лидов и учеников': 'settings.crm.pipeline',
  'Добавить поле': 'settings.crm.fields',
  'Добавить набор': 'settings.crm.lists',
  'Открыть': 'settings.user.detail',
  'Новый чат': 'chat.create.menu',
  'Создать чат или канал': 'chat.create.menu',
  'Меню': 'chat.info',
  'Прикрепить': 'chat.file',
  'Добавить другой набор дней': 'schedule.recurring.multiple',
  'Изменить строку 1': 'schedule.recurring.create',
  'Открыть в расписании': 'schedule.week',
}

function openVisualScreen(screenId: string) {
  const catalog = (window as unknown as { __screenCatalog?: { navigate: (id: string) => void } }).__screenCatalog
  catalog?.navigate(screenId)
}

function Button({
  children,
  variant = 'primary',
  size = 'md',
  icon,
  disabled,
  onClick,
  className,
  title,
  target,
}: {
  children?: ReactNode
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger' | 'quiet'
  size?: 'sm' | 'md' | 'lg' | 'icon'
  icon?: ReactNode
  disabled?: boolean
  onClick?: () => void
  className?: string
  title?: string
  target?: string
}) {
  const label = typeof children === 'string' ? children : title
  const visualTarget = target ?? (label ? visualButtonTargets[label] : undefined)
  return (
    <button
      type="button"
      className={cn('btn', `btn-${variant}`, `btn-${size}`, className)}
      disabled={disabled}
      onClick={onClick ?? (visualTarget ? () => openVisualScreen(visualTarget) : undefined)}
      data-screen-target={visualTarget}
      title={title}
    >
      {icon}
      {children}
    </button>
  )
}

function Badge({ children, tone = 'neutral' }: { children: ReactNode; tone?: string }) {
  return <span className={cn('badge', `badge-${tone}`)}>{children}</span>
}

function Field({ label, children, hint, error }: { label: string; children: ReactNode; hint?: string; error?: string }) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {error ? <span className="field-error">{error}</span> : hint ? <span className="field-hint">{hint}</span> : null}
    </label>
  )
}

function Segmented({ items, value, onChange }: { items: string[]; value: string; onChange: (value: string) => void }) {
  return (
    <div className="segmented">
      {items.map((item) => (
        <button type="button" key={item} className={item === value ? 'selected' : ''} onClick={() => onChange(item)}>
          {item}
        </button>
      ))}
    </div>
  )
}

function PageHeader({ eyebrow, title, description, actions }: { eyebrow?: string; title: string; description?: string; actions?: ReactNode }) {
  return (
    <header className="page-header">
      <div>
        {eyebrow && <div className="eyebrow">{eyebrow}</div>}
        <h1>{title}</h1>
        {description && <p>{description}</p>}
      </div>
      {actions && <div className="page-actions">{actions}</div>}
    </header>
  )
}

const routeScreen: Record<RouteKey, string> = {
  chat: 'chat.inbox',
  overview: 'overview.main',
  schedule: 'schedule.week',
  clients: 'clients.leads',
  tasks: 'tasks.list',
  analytics: 'analytics.overview',
  settings: 'settings.root',
  teacherStudents: 'teacher.students',
  clientLessons: 'client.lessons.upcoming',
  clientSubscription: 'client.subscription',
  clientProfile: 'client.profile',
  clientCard: 'clients.lead.card',
}

const roleValues: Role[] = ['client', 'teacher', 'admin', 'manager', 'director', 'system_admin']
const routeValues = Object.keys(routeScreen) as RouteKey[]

function parentRouteForScreen(screenId: string): RouteKey {
  if (screenId.startsWith('schedule.')) return 'schedule'
  if (screenId.startsWith('clients.')) return screenId.endsWith('.card') ? 'clientCard' : 'clients'
  if (screenId.startsWith('tasks.')) return 'tasks'
  if (screenId.startsWith('analytics.') || screenId.startsWith('finance.')) return 'analytics'
  if (screenId.startsWith('settings.')) return 'settings'
  if (screenId.startsWith('chat.')) return 'chat'
  if (screenId.startsWith('teacher.students') || screenId.startsWith('teacher.student')) return 'teacherStudents'
  if (screenId.startsWith('teacher.')) return 'schedule'
  if (screenId.startsWith('client.subscription') || screenId.startsWith('client.payment')) return 'clientSubscription'
  if (screenId.startsWith('client.profile') || screenId.startsWith('profile.')) return 'clientProfile'
  if (screenId.startsWith('client.')) return 'clientLessons'
  return 'overview'
}

function App() {
  const initialQuery = useMemo(() => new URLSearchParams(window.location.search), [])
  const requestedRole = initialQuery.get('role') as Role | null
  const initialRole: Role = requestedRole && roleValues.includes(requestedRole) ? requestedRole : 'director'
  const requestedScreen = initialQuery.get('screen')
  const initialScreenId = requestedScreen && screenById.has(requestedScreen) ? requestedScreen : 'overview.main'
  const initialEntry = screenById.get(initialScreenId)!
  const requestedState = initialQuery.get('state') as ScreenState | null
  const initialState: ScreenState = requestedState && ['content', 'empty', 'loading', 'error', 'forbidden'].includes(requestedState) ? requestedState : 'content'
  const initialRoute = routeValues.includes(initialEntry.nativeRoute as RouteKey) ? initialEntry.nativeRoute as RouteKey : parentRouteForScreen(initialScreenId)
  const [role, setRole] = useState<Role>(initialRole)
  const [route, setRoute] = useState<RouteKey>(initialRoute)
  const [tabs, setTabs] = useState<RouteKey[]>(['overview'])
  const [modal, setModal] = useState<ModalName>(null)
  const [drawer, setDrawer] = useState<string | null>(null)
  const [clientKind, setClientKind] = useState<'lead' | 'student'>('lead')
  const [toast, setToast] = useState<string | null>(null)
  const [activeScreenId, setActiveScreenId] = useState(initialScreenId)
  const [screenState, setScreenState] = useState<ScreenState>(initialState)
  const [catalogOpen, setCatalogOpen] = useState(initialQuery.get('catalog') === 'open')
  const [compact, setCompact] = useState(initialQuery.get('viewport') === 'compact')
  const [screenHistory, setScreenHistory] = useState<string[]>([initialScreenId])
  const activeEntry = screenById.get(activeScreenId) ?? screenManifest[0]
  const coverage = useMemo(() => validateScreenManifest(), [])

  const writeUrl = (screenId: string, nextRole = role, nextState = screenState, nextCompact = compact) => {
    const query = new URLSearchParams()
    query.set('role', nextRole)
    query.set('screen', screenId)
    if (nextState !== 'content') query.set('state', nextState)
    if (nextCompact) query.set('viewport', 'compact')
    window.history.replaceState({}, '', `${window.location.pathname}?${query.toString()}`)
  }

  const openScreen = (screenId: string, options: { keepCatalog?: boolean; record?: boolean } = {}) => {
    const nextEntry = screenById.get(screenId)
    if (!nextEntry) return
    setActiveScreenId(screenId)
    setScreenState('content')
    setModal(null)
    setDrawer(null)
    const nextRoute = nextEntry.nativeRoute && routeValues.includes(nextEntry.nativeRoute as RouteKey)
      ? nextEntry.nativeRoute as RouteKey
      : parentRouteForScreen(screenId)
    setRoute(nextRoute)
    setTabs((current) => (current.includes(nextRoute) ? current : [...current, nextRoute].slice(-6)))
    if (screenId.includes('student')) setClientKind('student')
    if (screenId.includes('lead')) setClientKind('lead')
    if (options.record !== false) setScreenHistory((current) => current.at(-1) === screenId ? current : [...current, screenId].slice(-40))
    if (!options.keepCatalog) setCatalogOpen(false)
    writeUrl(screenId, role, 'content', compact)
  }

  const navigate = (next: RouteKey) => {
    setRoute(next)
    setTabs((current) => (current.includes(next) ? current : [...current, next].slice(-6)))
    setDrawer(null)
    const nextId = next === 'clientCard' ? (clientKind === 'student' ? 'clients.student.card' : 'clients.lead.card') : routeScreen[next]
    setActiveScreenId(nextId)
    setScreenState('content')
    setScreenHistory((current) => current.at(-1) === nextId ? current : [...current, nextId].slice(-40))
    writeUrl(nextId, role, 'content', compact)
  }

  const goBack = () => {
    if (screenHistory.length < 2) return
    const nextHistory = screenHistory.slice(0, -1)
    const previous = nextHistory.at(-1)!
    setScreenHistory(nextHistory)
    openScreen(previous, { record: false })
  }

  const changeRole = (nextRole: Role) => {
    setRole(nextRole)
    if (!activeEntry.roles.includes(nextRole)) {
      const fallback = nextRole === 'client' ? 'client.lessons.upcoming' : nextRole === 'teacher' ? 'teacher.schedule' : nextRole === 'admin' ? 'chat.inbox' : 'overview.main'
      const fallbackEntry = screenById.get(fallback)!
      setActiveScreenId(fallback)
      setRoute((fallbackEntry.nativeRoute as RouteKey) || parentRouteForScreen(fallback))
      setScreenHistory([fallback])
      writeUrl(fallback, nextRole, 'content', compact)
    } else {
      writeUrl(activeScreenId, nextRole, screenState, compact)
    }
  }

  const changeState = (nextState: ScreenState) => {
    setScreenState(nextState)
    writeUrl(activeScreenId, role, nextState, compact)
  }

  const changeCompact = (nextCompact: boolean) => {
    setCompact(nextCompact)
    writeUrl(activeScreenId, role, screenState, nextCompact)
  }

  const notify = (message: string) => {
    setToast(message)
    window.setTimeout(() => setToast(null), 2600)
  }

  useEffect(() => {
    const catalogApi = {
      entries: screenManifest.map(({ id, title, group, roles }) => ({ id, title, group, roles })),
      coverage,
      navigate: (id: string) => openScreen(id),
    }
    ;(window as unknown as { __screenCatalog: typeof catalogApi }).__screenCatalog = catalogApi
  })

  const forceVisualSurface = new Set(['schedule.month', 'schedule.day.rooms', 'schedule.day.teachers', 'clients.students', 'settings.users', 'profile.main'])
  const showVisualSurface = screenState !== 'content' || !activeEntry.nativeRoute || forceVisualSurface.has(activeScreenId)
  const standalone = activeEntry.kind === 'auth' || (activeEntry.kind === 'state' && !activeEntry.nativeRoute)

  const catalog = <ScreenCatalog entries={screenManifest} activeId={activeScreenId} role={role} state={screenState} compact={compact} open={catalogOpen} coverage={coverage} onOpenChange={setCatalogOpen} onNavigate={(id) => openScreen(id)} onRoleChange={changeRole} onStateChange={changeState} onCompactChange={changeCompact} />

  if (standalone) {
    return <div className="prototype-host"><div className={cn('prototype-stage', compact && 'prototype-compact')}><VisualSurface entry={activeEntry} state={screenState} onNavigate={openScreen} /></div>{catalog}</div>
  }

  return (
    <div className="prototype-host">
    <div className={cn('prototype-stage', compact && 'prototype-compact')}>
    <div className="app-shell">
      <a className="skip-link" href="#main-content">Перейти к содержимому</a>
      <header className="topbar">
        <div className="workspace-tabs" role="tablist">
          {tabs.map((tab) => (
            <button key={tab} role="tab" className={route === tab ? 'active' : ''} type="button" onClick={() => navigate(tab)}>
              <span>{routeLabels[tab]}</span>
              <X
                size={15}
                onClick={(event) => {
                  event.stopPropagation()
                  const remaining = tabs.filter((item) => item !== tab)
                  const fallback = remaining.at(-1) ?? navByRole[role][0].key
                  setTabs(remaining.length ? remaining : [fallback])
                  if (route === tab) setRoute(fallback)
                }}
              />
            </button>
          ))}
          <button className="new-tab" type="button" title="Новая вкладка" onClick={() => openScreen('system.command')}><Plus size={21} /></button>
        </div>
      </header>

      <div className="routebar">
        <div className="history-controls">
          <button type="button" title="Назад" onClick={goBack} disabled={screenHistory.length < 2}><CaretLeft size={25} /></button>
          <button type="button" title="Вперёд" disabled><CaretRight size={25} /></button>
        </div>
        <div className="route-title">
          {showVisualSurface ? <><button type="button" onClick={() => openScreen(activeEntry.id)}>{activeEntry.group}</button><CaretRight size={18} /><strong>{activeEntry.title}</strong></> : route === 'clientCard' ? <><button type="button" onClick={() => navigate('clients')}>Клиенты</button><CaretRight size={18} /><strong>{clientKind === 'student' ? 'Ученик · Алиса Воронцова' : 'Лид · София Крылова'}</strong></> : <strong>{routeLabels[route]}</strong>}
        </div>
      </div>

      <div className="workspace-body">
        <aside className="sidebar">
          <button className="brand" type="button" onClick={() => navigate('overview')} title="Magic Music">
            <img src={appLogo} alt="Magic Music" />
          </button>
          <nav className="main-nav" aria-label="Основная навигация">
            {navByRole[role].map((item) => {
              const Icon = item.icon
              return (
                <button key={item.key} className={route === item.key || (route === 'clientCard' && item.key === 'clients') ? 'active' : ''} type="button" onClick={() => navigate(item.key)}>
                  <span className="rail-icon"><Icon size={21} weight={route === item.key ? 'fill' : 'regular'} />{item.key === 'chat' && <i>3</i>}</span>
                  <span>{item.label}</span>
                </button>
              )
            })}
          </nav>
          <button className="version-button" type="button" onClick={() => openScreen('system.updates')} title="Обновления">
            <Info size={18} />
            <span>1.5.14</span>
            <i aria-label="Доступно обновление" />
          </button>
        </aside>

        <main id="main-content" className="page-scroll">
          {showVisualSurface ? <VisualSurface entry={activeEntry} state={screenState} onNavigate={openScreen} /> : <>
          {route === 'overview' && <OverviewPage role={role} navigate={navigate} />}
          {route === 'schedule' && <SchedulePage role={role} setModal={setModal} setDrawer={setDrawer} notify={notify} />}
          {route === 'clients' && <ClientsPage setModal={setModal} openClient={(kind) => { setClientKind(kind); navigate('clientCard') }} />}
          {route === 'clientCard' && <ClientWorkspacePage kind={clientKind} onClose={() => navigate('clients')} setModal={setModal} notify={notify} />}
          {route === 'tasks' && <TasksPage setModal={setModal} notify={notify} />}
          {route === 'analytics' && <AnalyticsPage role={role} notify={notify} />}
          {route === 'settings' && <SettingsPage notify={notify} />}
          {route === 'chat' && <ChatPage notify={notify} role={role} />}
          {route === 'teacherStudents' && <TeacherStudentsPage setDrawer={setDrawer} />}
          {route === 'clientLessons' && <ClientLessonsPage notify={notify} />}
          {route === 'clientSubscription' && <ClientSubscriptionPage />}
          {route === 'clientProfile' && <ClientProfilePage notify={notify} />}
          </>}
        </main>
      </div>

      {drawer === 'lesson' && <LessonDrawer onClose={() => setDrawer(null)} setModal={setModal} notify={notify} />}
      {modal === 'lesson' && <LessonModal onClose={() => setModal(null)} notify={notify} />}
      {modal === 'recurring' && <RecurringModal onClose={() => setModal(null)} notify={notify} />}
      {modal === 'task' && <TaskEditModal onClose={() => setModal(null)} notify={notify} />}
      {modal === 'taskNew' && <TaskModal onClose={() => setModal(null)} notify={notify} />}
      {modal === 'lead' && <ClientModal kind="lead" onClose={() => setModal(null)} notify={notify} />}
      {modal === 'student' && <ClientModal kind="student" onClose={() => setModal(null)} notify={notify} />}
      {modal === 'version' && <VersionModal onClose={() => setModal(null)} notify={notify} />}
      {toast && <div className="toast"><CheckCircle size={20} weight="fill" /><span>{toast}</span></div>}
    </div>
    </div>
    {catalog}
    </div>
  )
}

function OverviewPage({ role, navigate }: { role: Role; navigate: (route: RouteKey) => void }) {
  const [period, setPeriod] = useState('Месяц')
  const canSeeFinance = role === 'director' || role === 'system_admin'
  const kpis = [
    ...(canSeeFinance ? [
      { label: 'Выручка', value: '940 200 ₽', source: 'Финансы', target: 'analytics' as RouteKey, icon: Receipt, tone: 'success' },
      { label: 'Ожидаемые платежи', value: '128 500 ₽', source: 'Платежи', target: 'analytics' as RouteKey, icon: CalendarBlank, tone: 'gold' },
      { label: 'Ученики с долгом', value: '5', source: 'Балансы', target: 'clients' as RouteKey, icon: WarningCircle, tone: 'danger' },
    ] : []),
    { label: 'Активные ученики', value: '246', source: 'Система', target: 'clients' as RouteKey, icon: GraduationCap, tone: 'gold' },
    { label: 'Новые лиды', value: '7', source: 'Лиды', target: 'clients' as RouteKey, icon: UserPlus, tone: 'warning' },
    { label: 'Открытые задачи', value: '18', source: 'Задачи', target: 'tasks' as RouteKey, icon: CheckSquare, tone: 'warning' },
    { label: 'Просроченные задачи', value: '3', source: 'Задачи', target: 'tasks' as RouteKey, icon: Clock, tone: 'danger' },
    { label: 'Пробные занятия', value: '9', source: 'Расписание', target: 'schedule' as RouteKey, icon: CalendarBlank, tone: 'gold' },
    { label: 'Конфликты расписания', value: '2', source: 'Расписание', target: 'schedule' as RouteKey, icon: Warning, tone: 'danger' },
    { label: 'Загрузка аудиторий', value: '184', source: 'Расписание', target: 'analytics' as RouteKey, icon: Buildings, tone: 'gold' },
    { label: 'Действия сотрудников', value: '326', source: 'Активность', target: 'analytics' as RouteKey, icon: ListChecks, tone: 'gold' },
  ]
  return <div className="page page-dashboard exact-overview-page">
    <PageHeader title="Сводка" description={period === '7 дней' ? '10 - 16 авг' : period === 'Квартал' ? '1 июн - 16 авг' : '1 - 16 авг'} />
    <div className="overview-filters">
      <Segmented items={['7 дней', 'Месяц', 'Квартал']} value={period} onChange={setPeriod} />
      <Field label="Филиал"><select><option>Все филиалы</option><option>Садовая</option><option>Петроградская</option></select></Field>
    </div>
    <section className="surface attention-panel">
      <h2>Требует внимания</h2>
      <div>
        <button type="button" onClick={() => navigate('tasks')}><WarningCircle size={19} /><span>Просроченные задачи</span><b>3</b></button>
        <button type="button" onClick={() => openVisualScreen('schedule.conflicts')}><Warning size={19} /><span>Конфликты расписания</span><b>2</b></button>
        {canSeeFinance && <button type="button" onClick={() => navigate('clients')}><Receipt size={19} /><span>Ученики с долгом</span><b>5</b></button>}
        {canSeeFinance && <button type="button" onClick={() => navigate('analytics')}><CalendarBlank size={19} /><span>Ожидаемые платежи</span><b>128 500 ₽</b></button>}
      </div>
    </section>
    <div className="kpi-grid">
      {kpis.map(({ label, value, source, target, icon: Icon, tone }) => <button type="button" className={cn('surface kpi-card exact', `tone-${tone}`)} key={label} onClick={() => navigate(target)}><span className="kpi-icon"><Icon size={20} /></span><span className="kpi-copy"><strong>{value}</strong><b>{label}</b><small>{source}</small></span><CaretRight size={19} /></button>)}
    </div>
  </div>
}

function SchedulePage({ role, setModal, setDrawer, notify }: { role: Role; setModal: (name: ModalName) => void; setDrawer: (value: string | null) => void; notify: (message: string) => void }) {
  const [view, setView] = useState('Месяц')
  const [filterOpen, setFilterOpen] = useState(false)
  const [teacherMode, setTeacherMode] = useState('По аудиториям')
  const [weekOffset, setWeekOffset] = useState(0)
  const weekDays = ['Пн\n10 августа', 'Вт\n11 августа', 'Ср\n12 августа', 'Чт\n13 августа', 'Пт\n14 августа', 'Сб\n15 августа', 'Вс\n16 августа']
  const roomColumns = ['Аудитория 1', 'Аудитория 2', 'Аудитория 3', 'Студия']
  const dayColumns = teacherMode === 'По аудиториям' ? roomColumns : ['Анна Лебедева', 'Илья Морозов', 'Мария Орлова', 'Денис Волков']
  const period = view === 'Месяц'
    ? 'Август 2026'
    : view === 'Неделя'
      ? weekOffset === 0 ? '10 августа - 16 августа 2026' : weekOffset > 0 ? '17 августа - 23 августа 2026' : '3 августа - 9 августа 2026'
      : 'сб, 15 августа 2026'
  return (
    <div className="schedule-page exact-schedule-page">
      <section className="schedule-control-panel exact surface">
        <div className="schedule-title-row">
          <div><h1>{role === 'teacher' ? 'Моё расписание' : 'Расписание'}</h1><p>{period}</p></div>
          <div className="schedule-actions"><Button className="schedule-search-button" variant="ghost" size="icon" title="Найти занятие"><MagnifyingGlass size={20} /></Button><Button className="schedule-filter-button" variant={filterOpen ? 'secondary' : 'ghost'} icon={<SlidersHorizontal size={18} />} onClick={() => setFilterOpen(!filterOpen)}><span>{filterOpen ? 'Фильтры применены' : 'Фильтры'}</span></Button><Button className="schedule-refresh-button" variant="ghost" size="icon" title="Обновить расписание" onClick={() => notify('Расписание обновлено')}><ArrowClockwise size={20} /></Button>{role !== 'teacher' && <Button className="schedule-create-button" icon={<Plus size={18} />} onClick={() => setModal('lesson')}>Создать занятие</Button>}</div>
        </div>
        <div className="schedule-toolbar exact">
          <Segmented items={['Месяц', 'Неделя', 'День']} value={view} onChange={setView} />
          <div className="date-nav"><Button variant="ghost" size="icon" title="Предыдущий период" onClick={() => setWeekOffset((v) => v - 1)}><CaretLeft size={21} /></Button><strong>{view === 'Месяц' ? 'августа 2026' : view === 'Неделя' ? (weekOffset === 0 ? '10 августа - 16 августа 2026' : weekOffset > 0 ? '17 августа - 23 августа 2026' : '3 августа - 9 августа 2026') : 'сб, 15 августа 2026'}</strong><Button variant="quiet" size="sm" onClick={() => setWeekOffset(0)}>Сегодня</Button><Button variant="ghost" size="icon" title="Следующий период" onClick={() => setWeekOffset((v) => v + 1)}><CaretRight size={21} /></Button></div>
          <label className="select-compact"><MapPin size={18} /><span><small>Филиал</small><select><option>Садовая</option><option>Петроградская</option></select></span></label>
          <Button variant="ghost" size="icon" title="Часовой пояс"><Clock size={21} /></Button>
        </div>
      </section>
      {filterOpen && (
        <div className="filter-panel surface">
          <Field label="Филиал"><select><option>Все филиалы</option><option>Садовая</option><option>Петроградская</option></select></Field>
          <Field label="Преподаватель"><select><option>Все преподаватели</option><option>Анна Лебедева</option><option>Мария Орлова</option></select></Field>
          <Field label="Тип занятий"><select><option>Все занятия</option><option>Только пробные</option></select></Field>
          <Field label="Конфликты"><select><option>Все состояния</option><option>Только с конфликтами</option></select></Field>
          {view === 'День' && <Field label="Группировка"><select value={teacherMode} onChange={(event) => setTeacherMode(event.target.value)}><option>По аудиториям</option><option>По преподавателям</option></select></Field>}
          <Button variant="quiet" size="sm" onClick={() => setFilterOpen(false)}>Сбросить</Button>
          <Button size="sm" onClick={() => setFilterOpen(false)}>Применить</Button>
        </div>
      )}
      {view === 'День' && <div className="day-mode-row"><Segmented items={['По аудиториям', 'По преподавателям']} value={teacherMode} onChange={setTeacherMode} /></div>}
      <div className="schedule-status-row">
        <Badge tone="neutral">Обычные</Badge><Badge tone="success">Пробные</Badge><Badge tone="warning">Пиковая</Badge><Badge tone="danger"><WarningCircle size={14} /> Конфликт</Badge>
      </div>
      {view === 'День' && <div className="availability-row"><Badge tone="success"><CheckCircle size={14} /> Без занятий: 2</Badge><Badge tone="warning"><CalendarBlank size={14} /> С занятиями: 4</Badge><Badge tone="danger"><WarningCircle size={14} /> Конфликты: 1</Badge></div>}
      <div className={cn('calendar exact surface', `calendar-${view.toLowerCase()}`, view === 'День' && teacherMode === 'По преподавателям' && 'teacher-timeline')}>
        {view === 'Месяц' ? (
          <MonthCalendar setDrawer={setDrawer} />
        ) : view === 'День' && teacherMode === 'По преподавателям' ? (
          <TeacherDayTimeline setDrawer={setDrawer} setModal={setModal} />
        ) : (
          <>
            <div className="calendar-corner">Время</div>
            {(view === 'Неделя' ? weekDays : dayColumns).map((day, index) => <div key={day} className={cn('calendar-day-head', view === 'Неделя' && index === 5 && 'today')}><b>{day}</b>{view === 'День' && <small>{index === 0 ? '2 занятия' : index === 2 ? 'есть конфликт' : '1 занятие'}</small>}</div>)}
            <div className="time-column">{Array.from({ length: 11 }, (_, i) => <span key={i}>{`${9 + i}:00`}</span>)}</div>
            <div className="calendar-grid-lines" />
            <div className="calendar-now"><span>12:42</span></div>
            {lessons.map((lesson) => (
              <button
                type="button"
                key={lesson.id}
                className={cn('lesson-block', `lesson-${lesson.tone}`, lesson.conflict && 'has-conflict')}
                style={{
                  left: `calc(68px + ${(lesson.day / (view === 'Неделя' ? 7 : dayColumns.length)) * 100}% - ${(lesson.day / (view === 'Неделя' ? 7 : dayColumns.length)) * 68}px)`,
                  top: 48 + (lesson.start - 9) * 61,
                  width: `calc(${100 / (view === 'Неделя' ? 7 : dayColumns.length)}% - ${68 / (view === 'Неделя' ? 7 : dayColumns.length) + 7}px)`,
                  height: lesson.span * 61 - 6,
                } as CSSProperties}
                onClick={() => setDrawer('lesson')}
              >
                <span className="lesson-time">{`${String(Math.floor(lesson.start)).padStart(2, '0')}:${lesson.start % 1 ? '30' : '00'}`}</span>
                <b>{lesson.title}</b>
                <small>{lesson.sub}</small>
                <small>{lesson.room}</small>
                {lesson.conflict && <Warning size={16} weight="fill" />}
              </button>
            ))}
            {role !== 'teacher' && <button className="empty-slot" type="button" onClick={() => setModal('lesson')} style={{ left: `calc(68px + ${(Math.min(3, (view === 'Неделя' ? 7 : dayColumns.length) - 1) / (view === 'Неделя' ? 7 : dayColumns.length)) * 100}% - ${(Math.min(3, (view === 'Неделя' ? 7 : dayColumns.length) - 1) / (view === 'Неделя' ? 7 : dayColumns.length)) * 68}px)`, top: 48 + 2 * 61, width: `calc(${100 / (view === 'Неделя' ? 7 : dayColumns.length)}% - ${68 / (view === 'Неделя' ? 7 : dayColumns.length) + 7}px)`, height: 55 } as CSSProperties}><Plus size={15} /> 11:00</button>}
          </>
        )}
      </div>
    </div>
  )
}

function TeacherDayTimeline({ setDrawer, setModal }: { setDrawer: (value: string) => void; setModal: (name: ModalName) => void }) {
  const rows = [
    ['Анна Лебедева', '2 занятия · 2 ч', 11, 'Алиса Воронцова', 'Фортепиано · Аудитория 2'],
    ['Илья Морозов', '1 занятие · 1 ч', 10.5, 'Матвей Соколов', 'Гитара · Аудитория 1'],
    ['Мария Орлова', '2 занятия · 2 ч', 12, 'София Крылова', 'Вокал · Аудитория 1'],
    ['Денис Волков', '1 занятие · 1 ч', 14, 'Лев Фролов', 'Барабаны · Студия'],
  ] as const
  return <div className="teacher-day-grid"><h3>Суббота</h3><div className="teacher-time-head"><b><ChalkboardTeacher size={17} /> Преподаватель</b>{['08:00-10:00', '10:00-12:00', '12:00-14:00', '14:00-16:00', '16:00-18:00', '18:00-20:00', '20:00-22:00'].map((time) => <span key={time}>{time}</span>)}</div>{rows.map((row, index) => <div className="teacher-time-row" key={row[0]}><button type="button" className="teacher-label" onClick={() => openVisualScreen('settings.teacher.detail')}><i /><b>{row[0]}</b><small>{row[1]}</small></button><div className="teacher-track" onDoubleClick={() => setModal('lesson')}><button type="button" className={cn('teacher-lesson', index === 2 && 'has-conflict')} style={{ left: `${((row[2] - 8) / 14) * 100}%`, width: '13%' }} onClick={() => setDrawer('lesson')}><b>{row[3]}</b><small>{row[4]}</small></button></div></div>)}</div>
}

function MonthCalendar({ setDrawer }: { setDrawer: (value: string) => void }) {
  const days = Array.from({ length: 35 }, (_, i) => i - 1)
  return (
    <div className="month-calendar">
      {['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((d) => <div className="month-head" key={d}>{d}</div>)}
      {days.map((day, index) => {
        const inMonth = day > 0 && day <= 31
        return <button type="button" className={cn('month-cell', !inMonth && 'outside', day === 15 && 'today')} key={index} onClick={() => inMonth && setDrawer('lesson')}><b>{inMonth ? day : day <= 0 ? 31 + day : day - 31}</b>{inMonth && day % 4 === 0 && <span className="month-event gold">10:00 Фортепиано</span>}{inMonth && day % 5 === 0 && <span className="month-event blue">14:30 Вокал</span>}</button>
      })}
    </div>
  )
}

function ClientsPage({ setModal, openClient }: { setModal: (name: ModalName) => void; openClient: (kind: 'lead' | 'student') => void }) {
  const [kind, setKind] = useState('Лиды')
  const [query, setQuery] = useState('')
  const leadColumns = [
    { name: 'В процессе', items: [['София Крылова', '+7 915 208-44-63', 'Сайт', 'Садовая']] },
    { name: 'Пробный урок', items: [['Матвей Соколов', '+7 921 744-30-08', 'Рекомендация', 'Садовая']] },
    { name: 'Звонок после пробного', items: [] },
    { name: 'Успешный', items: [] },
    { name: 'Отложенный', items: [] },
  ]
  const studentColumns = [
    { name: 'Обучаются', items: [['Алиса Воронцова', '+7 999 418-22-17', 'Садовая', '12 занятий'], ['Лев Фролов', '+7 903 551-72-19', 'Садовая', '9 занятий']] },
    { name: 'Пауза', items: [['Вера Мельникова', '+7 926 155-82-11', 'Петроградская', '6 занятий']] },
    { name: 'Завершили', items: [] },
  ]
  const columns = (kind === 'Лиды' ? leadColumns : studentColumns).map((column) => ({ ...column, items: column.items.filter((item) => item[0].toLowerCase().includes(query.toLowerCase()) || item[1].includes(query)) }))
  return (
    <div className="clients-page exact-clients-page">
      <div className="client-mode-head exact">
        <div className="client-mode-toggle"><button type="button" className={kind === 'Лиды' ? 'active' : ''} onClick={() => setKind('Лиды')}><UsersThree size={17} />Лиды</button><button type="button" className={kind === 'Ученики' ? 'active' : ''} onClick={() => setKind('Ученики')}><GraduationCap size={17} />Ученики</button></div>
        <Button variant="ghost" size="icon" title="Уведомления"><Bell size={20} /><i className="notification-count">9+</i></Button>
      </div>
      <div className="board-toolbar">
        <div><h1>{kind === 'Лиды' ? `Воронка продаж · ${columns.reduce((total, column) => total + column.items.length, 0)}` : 'Ученики'}</h1>{kind === 'Ученики' && <span>{columns.reduce((total, column) => total + column.items.length, 0)}</span>}</div>
        <label className="search-input"><MagnifyingGlass size={18} /><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder={kind === 'Лиды' ? 'Имя, телефон, источник' : 'Имя или телефон'} /></label>
        <Button variant="secondary" icon={<Funnel size={17} />} target="clients.filters">Фильтры</Button>
      </div>
      <div className="kanban-board">
        {columns.map((column) => <section className="kanban-column" key={column.name}><header><span className="status-dot" /><b>{column.name}</b><i>{column.items.length}</i></header><div>{column.items.map((item) => <article className="client-board-card surface" key={item[0]}><button type="button" className="client-card-open" aria-label={'Открыть карточку: ' + item[0]} onClick={() => openClient(kind === 'Лиды' ? 'lead' : 'student')}><span className="person-cell"><span className="avatar soft">{item[0].split(' ').map((value) => value[0]).join('')}</span><span><b>{item[0]}</b><small>{item[1]}</small></span></span><dl><dt>{kind === 'Лиды' ? 'Источник' : 'Филиал'}</dt><dd>{item[2]}</dd><dt>{kind === 'Лиды' ? 'Филиал' : 'Занятия'}</dt><dd>{item[3]}</dd></dl></button><div className="card-actions"><Button variant="ghost" size="sm" onClick={() => openClient(kind === 'Лиды' ? 'lead' : 'student')}>Открыть</Button><Button variant="ghost" size="icon" title="Действия" target={kind === 'Лиды' ? 'clients.lead.card' : 'clients.student.card'}><DotsThree size={18} /></Button></div></article>)}</div></section>)}
      </div>
      <button type="button" className="board-fab" title={kind === 'Лиды' ? 'Новый контакт' : 'Новый ученик'} aria-label={kind === 'Лиды' ? 'Новый контакт' : 'Новый ученик'} onClick={() => setModal(kind === 'Лиды' ? 'lead' : 'student')}><UserPlus size={22} /></button>
    </div>
  )
}

function TasksPage({ setModal, notify }: { setModal: (name: ModalName) => void; notify: (message: string) => void }) {
  const [tab, setTab] = useState('Открытые')
  const [calendarMode, setCalendarMode] = useState(false)
  const visibleTasks = taskRows.filter((_, index) => tab !== 'Закрытые' || index === 4)
  return (
    <div className="tasks-page exact-tasks-page">
      <div className="task-appbar"><h1>Задачи</h1><Button icon={<Plus size={18} />} onClick={() => setModal('taskNew')}>Новая задача</Button></div>
      <div className="task-state-filter exact desktop-task-state"><Segmented items={['Открытые', 'Просроченные', 'Закрытые', 'Все']} value={tab} onChange={setTab} /><span>Открыто: 18</span></div>
      <div className="mobile-task-state"><label><span>Задачи</span><select value={tab} onChange={(event) => setTab(event.target.value)}><option>Открытые</option><option>Просроченные</option><option>Закрытые</option><option>Все</option></select></label><Button variant="ghost" size="icon" title="Расширенные фильтры"><SlidersHorizontal size={19} /></Button></div>
      <div className="list-toolbar task-tools exact"><label className="search-input"><MagnifyingGlass size={18} /><input placeholder="Поиск" /></label><select aria-label="Приоритет"><option>Все приоритеты</option><option>Высокий</option><option>Обычный</option><option>Низкий</option></select><select aria-label="Область"><option>Мои задачи</option><option>Мой филиал</option><option>Вся школа</option><option>Все доступные</option></select><Button variant="secondary"><Check size={17} />Сегодня</Button><Button variant="secondary" size="icon" title={calendarMode ? 'Показать список' : 'Показать календарь'} onClick={() => setCalendarMode(!calendarMode)}>{calendarMode ? <ListChecks size={18} /> : <CalendarBlank size={18} />}</Button></div>
      {calendarMode ? <TaskMonthCalendar onOpen={() => openVisualScreen('tasks.calendar.day')} /> : <section className="task-card-list">{visibleTasks.map((task) => <article className="shared-task-card" key={task.title}><div className="shared-task-open"><span className="shared-task-title"><button type="button" className="task-title-button" onClick={() => openVisualScreen(task.state === 'Готово' ? 'tasks.detail.closed' : 'tasks.detail')}>{task.title}</button><Button variant="ghost" size="icon" title="Изменить" onClick={() => setModal('task')}><PencilSimple size={18} /></Button></span><p>{task.owner === 'Олег Романов' ? 'Сверить список клиентов с ожидаемыми платежами.' : 'Проверить детали и выполнить задачу в указанный срок.'}</p><span className="task-meta-row"><Badge tone="gold"><Clock size={15} /> {task.due}</Badge><Badge tone={task.priority === 'Высокий' ? 'danger' : task.priority === 'Низкий' ? 'neutral' : 'info'}><WarningCircle size={15} /> {task.priority}</Badge><Badge tone={task.state === 'Готово' ? 'success' : 'gold'}><UsersThree size={15} /> {task.state === 'Готово' ? 'Закрыта' : 'Открыта'}</Badge></span></div>{task.state !== 'Готово' && <Button className="task-close-action" icon={<CheckCircle size={18} />} onClick={() => openVisualScreen('tasks.detail.closed')}>Закрыть задачу</Button>}<button type="button" className="task-history-link" onClick={() => openVisualScreen('tasks.detail')}>Открыть детали и историю</button></article>)}</section>}
    </div>
  )
}

function TaskMonthCalendar({ onOpen }: { onOpen: () => void }) {
  const cells = Array.from({ length: 35 }, (_, index) => index - 3)
  return <section className="task-month-grid"><header><Button variant="ghost" size="icon" title="Предыдущий месяц" target="tasks.calendar"><CaretLeft size={20} /></Button><h2>Август 2026</h2><Button variant="ghost" size="icon" title="Следующий месяц" target="tasks.calendar"><CaretRight size={20} /></Button></header><div className="task-week-head">{['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((day) => <b key={day}>{day}</b>)}</div><div className="task-month-cells">{cells.map((day, index) => <button type="button" key={index} className={cn(day < 1 && 'outside', day === 15 && 'today')} onClick={day > 0 ? onOpen : () => openVisualScreen('tasks.calendar')}><b>{day > 0 ? day : 31 + day}</b>{day > 0 && day % 3 === 0 && <span>{day % 2 === 0 ? 2 : 1}</span>}</button>)}</div></section>
}

function AnalyticsPage({ role, notify }: { role: Role; notify: (message: string) => void }) {
  const [tab, setTab] = useState('Обзор')
  const canSeeFinance = role === 'director' || role === 'system_admin'
  return (
    <div className="analytics-page exact-analytics-page">
      <div className="underlined-tabs"><button className={tab === 'Обзор' ? 'active' : ''} onClick={() => setTab('Обзор')}>Обзор</button><button className={tab === 'Журналы' ? 'active' : ''} onClick={() => setTab('Журналы')}>Журналы</button></div>
      <div className="analytics-filter-bar"><h1>Аналитика</h1><Button variant="secondary" icon={<CalendarBlank size={17} />}>01.03.2026 - 15.08.2026</Button><Field label="Филиал"><select><option>{canSeeFinance ? 'Вся школа' : 'Все доступные филиалы'}</option><option>Садовая</option></select></Field></div>
      {tab === 'Обзор' ? <AnalyticsOverview canSeeFinance={canSeeFinance} notify={notify} /> : <Journals canSeeFinance={canSeeFinance} />}
    </div>
  )
}

function AnalyticsOverview({ canSeeFinance, notify }: { canSeeFinance: boolean; notify: (message: string) => void }) {
  return <div className="report-dashboard exact"><div className="report-head"><h2>Единая сводка</h2><Button variant="secondary" size="sm" icon={<ChartBar size={16} />} onClick={() => notify('Подготовка XLSX началась')}>XLSX</Button><Button variant="secondary" size="sm" icon={<DownloadSimple size={16} />} onClick={() => notify('Подготовка CSV началась')}>CSV</Button>{canSeeFinance && <Button variant="secondary" size="sm" icon={<Buildings size={16} />} onClick={() => notify('Подготовка финансового XLSX началась')}>Финансы XLSX</Button>}</div><section className="surface report-section"><h3>Занятия</h3><p>Успешность за выбранный период и филиал</p><button type="button" className="report-row" onClick={() => openVisualScreen('schedule.week')}><CalendarBlank size={20} /><span><b>Успешно завершённые занятия</b><small>184 из 196</small></span><strong>93,9%</strong></button></section><section className="surface report-section"><h3>Клиенты и воронка</h3><p>Статусы с теми же периодом и филиалом</p>{[['В процессе', 'Лид', '7'], ['Пробный урок', 'Лид', '9'], ['Обучаются', 'Ученик', '246']].map((row) => <button type="button" className="report-row" key={row[0]} onClick={() => openVisualScreen(row[1] === 'Ученик' ? 'clients.students' : 'clients.leads')}><span><b>{row[0]}</b><small>{row[1]}</small></span><strong>{row[2]}</strong></button>)}</section><section className="surface report-section"><h3>Задачи</h3><p>Текущая очередь · период и филиал к этому показателю не применяются</p><button type="button" className="report-row" onClick={() => openVisualScreen('tasks.list')}><span><b>Открыто: 18 · Просрочено: 3</b></span><CaretRight size={18} /></button></section>{canSeeFinance && <section className="surface report-section"><h3>Финансы школы</h3><p>Выручка и расходы за выбранный период и филиал</p><button type="button" className="report-row" onClick={() => openVisualScreen('analytics.finance')}><span><b>Август 2026</b><small>Выручка 940 200 ₽ · расходы 286 000 ₽</small></span><CaretRight size={18} /></button></section>}</div>
}

function Journals({ canSeeFinance }: { canSeeFinance: boolean }) {
  const journals = ['Действия', ...(canSeeFinance ? ['Финансовые операции', 'Расчёты преподавателей'] : ['Расчёты преподавателей'])]
  return <div className="journal-layout exact"><label className="journal-select"><span>Журнал</span><select>{journals.map((item) => <option key={item}>{item}</option>)}</select></label><section className="table-shell surface"><table><thead><tr><th>Дата</th><th>Событие</th><th>Объект</th><th>Сотрудник</th></tr></thead><tbody>{[['15.08, 12:31', 'Занятие завершено', 'Алиса Воронцова', 'Анна Лебедева'], ['15.08, 11:46', 'Занятие перенесено', 'Матвей Соколов', 'Елена Смирнова'], ['15.08, 10:12', 'Создано пробное занятие', 'София Крылова', 'Алина К.']].map((row) => <tr key={row[0]}>{row.map((cell) => <td key={cell}>{cell}</td>)}</tr>)}</tbody></table></section></div>
}

function SettingsPage({ notify }: { notify: (message: string) => void }) {
  const [section, setSection] = useState('Организация')
  const sections = [
    ['Организация', Buildings], ['Расписание', CalendarBlank], ['Клиенты', AddressBook],
    ['Продажи и оплаты', CreditCard], ['Пользователи и доступы', ShieldCheck], ['Данные и обслуживание', Archive],
  ] as const
  return <div className="settings-page exact-settings-page" onClickCapture={(event) => {
    const button = (event.target as HTMLElement).closest('button')
    if (!button?.matches('.settings-list button, .settings-catalog-grid button, .package-grid button')) return
    const text = button.textContent?.trim() ?? ''
    const target = text.includes('Филиал') || text.includes('Садовая') || text.includes('Петроградская')
      ? 'settings.branch.detail'
      : text.includes('Анна Лебедева') || text.includes('Илья Морозов')
        ? 'settings.teacher.schedule'
        : text.includes('Группа')
          ? 'settings.group.detail'
          : text.includes('Старт') || text.includes('Развитие') || text.includes('Премиум')
            ? 'settings.package.detail'
            : text.includes('Роли') || text.includes('Елена Смирнова') || text.includes('Олег Романов')
              ? 'settings.user.detail'
              : text.includes('Ворон') ? 'settings.crm.pipeline'
                : text.includes('Структура') || text === 'ИмяЛид и ученик · Текст' || text.startsWith('Категории') ? 'settings.crm.fields'
                  : text.includes('Значения') || text.includes('Рекламный источник') ? 'settings.crm.lists'
                    : 'settings.catalog.detail'
    event.preventDefault()
    event.stopPropagation()
    openVisualScreen(target)
  }}><h1>Настройки системы</h1><label className="settings-area-select"><span>Раздел настроек</span><select value={section} onChange={(event) => setSection(event.target.value)}>{sections.map(([name]) => <option key={name}>{name}</option>)}</select></label><div className="settings-layout exact"><aside className="settings-nav exact">{sections.map(([name, Icon]) => <button type="button" key={name} className={section === name ? 'active' : ''} onClick={() => setSection(name)}><Icon size={22} /><span>{name}</span></button>)}</aside><section className="settings-content exact"><SettingsContent section={section} notify={notify} /></section></div></div>
}

function LegacySettingsContent({ section, notify }: { section: string; notify: (message: string) => void }) {
  const [sub, setSub] = useState('Доступы')
  if (section === 'Пользователи и доступы') return <><div className="section-head padded"><div><h2>Пользователи и доступы</h2><p>Учётные записи сотрудников и преподавателей</p></div><Button icon={<UserPlus size={18} />}>Новый пользователь</Button></div><div className="padded top-none"><Segmented items={['Доступы', 'Сотрудники', 'Преподаватели']} value={sub} onChange={setSub} /></div><div className="table-shell embedded"><table><thead><tr><th>Пользователь</th><th>Роль</th><th>Почта</th><th>Состояние</th><th /></tr></thead><tbody>{[['Елена Смирнова', 'Администратор', 'elena@magicmusic.ru'], ['Анна Лебедева', 'Преподаватель', 'a.lebedeva@magicmusic.ru'], ['Олег Романов', 'Управляющий', 'o.romanov@magicmusic.ru']].map((row, i) => <tr key={row[0]}><td><span className="person-cell"><span className="avatar soft">{row[0].split(' ').map((v) => v[0]).join('')}</span><b>{row[0]}</b></span></td><td>{row[1]}</td><td>{row[2]}</td><td><Badge tone="success">Активен</Badge></td><td><Button variant="ghost" size="icon"><PencilSimple size={17} /></Button></td></tr>)}</tbody></table></div></>
  if (section === 'Расписание') return <><div className="section-head padded"><div><h2>Расписание</h2><p>Рабочие часы, доступность и учебные группы</p></div></div><div className="padded top-none"><Segmented items={['Часы работы филиалов', 'Графики преподавателей', 'Учебные группы']} value={sub === 'Доступы' ? 'Часы работы филиалов' : sub} onChange={setSub} /></div><div className="settings-list">{[['Садовая', 'Пн - Сб, 09:00 - 21:00'], ['Петроградская', 'Пн - Вс, 10:00 - 20:00']].map((row) => <button key={row[0]}><span className="settings-list-icon"><Clock size={20} /></span><span><b>{row[0]}</b><small>{row[1]}</small></span><CaretRight size={18} /></button>)}</div></>
  if (section === 'Продажи и оплаты') return <><div className="section-head padded"><div><h2>Продажи и оплаты</h2><p>Каталог абонементов</p></div><Button icon={<Plus size={18} />}>Новый абонемент</Button></div><div className="package-grid padded top-none">{[['Старт', '4 занятия', '8 900 ₽'], ['Развитие', '8 занятий', '16 500 ₽'], ['Премиум', '12 занятий', '23 400 ₽']].map((item) => <button key={item[0]}><span><b>{item[0]}</b><Badge tone="success">Действует</Badge></span><strong>{item[2]}</strong><small>{item[1]} · срок 45 дней</small><span className="package-actions"><PencilSimple size={17} /> Изменить</span></button>)}</div></>
  if (section === 'Данные и обслуживание') {
    const dataTab = ['Качество данных', 'Запросы на удаление'].includes(sub) ? sub : 'Качество данных'
    return <><div className="section-head padded"><div><h2>Данные и обслуживание</h2><p>Проверки качества данных и запросы на удаление</p></div></div><div className="padded top-none"><Segmented items={['Качество данных', 'Запросы на удаление']} value={dataTab} onChange={setSub} /></div>{dataTab === 'Качество данных' && <div className="quality-grid padded"><div><CheckCircle size={26} weight="fill" /><span><b>Данные в порядке</b><small>Последняя проверка сегодня в 09:42</small></span></div><Button variant="secondary" onClick={() => notify('Проверка запущена')}>Проверить сейчас</Button></div>}{dataTab === 'Запросы на удаление' && <div className="empty-state"><span><Archive size={24} /></span><b>Нет активных запросов</b><p>Перед удалением система покажет связи и возможные блокировки.</p></div>}</>
  }
  return <><div className="section-head padded"><div><h2>{section}</h2><p>{section === 'Организация' ? 'Филиалы, аудитории и направления' : 'Воронки, статусы и пользовательские поля'}</p></div><Button icon={<Plus size={18} />}>Добавить</Button></div><div className="settings-list">{(section === 'Организация' ? [['Филиал на Садовой', '6 аудиторий · 8 направлений'], ['Филиал на Петроградской', '4 аудитории · 6 направлений']] : [['Воронка продаж', '5 этапов'], ['Источники обращений', '12 значений'], ['Причины отказа', '8 значений']]).map((row) => <button key={row[0]}><span className="settings-list-icon"><Buildings size={20} /></span><span><b>{row[0]}</b><small>{row[1]}</small></span><CaretRight size={18} /></button>)}</div></>
}

function SettingsContent({ section, notify }: { section: string; notify: (message: string) => void }) {
  const [subByArea, setSubByArea] = useState<Record<string, string>>({
    'Организация': 'Филиалы',
    'Расписание': 'Часы филиалов',
    'Клиенты': 'Поля и категории',
    'Пользователи и доступы': 'Доступы',
    'Данные и обслуживание': 'Качество данных',
  })
  const sub = subByArea[section] ?? ''
  const setSub = (value: string) => setSubByArea((current) => ({ ...current, [section]: value }))

  if (section === 'Организация') {
    const branches = sub === 'Филиалы'
    return <div className="settings-workspace"><div className="section-head padded"><div><h2>{branches ? 'Организация' : 'Организационные справочники'}</h2><p>{branches ? 'Филиалы; аудитории и дисциплины настраиваются внутри филиала' : 'Дисциплины школы и причины отказа'}</p></div>{branches && <div className="page-actions"><Button variant="secondary" icon={<ArrowClockwise size={17} />} onClick={() => notify('Список филиалов обновлён')}>Обновить</Button><Button icon={<Plus size={17} />}>Новый филиал</Button></div>}</div><div className="settings-toolbar-line"><Segmented items={['Филиалы', 'Справочники']} value={sub} onChange={setSub} />{branches && <><label className="search-input"><MagnifyingGlass size={18} /><input placeholder="Поиск по названию" /></label><label className="check-row"><input type="checkbox" /> Показать архив</label></>}</div>{branches ? <div className="settings-list exact-settings-list">{[['Филиал на Садовой', '6 аудиторий · 8 дисциплин'], ['Филиал на Петроградской', '4 аудитории · 6 дисциплин']].map((row) => <button key={row[0]}><span className="settings-list-icon"><Buildings size={20} /></span><span><b>{row[0]}</b><small>{row[1]}</small></span><Badge tone="success">Работает</Badge><CaretRight size={18} /></button>)}</div> : <div className="settings-catalog-grid"><button><MusicNotes size={22} /><span><b>Дисциплины</b><small>Направления обучения школы</small></span><CaretRight size={18} /></button><button><WarningCircle size={22} /><span><b>Причины отказа</b><small>Справочник для завершения работы с лидами</small></span><CaretRight size={18} /></button></div>}</div>
  }

  if (section === 'Расписание') {
    const title = sub === 'Часы филиалов' ? 'Часы работы филиалов' : sub === 'Графики преподавателей' ? 'Графики преподавателей' : 'Учебные группы'
    const subtitle = sub === 'Часы филиалов' ? 'Рабочие дни, время открытия и исключения' : sub === 'Графики преподавателей' ? 'Назначения по филиалам, рабочие часы и недоступность' : 'Состав и параметры учебных групп'
    return <div className="settings-workspace"><div className="section-head padded"><div><h2>{title}</h2><p>{subtitle}</p></div>{sub === 'Группы' && <Button icon={<Plus size={17} />}>Новая группа</Button>}</div><div className="settings-toolbar-line"><Segmented items={['Часы филиалов', 'Графики преподавателей', 'Группы']} value={sub} onChange={setSub} />{sub === 'Группы' && <><label className="search-input"><MagnifyingGlass size={18} /><input placeholder="Поиск группы" /></label><label className="check-row"><input type="checkbox" /> Показывать завершённые</label></>}</div>{sub === 'Часы филиалов' && <div className="settings-list exact-settings-list">{[['Садовая', 'Пн - Сб · 09:00 - 21:00'], ['Петроградская', 'Пн - Вс · 10:00 - 20:00']].map((row) => <button key={row[0]}><span className="settings-list-icon"><Clock size={20} /></span><span><b>{row[0]}</b><small>{row[1]}</small></span><CaretRight size={18} /></button>)}</div>}{sub === 'Графики преподавателей' && <div className="settings-list exact-settings-list">{[['Анна Лебедева', 'Садовая · Пн, Ср, Пт · 12:00 - 20:00'], ['Илья Морозов', 'Садовая · Вт, Чт, Сб · 10:00 - 19:00']].map((row) => <button key={row[0]}><span className="settings-list-icon"><ChalkboardTeacher size={20} /></span><span><b>{row[0]}</b><small>{row[1]}</small></span><CaretRight size={18} /></button>)}</div>}{sub === 'Группы' && <div className="settings-list exact-settings-list"><button><span className="settings-list-icon"><UsersThree size={20} /></span><span><b>Группа «Ритм»</b><small>5 учеников · Сольфеджио · Садовая</small></span><Badge tone="success">Активна</Badge><CaretRight size={18} /></button></div>}</div>
  }

  if (section === 'Клиенты') {
    const crmAreas = ['Поля и категории', 'Варианты для полей', 'Бизнес-параметры', 'Воронки клиентов', 'Занятия и оплата', 'История версий']
    return <div className="settings-workspace crm-settings"><div className="crm-config-toolbar"><Field label="Область действия"><select><option>Вся школа</option><option>Садовая</option><option>Петроградская</option></select></Field><Badge tone="success"><CheckCircle size={14} /> Опубликовано · версия 12</Badge><Button variant="secondary" disabled>Сохранить черновик</Button><Button>Проверить и опубликовать</Button></div><div className="crm-settings-body"><nav>{crmAreas.map((item) => <button type="button" className={sub === item ? 'active' : ''} key={item} onClick={() => setSub(item)}><span>{item}</span><CaretRight size={16} /></button>)}</nav><section>{sub === 'Поля и категории' && <SettingsPane title="Поля форм и карточек" action="Добавить поле" rows={[['Структура и видимость полей', 'Название, тип, категория и показ в карточках'], ['Категории · 4', 'Добавить категорию'], ['Имя', 'Лид и ученик · Текст'], ['Телефон', 'Лид и ученик · Телефон'], ['Направления', 'Лид и ученик · Несколько вариантов']]} />}{sub === 'Варианты для полей' && <SettingsPane title="Наборы вариантов для полей" action="Добавить набор" rows={[['Значения списков и справочников', 'Один набор используется обеими карточками'], ['Рекламный источник', 'Лид и ученик · системный справочник'], ['Направления', '8 вариантов'], ['Уровень подготовки', '4 варианта']]} />}{sub === 'Бизнес-параметры' && <SettingsPane title="Безопасные бизнес-параметры" rows={[['Напоминание об оплате', '3 дн.']]} />}{sub === 'Воронки клиентов' && <div className="settings-center-action"><Button icon={<SlidersHorizontal size={18} />}>Настроить воронки лидов и учеников</Button></div>}{sub === 'Занятия и оплата' && <SettingsPane title="Занятия и оплата преподавателю" rows={[['Типы списания занятия', 'Цвет всегда сопровождается названием'], ['Типы оплаты преподавателю', 'Сотрудник всегда выбирает тип вручную']]} />}{sub === 'История версий' && <SettingsPane title="Неизменяемые версии" rows={[['Версия 12', 'Опубликована 14.08.2026'], ['Версия 11', 'Изменены поля карточки клиента'], ['Версия 10', 'Обновлены воронки клиентов']]} />}</section></div></div>
  }

  if (section === 'Продажи и оплаты') return <div className="settings-workspace"><div className="section-head padded"><div><h2>Продажи и оплаты</h2><p>Каталог абонементов</p></div><div className="page-actions"><label className="check-row"><input type="checkbox" /> Показать архив</label><Button icon={<Plus size={18} />}>Новый абонемент</Button></div></div><div className="package-grid padded top-none">{[['Старт', '4 занятия', '8 900 ₽'], ['Развитие', '8 занятий', '16 500 ₽'], ['Премиум', '12 занятий', '23 400 ₽']].map((item) => <button key={item[0]}><span><b>{item[0]}</b><Badge tone="success">Действует</Badge></span><strong>{item[2]}</strong><small>{item[1]} · срок 45 дней</small><span className="package-actions"><PencilSimple size={17} /> Изменить</span></button>)}</div></div>

  if (section === 'Пользователи и доступы') {
    const list = sub !== 'Доступы'
    return <div className="settings-workspace"><div className="section-head padded"><div><h2>Пользователи и доступы</h2><p>{sub === 'Доступы' ? 'Аккаунты, роли и персональные права' : sub === 'Сотрудники' ? 'Сотрудники школы' : 'Преподаватели и специализации'}</p></div>{list && <Button icon={<UserPlus size={18} />}>{sub === 'Сотрудники' ? 'Новый сотрудник' : 'Новый преподаватель'}</Button>}</div><div className="settings-toolbar-line"><Segmented items={['Доступы', 'Сотрудники', 'Преподаватели']} value={sub} onChange={setSub} />{list && <label className="search-input"><MagnifyingGlass size={18} /><input placeholder="Поиск" /></label>}</div>{sub === 'Доступы' ? <div className="access-layout"><SettingsPane title="Роли и персональные права" rows={[['Елена Смирнова', 'Администратор · индивидуальные права'], ['Олег Романов', 'Управляющий'], ['Анна Лебедева', 'Преподаватель']]} /></div> : <div className="table-shell embedded"><table><thead><tr><th>{sub === 'Сотрудники' ? 'Сотрудник' : 'Преподаватель'}</th><th>{sub === 'Сотрудники' ? 'Роль' : 'Специализации'}</th><th>Почта</th><th>Состояние</th><th /></tr></thead><tbody>{(sub === 'Сотрудники' ? [['Елена Смирнова', 'Администратор', 'elena@magicmusic.ru'], ['Олег Романов', 'Управляющий', 'o.romanov@magicmusic.ru']] : [['Анна Лебедева', 'Фортепиано, скрипка', 'a.lebedeva@magicmusic.ru'], ['Илья Морозов', 'Гитара', 'i.morozov@magicmusic.ru']]).map((row) => <tr key={row[0]}><td><span className="person-cell"><span className="avatar soft">{row[0].split(' ').map((v) => v[0]).join('')}</span><b>{row[0]}</b></span></td><td>{row[1]}</td><td>{row[2]}</td><td><Badge tone="success">Активен</Badge></td><td><Button variant="ghost" size="icon" title="Открыть"><CaretRight size={17} /></Button></td></tr>)}</tbody></table></div>}</div>
  }

  const dataTab = sub || 'Качество данных'
  return <div className="settings-workspace"><div className="section-head padded"><div><h2>Данные и обслуживание</h2><p>Контроль качества и запросы на удаление</p></div></div><div className="settings-toolbar-line"><Segmented items={['Качество данных', 'Запросы на удаление']} value={dataTab} onChange={setSub} /></div>{dataTab === 'Качество данных' ? <div className="data-quality-sections"><section className="surface"><div><h3>Очередь телефонов</h3><p>Проверка и исправление канонических номеров</p></div><strong>0</strong></section><section className="surface"><div><h3>Объединение лидов</h3><p>Поиск возможных дублей без удаления истории</p></div><strong>0</strong></section></div> : <div className="empty-state"><span><Archive size={24} /></span><b>Нет активных запросов</b><p>Запросы клиентов на удаление появятся здесь.</p></div>}</div>
}

function SettingsPane({ title, rows, action }: { title: string; rows: string[][]; action?: string }) {
  return <div className="settings-pane"><div className="section-head"><h3>{title}</h3>{action && <Button variant="secondary" size="sm" icon={<Plus size={16} />}>{action}</Button>}</div><div className="settings-list exact-settings-list">{rows.map((row) => <button type="button" key={row[0]}><span><b>{row[0]}</b><small>{row[1]}</small></span><CaretRight size={17} /></button>)}</div></div>
}

function ChatPage({ notify, role }: { notify: (message: string) => void; role: Role }) {
  const [message, setMessage] = useState('')
  const [sent, setSent] = useState<string[]>([])
  const [folder, setFolder] = useState('Лиды')
  const showFolders = !['client', 'teacher'].includes(role)
  const dialogsByFolder: Record<string, string[][]> = {
    'Лиды': [['София Крылова', 'Можно перенести занятие?', '12:36', '3'], ['Никита Орлов', 'Хочу записаться на гитару', '09:18', '1']],
    'Ученики': [['Анна Лебедева', 'Хорошо, подтверждаю', '11:04', ''], ['Родители группы «Ритм»', 'Концерт состоится в 18:00', 'Вчера', '']],
    'Архив': [['Павел Титов', 'Спасибо, всё получилось', '12 авг', '']],
  }
  const dialogs = showFolders ? dialogsByFolder[folder] : [['Команда филиала', 'Елена: перенесла занятие', '12:36', '3'], ['Анна Лебедева', 'Хорошо, подтверждаю', '11:04', '']]
  return <div className="chat-page">
    <aside className="chat-list">
      <div className="chat-title"><Button variant="ghost" size="icon" title="Профиль" target="profile.main"><UserCircle size={19} /></Button><h1>MagicMusic</h1><Button size="icon" title="Создать чат или канал"><Plus size={19} /></Button></div>
      <label className="search-input small"><MagnifyingGlass size={17} /><input placeholder="Поиск" /></label>
      {showFolders && <><Segmented items={['Лиды', 'Ученики', 'Архив']} value={folder} onChange={setFolder} /><label className="chat-branch-filter"><Buildings size={16} /><select aria-label="Филиал"><option>Все филиалы</option><option>Садовая</option><option>Петроградская</option></select></label></>}
      <small className="chat-list-section">{folder === 'Архив' ? 'Архив' : 'Диалоги'}</small>
      {dialogs.map((row, i) => <button type="button" className={i === 0 ? 'active' : ''} key={row[0]} onClick={() => openVisualScreen(row[0].includes('Команда') || row[0].includes('Родители') ? 'chat.group' : 'chat.dialog')}><span className="avatar soft">{row[0].slice(0, 2).toUpperCase()}</span><span><b>{row[0]}</b><small>{row[1]}</small></span><span className="chat-meta"><time>{row[2]}</time>{row[3] && <i>{row[3]}</i>}</span></button>)}
    </aside>
    <section className="conversation">
      <header><span className="avatar">КФ</span><button type="button" className="conversation-person" onClick={() => openVisualScreen('chat.group.edit')}><b>Команда филиала</b><small>6 участников · 4 в сети</small></button><div><Button variant="ghost" size="icon" title="Поиск" target="chat.search"><MagnifyingGlass size={19} /></Button><Button variant="ghost" size="icon" title="Меню" target="chat.group.edit"><DotsThree size={20} /></Button></div></header>
      <div className="messages"><div className="date-chip">Сегодня</div><div className="message incoming"><b>Елена Смирнова <time>12:31</time></b><p>Коллеги, занятие Матвея перенесено на понедельник. Аудитория уже изменена.</p></div><div className="message outgoing"><p>Спасибо. Я проверю, нет ли пересечений у преподавателя.</p><time>12:34 · прочитано</time></div><div className="message incoming"><b>Елена Смирнова <time>12:36</time></b><p>Проверила через анализатор, всё свободно.</p></div>{sent.map((item, i) => <div className="message outgoing" key={i}><p>{item}</p><time>сейчас · отправлено</time></div>)}</div>
      <form className="message-form" onSubmit={(e) => { e.preventDefault(); if (!message.trim()) return; setSent((v) => [...v, message]); setMessage(''); notify('Сообщение отправлено') }}><Button variant="ghost" size="icon" title="Прикрепить"><Plus size={20} /></Button><input value={message} onChange={(e) => setMessage(e.target.value)} placeholder="Напишите сообщение" /><Button size="icon" title="Отправить"><PaperPlaneTilt size={19} weight="fill" /></Button></form>
    </section>
  </div>
}

function TeacherStudentsPage({ setDrawer }: { setDrawer: (value: string) => void }) {
  void setDrawer
  return <div className="page"><PageHeader title="Ученики" /><div className="teacher-student-list">{clients.slice(0, 4).map((student, index) => <button type="button" className="teacher-student-row surface" key={student.name} onClick={() => openVisualScreen('teacher.student.card')}><span className="avatar soft">{student.name.split(' ').map((value) => value[0]).join('')}</span><span><b>{student.name}</b><small>{student.course}</small></span><Badge tone="gold">{7 + index * 2} занятий</Badge><CaretRight size={18} /></button>)}</div></div>
}

function ClientLessonsPage({ notify }: { notify: (message: string) => void }) {
  const [tab, setTab] = useState('Предстоящие')
  const rows = tab === 'История' ? [['8 августа', 'Фортепиано', '18:00', 'Завершено'], ['5 августа', 'Фортепиано', '18:00', 'Завершено']] : [['Сегодня', 'Фортепиано', '18:00', 'Запланировано'], ['19 августа', 'Фортепиано', '18:00', 'Запланировано'], ['22 августа', 'Фортепиано', '13:30', 'Запланировано']]
  return <div className="page client-page"><PageHeader title="Занятия" actions={<Button variant="ghost" size="icon" title="Обновить" onClick={() => notify('Занятия обновлены')}><ArrowClockwise size={18} /></Button>} /><Segmented items={['Предстоящие', 'История', 'Задания']} value={tab} onChange={(value) => value === 'Задания' ? openVisualScreen('client.homework') : setTab(value)} />{tab === 'Задания' ? <div className="empty-state surface"><span><CheckSquare size={24} /></span><b>Нет новых заданий</b></div> : <div className="lesson-history surface">{rows.map((row, index) => <button type="button" key={`${row[0]}-${index}`} onClick={() => openVisualScreen('client.lesson.details')}><span><CalendarBlank size={18} /></span><span><b>{row[1]}</b><small>{row[0]} · {row[2]}</small><small>Преподаватель: Анна Лебедева</small><small>Филиал: Садовая · Аудитория 2 · 60 мин</small></span><Badge tone={row[3] === 'Завершено' ? 'success' : index === 0 ? 'gold' : 'neutral'}>{row[3]}</Badge></button>)}</div>}</div>
}

function ClientSubscriptionPage() {
  const [tab, setTab] = useState('Абонемент')
  const metrics = [['Часы', '4 из 8'], ['Оплачено', '16 500 ₽'], ['Долг', '0 ₽'], ['Ожидает подтверждения', '0 ₽'], ['Переплата', '0 ₽'], ['Следующий платёж', 'Нет']]
  return <div className="page client-page"><PageHeader title="Абонемент" /><Segmented items={['Абонемент', 'Оплаты']} value={tab} onChange={setTab} />{tab === 'Абонемент' ? <button type="button" className="subscription-card surface" onClick={() => openVisualScreen('client.subscription')}><div className="subscription-top"><span><MusicNotes size={26} weight="fill" /></span><div><Badge tone="success">Осталось: 4 ч</Badge><h2>РАЗВИТИЕ · 8 ЗАНЯТИЙ</h2><p>Действует до: 28.09.2026</p></div></div><div className="subscription-metrics">{metrics.map((metric) => <span key={metric[0]}><small>{metric[0]}</small><b>{metric[1]}</b></span>)}</div></button> : <div className="payment-list surface">{[['16 500 ₽', '14.08.2026', 'Карта', 'Абонемент «Развитие»'], ['8 900 ₽', '28.06.2026', 'Наличные', 'Абонемент «Старт»']].map((payment) => <button type="button" key={payment[1]} onClick={() => openVisualScreen('client.payment.details')}><span><b>{payment[0]}</b><small>{payment[1]} · {payment[2]}</small></span><span>{payment[3]}</span></button>)}</div>}</div>
}

function ClientProfilePage({ notify }: { notify: (message: string) => void }) {
  return <div className="page client-page"><PageHeader title="Изменить профиль" /><section className="surface profile-card exact-profile"><button type="button" className="profile-photo" onClick={() => openVisualScreen('profile.avatar')}><span className="avatar huge">АВ</span><small>Сменить фото</small></button><div className="form-grid"><Field label="Имя (обязательно)"><input defaultValue="Алиса" /></Field><Field label="Фамилия (необязательно)"><input defaultValue="Воронцова" /></Field><Field label="Номер телефона"><input defaultValue="+7 999 418-22-17" /></Field><Field label="Роль"><input value="Клиент" readOnly /></Field></div><button type="button" className="profile-link" onClick={() => openVisualScreen('profile.edit')}><CalendarBlank size={20} /><span><b>День рождения</b><small>12.03.2010</small></span><CaretRight size={18} /></button><button type="button" className="profile-link" onClick={() => openVisualScreen('profile.auth-methods')}><LockKey size={20} /><span><b>Способы входа</b><small>Пароль и код из письма</small></span><CaretRight size={18} /></button><button type="button" className="profile-link" onClick={() => openVisualScreen('profile.legal')}><FileText size={20} /><span><b>Юридические документы</b><small>Политика, соглашение и удаление данных</small></span><CaretRight size={18} /></button><Button onClick={() => notify('Изменения сохранены')}>Сохранить</Button></section></div>
}

function ComponentsPage({ setModal, setDrawer, notify }: { setModal: (name: ModalName) => void; setDrawer: (value: string) => void; notify: (message: string) => void }) {
  const [tab, setTab] = useState('Кнопки')
  return <div className="page components-page"><PageHeader eyebrow="Дизайн-стенд" title="Компоненты интерфейса" description="Базовые элементы и их состояния до переноса в приложение" actions={<Badge tone="gold"><Sparkle size={14} /> Светлая система</Badge>} /><div className="component-nav">{['Кнопки', 'Поля', 'Состояния', 'Таблицы', 'Окна'].map((item) => <button className={tab === item ? 'active' : ''} key={item} onClick={() => setTab(item)}>{item}</button>)}</div>{tab === 'Кнопки' && <div className="component-sections"><ComponentBlock title="Основные действия" note="Одно главное действие на смысловой блок"><Button>Основная</Button><Button variant="secondary">Дополнительная</Button><Button variant="ghost">Нейтральная</Button><Button variant="danger">Опасная</Button><Button variant="quiet">Текстовая</Button></ComponentBlock><ComponentBlock title="Размеры и значки"><Button size="lg" icon={<Plus size={19} />}>Крупная</Button><Button icon={<Plus size={18} />}>Средняя</Button><Button size="sm" icon={<Plus size={16} />}>Малая</Button><Button size="icon" title="Добавить"><Plus size={19} /></Button></ComponentBlock><ComponentBlock title="Состояния"><Button disabled>Недоступна</Button><Button icon={<ArrowClockwise className="spin" size={18} />}>Загрузка</Button><Button variant="secondary" icon={<Check size={18} />}>Выполнено</Button></ComponentBlock></div>}{tab === 'Поля' && <div className="component-sections"><ComponentBlock title="Текст и выбор"><Field label="Имя клиента"><input placeholder="Введите имя" /></Field><Field label="Филиал"><select><option>Садовая</option><option>Петроградская</option></select></Field><Field label="Почта" hint="Сюда придёт приглашение"><input placeholder="name@example.ru" /></Field><Field label="Пароль" error="Не меньше 8 символов"><input type="password" defaultValue="1234" /></Field></ComponentBlock><ComponentBlock title="Выбор состояния"><label className="check-row"><input type="checkbox" defaultChecked /> Флажок</label><label className="check-row"><input type="radio" name="sample" defaultChecked /> Первый вариант</label><label className="check-row"><input type="radio" name="sample" /> Второй вариант</label><label className="switch-row"><span>Переключатель</span><input type="checkbox" defaultChecked /><i /></label></ComponentBlock></div>}{tab === 'Состояния' && <div className="component-sections"><ComponentBlock title="Статусы"><Badge tone="success">Активен</Badge><Badge tone="info">В работе</Badge><Badge tone="warning">Нужно внимание</Badge><Badge tone="danger">Ошибка</Badge><Badge tone="neutral">Архив</Badge></ComponentBlock><ComponentBlock title="Сообщения"><div className="alert success"><CheckCircle size={20} /><span><b>Данные сохранены</b><small>Изменения уже доступны сотрудникам.</small></span></div><div className="alert warning"><WarningCircle size={20} /><span><b>Найдено пересечение</b><small>Преподаватель занят в это время.</small></span></div><div className="alert danger"><Warning size={20} /><span><b>Не удалось сохранить</b><small>Проверьте подключение и повторите.</small></span></div></ComponentBlock></div>}{tab === 'Таблицы' && <div className="component-sections"><ComponentBlock title="Строки и действия"><div className="mini-table"><div className="mini-head"><span>Клиент</span><span>Состояние</span><span /></div>{clients.slice(0, 3).map((item) => <button key={item.name} onClick={() => setDrawer('client')}><span><b>{item.name}</b><small>{item.course}</small></span><Badge tone={item.state === 'Активен' ? 'success' : 'danger'}>{item.state}</Badge><DotsThree size={18} /></button>)}</div></ComponentBlock><ComponentBlock title="Пустое состояние"><div className="empty-state"><span><MagnifyingGlass size={25} /></span><b>Ничего не найдено</b><p>Измените запрос или сбросьте фильтры.</p><Button variant="secondary">Сбросить фильтры</Button></div></ComponentBlock></div>}{tab === 'Окна' && <div className="component-sections"><ComponentBlock title="Диалоги и панели"><Button onClick={() => setModal('lesson')}>Форма занятия</Button><Button variant="secondary" onClick={() => setModal('task')}>Новая задача</Button><Button variant="secondary" onClick={() => setDrawer('sample')}>Боковая панель</Button><Button variant="ghost" onClick={() => notify('Это пример короткого уведомления')}>Уведомление</Button></ComponentBlock></div>}</div>
}

function ComponentBlock({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return <section className="component-block surface"><div><h2>{title}</h2>{note && <p>{note}</p>}</div><div className="component-demo">{children}</div></section>
}

function ModalFrame({ title, subtitle, children, footer, onClose, wide = false }: { title: string; subtitle?: string; children: ReactNode; footer: ReactNode; onClose: () => void; wide?: boolean }) {
  return <div className="modal-backdrop" onMouseDown={onClose}><section className={cn('modal', wide && 'modal-wide')} role="dialog" aria-modal="true" onMouseDown={(e) => e.stopPropagation()}><header><div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div><Button variant="ghost" size="icon" title="Закрыть" onClick={onClose}><X size={20} /></Button></header><div className="modal-body">{children}</div><footer>{footer}</footer></section></div>
}

function LessonModal({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  const [status, setStatus] = useState<'idle' | 'checking' | 'conflict' | 'safe'>('idle')
  const check = () => {
    setStatus('checking')
    window.setTimeout(() => setStatus('conflict'), 650)
  }
  const applySuggestion = () => {
    setStatus('checking')
    window.setTimeout(() => setStatus('safe'), 650)
  }
  return <ModalFrame wide title="Новое занятие" onClose={onClose} footer={<><Button variant="ghost" onClick={onClose}>Отмена</Button><Button onClick={() => { notify('Занятие создано'); onClose() }}>Создать</Button></>}>
    <div className={cn('lesson-form-layout', status === 'idle' && 'single')}>
      <div className="lesson-fields">
        <div className="form-grid">
          <Field label="Клиент *"><select><option>Матвей Соколов</option><option>Алиса Воронцова</option></select></Field>
          <Field label="Филиал *"><select><option>Садовая</option><option>Петроградская</option></select></Field>
          <Field label="Аудитория *"><select><option>Аудитория 1</option><option>Аудитория 3</option></select></Field>
          <Field label="Преподаватель *"><select><option>Илья Морозов</option><option>Денис Волков</option></select></Field>
          <Field label="Дата"><input type="date" defaultValue="2026-08-15" /></Field>
          <Field label="Время"><input type="time" defaultValue="10:30" /></Field>
          <Field label="Длительность *"><select><option>60 минут</option><option>45 минут</option><option>90 минут</option></select></Field>
        </div>
        <Button variant="secondary" className="full" icon={<ShieldCheck size={18} />} onClick={check}>{status === 'checking' ? 'Проверяем…' : 'Проверить конфликты и варианты'}</Button>
        <label className="switch-row"><span><b>Пробное занятие</b><small>Не зависит от типа клиента и способа списания</small></span><input type="checkbox" /><i /></label>
        <h3 className="form-section-title">Результат и расчёты</h3>
        <div className="form-grid">
          <Field label="Автозавершение *"><select><option>Успешно завершить</option></select></Field>
          <Field label="Тип списания *"><select><option>Стандартное списание</option><option>Без списания</option></select></Field>
          <Field label="Правило оплаты преподавателю *"><select><option>Стандартная ставка</option><option>Фиксированная сумма</option></select></Field>
          <Field label="Источник средств *"><select><option>С абонемента</option><option>С личного счёта</option><option>Без списания</option></select></Field>
          <Field label="Абонемент *"><select><option>«Развитие», осталось 4 ч</option></select></Field>
        </div>
        <div className="calculation-preview"><b>Расчёты перед созданием</b><span>Тип занятия <strong>Обычное</strong></span><span>Списание клиента <strong>1 ч</strong></span><span>Оплата преподавателю <strong>По стандартной ставке</strong></span></div>
      </div>
      {status !== 'idle' && <aside className="conflict-inspector">
        <div className="inspector-head"><span className={cn('inspector-icon', status)}>{status === 'checking' ? <ArrowClockwise className="spin" /> : status === 'safe' ? <CheckCircle weight="fill" /> : <WarningCircle weight="fill" />}</span><div><h3>{status === 'checking' ? 'Проверяем расписание' : status === 'safe' ? 'Конфликтов нет' : 'Найдены конфликты'}</h3><p>15.08.2026 · 10:30 · 60 мин</p></div></div>
        {status === 'conflict' && <><div className="conflict-group"><div><Badge tone="danger">Аудитория</Badge><b>Аудитория уже занята</b></div><p>Есть другое занятие в выбранное время.</p></div><div className="suggestion-head"><span>Подходящие варианты</span></div>{[['№1 · Свободная аудитория в то же время', 'Аудитория 3 · Илья Морозов · 15.08 · 10:30'], ['№2 · Ближайшее свободное время', 'Аудитория 1 · Илья Морозов · 15.08 · 11:30'], ['№3 · Преподаватель и аудитория', 'Аудитория 3 · Денис Волков · 15.08 · 10:30']].map((item) => <button type="button" className="suggestion" key={item[0]} onClick={applySuggestion}><span><b>{item[0]}</b><small>{item[1]}</small></span><CaretRight size={18} /></button>)}</>}
        {status === 'safe' && <div className="safe-list"><span><Check size={16} /> Все выбранные ресурсы доступны</span></div>}
      </aside>}
    </div>
  </ModalFrame>
}

function RecurringModal({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  const [review, setReview] = useState(false)
  const [checked, setChecked] = useState(false)
  return <ModalFrame wide title={review ? 'Проверка постоянного расписания' : 'Новое постоянное расписание'} subtitle={review ? 'Добавьте отдельный набор дней для другого педагога или аудитории' : 'Можно создать несколько дней и занятий одной командой'} onClose={onClose} footer={review ? <><Button variant="ghost" onClick={() => setReview(false)}>Назад</Button><Button onClick={() => checked ? (notify('Расписание создано'), onClose()) : setChecked(true)}>{checked ? 'Создать' : 'Проверить и создать'}</Button></> : <><Button variant="ghost" onClick={onClose}>Отмена</Button><Button onClick={() => setReview(true)}>Создать</Button></>}>
    {!review ? <div className="recurring-layout"><div className="form-grid"><Field label="Название"><input defaultValue="Индивидуальные занятия" /></Field><Field label="Абонемент"><select><option>«Развитие», осталось 4 ч</option></select></Field><Field label="Филиал *" hint="Постоянная серия всегда привязана к филиалу"><select><option>Садовая</option></select></Field></div><div className="weekday-picker"><span>Дни недели</span>{['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'].map((day, index) => <label key={day}><input type="checkbox" defaultChecked={index === 1 || index === 4} /><i>{day}</i></label>)}</div><div className="form-grid"><Field label="Время"><input type="time" defaultValue="17:00" /></Field><Field label="Длительность"><select><option>60 мин</option><option>45 мин</option><option>90 мин</option></select></Field><Field label="Занятий в день" hint="Идут подряд"><select><option>1</option><option>2</option><option>3</option><option>4</option></select></Field><Field label="Педагог *"><select><option>Анна Лебедева</option></select></Field><Field label="Аудитория *"><select><option>Аудитория 2</option></select></Field><Field label="Тип списания *"><select><option>Стандартное списание</option></select></Field><Field label="Оплата преподавателю *"><select><option>Стандартная ставка</option></select></Field><Field label="Дата начала"><input type="date" defaultValue="2026-09-01" /></Field></div><label className="switch-row"><span>Без даты окончания</span><input type="checkbox" defaultChecked /><i /></label><Field label="Описание"><textarea rows={3} placeholder="Пожелания клиента и важные условия" /></Field></div> : <div className="plan-review"><div className="plan-row-card"><span><b>Строка 1 · Вт, Пт · 17:00</b><small>Анна Лебедева · Аудитория 2 · Садовая · 60 мин</small></span><Button variant="ghost" size="icon" title="Изменить строку 1"><PencilSimple size={18} /></Button></div><Button variant="secondary" icon={<Plus size={17} />}>Добавить другой набор дней</Button>{checked && <div className="alert success"><CheckCircle size={20} /><span><b>Ограничений не найдено</b><small>Все строки можно сохранить.</small></span></div>}</div>}
  </ModalFrame>
}

function TaskModal({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  const [audience, setAudience] = useState('Сотрудники')
  const [reminder, setReminder] = useState(false)
  return <div className="task-sheet-backdrop" onMouseDown={onClose}><aside className="task-sheet" role="dialog" aria-modal="true" aria-label="Новая задача" onMouseDown={(event) => event.stopPropagation()}><header><span className="client-header-icon"><ListChecks size={22} /></span><div><h2>Новая задача</h2><p>Срок, получатели и напоминание</p></div><Button variant="ghost" size="icon" title="Закрыть" onClick={onClose}><X size={21} /></Button></header><div className="task-sheet-body"><div className="form-stack"><Field label="Название"><input autoFocus /></Field><Field label="Приоритет"><select><option>Обычный</option><option>Высокий</option><option>Низкий</option></select></Field><Field label="Описание"><textarea rows={3} /></Field><label className="switch-row"><span>На весь день</span><input type="checkbox" defaultChecked /><i /></label><div className="form-grid task-dates"><Field label="Начало"><input type="date" defaultValue="2026-08-16" /></Field><Field label="Окончание"><input type="date" defaultValue="2026-08-16" /></Field></div><h3 className="form-section-title">Кому</h3><Segmented items={['Сотрудники', 'Один филиал', 'Вся школа']} value={audience} onChange={setAudience} />{audience !== 'Вся школа' && <Field label={audience === 'Сотрудники' ? 'Сотрудник' : 'Филиал'}><select><option>{audience === 'Сотрудники' ? 'Елена Смирнова' : 'Садовая'}</option></select></Field>}<Button variant="secondary" icon={<UserPlus size={17} />}>Добавить получателя</Button><div className="recipient-preview"><b>Кто получит задачу</b><strong>Сейчас получат: 1</strong><span>Елена Смирнова: лично; сейчас 1</span></div><label className="switch-row"><span><b>Напомнить в приложении</b><small>Можно выбрать точные дату и время</small></span><input type="checkbox" checked={reminder} onChange={(event) => setReminder(event.target.checked)} /><i /></label>{reminder && <Field label="Напомнить"><input type="datetime-local" defaultValue="2026-08-16T09:00" /></Field>}</div></div><footer><Button variant="ghost" onClick={onClose}>Отмена</Button><Button onClick={() => { notify('Задача создана'); onClose() }}>Создать</Button></footer></aside></div>
}

function TaskEditModal({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  const [audience, setAudience] = useState('Сотрудники')
  const [reminder, setReminder] = useState(true)
  return <div className="task-sheet-backdrop" onMouseDown={onClose}><aside className="task-sheet" role="dialog" aria-modal="true" aria-label="Изменить задачу" onMouseDown={(event) => event.stopPropagation()}><header><span className="client-header-icon"><PencilSimple size={22} /></span><div><h2>Изменить задачу</h2><p>Срок, получатели и напоминание</p></div><Button variant="ghost" size="icon" title="Закрыть" onClick={onClose}><X size={21} /></Button></header><div className="task-sheet-body"><div className="form-stack"><Field label="Название"><input autoFocus defaultValue="Позвонить по заявке с сайта" /></Field><Field label="Приоритет"><select defaultValue="Высокий"><option>Обычный</option><option>Высокий</option><option>Низкий</option></select></Field><Field label="Описание"><textarea rows={3} defaultValue="Проверить детали и выполнить задачу в указанный срок." /></Field><label className="switch-row"><span>На весь день</span><input type="checkbox" defaultChecked /><i /></label><div className="form-grid task-dates"><Field label="Начало"><input type="date" defaultValue="2026-08-16" /></Field><Field label="Окончание"><input type="date" defaultValue="2026-08-16" /></Field></div><h3 className="form-section-title">Кому</h3><Segmented items={['Сотрудники', 'Один филиал', 'Вся школа']} value={audience} onChange={setAudience} />{audience !== 'Вся школа' && <Field label={audience === 'Сотрудники' ? 'Сотрудник' : 'Филиал'}><select><option>{audience === 'Сотрудники' ? 'Елена Смирнова' : 'Садовая'}</option></select></Field>}<Button variant="secondary" icon={<UserPlus size={17} />}>Добавить получателя</Button><div className="recipient-preview"><b>Кто получит задачу</b><strong>Сейчас получат: 1</strong><span>Елена Смирнова: лично; сейчас 1</span></div><label className="switch-row"><span><b>Напомнить в приложении</b><small>Можно выбрать точные дату и время</small></span><input type="checkbox" checked={reminder} onChange={(event) => setReminder(event.target.checked)} /><i /></label>{reminder && <Field label="Напомнить"><input type="datetime-local" defaultValue="2026-08-16T09:00" /></Field>}</div></div><footer><Button variant="ghost" onClick={onClose}>Отмена</Button><Button onClick={() => { notify('Изменения сохранены'); onClose() }}>Сохранить</Button></footer></aside></div>
}

function ClientModal({ kind, onClose, notify }: { kind: 'lead' | 'student'; onClose: () => void; notify: (message: string) => void }) {
  const title = kind === 'lead' ? 'Новый лид' : 'Новый ученик'
  return <ModalFrame title={title} subtitle={kind === 'student' ? 'Карточка будет сразу добавлена в воронку' : undefined} onClose={onClose} footer={<><Button variant="ghost" onClick={onClose}>Отмена</Button><Button onClick={() => { notify(kind === 'lead' ? 'Лид создан' : 'Ученик создан'); onClose() }}>Создать</Button></>}><div className="form-stack"><Field label="Имя *"><input /></Field><Field label="Фамилия *"><input /></Field><Field label="Телефон *"><input placeholder="+7 (___) ___ __ __" /></Field><Field label="Филиал *"><select><option>Садовая</option><option>Петроградская</option></select></Field><Field label="Этап воронки *"><select><option>{kind === 'lead' ? 'В процессе' : 'Обучаются'}</option></select></Field><Field label="Рекламный источник *"><select><option>Сайт</option><option>Рекомендация</option></select></Field></div></ModalFrame>
}

function VersionModal({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  return <ModalFrame title="Обновления" subtitle="Текущая версия 1.5.14+194" onClose={onClose} footer={<><Button variant="ghost" onClick={onClose}>Позже</Button><Button onClick={() => { notify('Обновление начнётся после закрытия окон'); onClose() }}>Обновить и перезапустить</Button></>}><div className="version-content"><div className="update-banner"><span><DownloadSimple size={23} /></span><div><Badge tone="gold">Доступно обновление</Badge><h3>Версия 1.5.15+201</h3><p>Готова к установке. Приложение перезапустится автоматически.</p></div></div><div className="release-list"><article><span>1.5.15</span><div><b>Расписание и обновления</b><ul><li>Улучшена проверка конфликтов при создании занятий.</li><li>Версия приложения всегда видна слева внизу.</li><li>Исправлены понятные сообщения при ошибках загрузки.</li></ul></div></article><article><span>1.5.14</span><div><b>Оплаты и абонементы</b><ul><li>Добавлено безопасное редактирование назначенных оплат.</li><li>Выданные абонементы можно пересчитать перед сохранением.</li></ul></div></article></div></div></ModalFrame>
}

function CommandModal({ onClose, navigate, title = 'Открыть раздел' }: { onClose: () => void; navigate: (route: RouteKey) => void; title?: string }) {
  const [query, setQuery] = useState('')
  const items = (Object.entries(routeLabels) as [RouteKey, string][]).filter(([, label]) => label.toLowerCase().includes(query.toLowerCase()))
  return <div className="modal-backdrop command-backdrop" onMouseDown={onClose}><section className="command-modal" onMouseDown={(e) => e.stopPropagation()}><div className="command-search"><MagnifyingGlass size={21} /><input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder={title} /><kbd>Esc</kbd></div><div className="command-results"><small>Разделы</small>{items.map(([key, label]) => <button type="button" key={key} onClick={() => { navigate(key); onClose() }}><span><FileText size={18} /></span>{label}<kbd>↵</kbd></button>)}</div></section></div>
}

function DrawerFrame({ title, subtitle, onClose, children }: { title: string; subtitle?: string; onClose: () => void; children: ReactNode }) {
  return <div className="drawer-backdrop" onMouseDown={onClose}><aside className="drawer" onMouseDown={(e) => e.stopPropagation()}><header><div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div><Button variant="ghost" size="icon" onClick={onClose}><X size={20} /></Button></header><div className="drawer-body">{children}</div></aside></div>
}

function LegacyClientWorkspacePage({ kind, onClose, setModal, notify }: { kind: 'lead' | 'student'; onClose: () => void; setModal: (name: ModalName) => void; notify: (message: string) => void }) {
  const sections = kind === 'student' ? ['Обзор', 'Занятия', 'Оплаты', 'Абонементы', 'Прогресс', 'История и задачи', 'Контакты', 'Документы'] : ['Обзор', 'Занятия', 'Абонементы', 'Прогресс', 'История и задачи', 'Контакты', 'Документы']
  const [section, setSection] = useState('Обзор')
  const isLead = kind === 'lead'
  let content: ReactNode
  if (section === 'Обзор') {
    content = <div className="client-overview-form"><h3>Клиент</h3><div className="form-grid"><Field label="Этап воронки"><select><option>{isLead ? 'В процессе' : 'Обучаются'}</option></select></Field><Field label="Имя"><input defaultValue={isLead ? 'София' : 'Алиса'} /></Field><Field label="Фамилия"><input defaultValue={isLead ? 'Крылова' : 'Воронцова'} /></Field><Field label="Телефон"><input defaultValue={isLead ? '+7 915 208-44-63' : '+7 999 418-22-17'} /></Field><Field label="Электронная почта"><input defaultValue={isLead ? '' : 'alisa@example.ru'} /></Field><Field label="Основной филиал"><select><option>Садовая</option></select></Field><Field label="Рекламный источник"><select><option>{isLead ? 'Сайт' : 'Рекомендация'}</option></select></Field><Field label="Ответственный"><select><option>Елена Смирнова</option></select></Field></div><h3>Параметры клиента</h3><div className="form-grid"><Field label="Возраст"><input value={isLead ? '' : '16'} readOnly /></Field><Field label="Направления"><input value={isLead ? 'Вокал' : 'Фортепиано'} readOnly /></Field></div></div>
  } else if (section === 'Занятия') {
    content = <div className="client-lessons-section"><div className="section-head"><div><h3>Постоянное расписание</h3><p>Действующие и завершённые планы занятий</p></div><Button icon={<Plus size={17} />} onClick={() => setModal('recurring')}>Добавить расписание</Button></div><div className="empty-state compact"><span><CalendarBlank size={24} /></span><b>Постоянных расписаний пока нет</b></div><div className="calendar-expansion"><b>Календарь занятий</b><span>Месяц, неделя и день по этому клиенту</span><CaretRight size={18} /></div></div>
  } else if (section === 'Оплаты' && !isLead) {
    content = <div className="workspace-placeholder"><div className="section-head"><div><h3>Оплаты и личный счёт</h3><p>Платежи неизменяемы; исправления проводятся отдельной операцией.</p></div><Button icon={<Plus size={17} />} onClick={() => notify('Открыта форма оплаты')}>Добавить оплату</Button></div><div className="payment-list"><div><span><b>16 500 ₽</b><small>14.08.2026 · Карта</small></span><span>Абонемент «Развитие»</span></div></div></div>
  } else if (section === 'Абонементы') {
    content = <div className="workspace-placeholder"><div className="section-head"><h3>Абонементы</h3><Button icon={<Plus size={17} />}>{isLead ? 'Выдать абонемент' : 'Выдать абонемент'}</Button></div>{isLead ? <div className="empty-state compact"><span><CreditCard size={24} /></span><b>Абонемент ещё не выдан</b></div> : <div className="subscription-metrics">{[['Всего', '8'], ['Использовано', '4'], ['Зарезервировано', '0'], ['Оплачено', '8'], ['Доступно', '4'], ['Долг', 'Нет']].map((metric) => <span key={metric[0]}><small>{metric[0]}</small><b>{metric[1]}</b></span>)}</div>}</div>
  } else {
    content = <div className="empty-state compact"><span><FileText size={24} /></span><b>{section === 'Документы' ? 'Документов пока нет' : `Раздел «${section}»`}</b>{section === 'Документы' && <p>Поддерживаемые документы появятся в этом разделе.</p>}</div>
  }
  return <section className="client-workspace"><header><span className="client-header-icon">{isLead ? <UserCircle size={22} /> : <GraduationCap size={22} />}</span><span><h2>{isLead ? 'София Крылова' : 'Алиса Воронцова'}</h2><small><span className="client-state-dot" />Клиент · {isLead ? 'Лид · В процессе' : 'Ученик · Баланс: 0 ₽'}</small></span><Button variant="ghost" size="icon" title="Назад" onClick={onClose}><CaretLeft size={24} /></Button></header><div className="client-workspace-body"><aside><div className="section-jump-card">{sections.map((item) => <button type="button" className={section === item ? 'active' : ''} key={item} onClick={() => setSection(item)}>→ {item}</button>)}</div></aside><main><section className="surface client-section"><div className="section-head"><div><h2>{section}</h2></div></div>{content}</section></main></div><footer>{isLead && <Button variant="secondary">Прикрепить к ученику</Button>}<Button variant="secondary" onClick={() => notify('Открыто расписание клиента')}>Открыть в расписании</Button><Button variant="ghost" onClick={onClose}>Назад</Button><Button onClick={() => notify('Изменения сохранены')}>Сохранить</Button></footer></section>
}

function ClientWorkspacePage({ kind, onClose, setModal, notify }: { kind: 'lead' | 'student'; onClose: () => void; setModal: (name: ModalName) => void; notify: (message: string) => void }) {
  const isLead = kind === 'lead'
  const sections = [
    ['overview', 'Обзор', AddressBook],
    ['lessons', 'Занятия', CalendarBlank],
    ...(!isLead ? [['payments', 'Оплаты', Receipt] as const] : []),
    ['subscriptions', 'Абонементы', CreditCard],
    ['progress', 'Прогресс', TrendUp],
    ['history_tasks', 'История и задачи', ListChecks],
    ['contacts', 'Контакты', UsersThree],
    ['documents', 'Документы', FileText],
  ] as const
  const [activeSection, setActiveSection] = useState('overview')
  const [historyTab, setHistoryTab] = useState('Задачи')

  const jumpTo = (id: string) => {
    setActiveSection(id)
    document.getElementById(`client-section-${id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const card = (id: string, title: string, Icon: typeof AddressBook, body: ReactNode, className?: string) => (
    <section id={`client-section-${id}`} className={cn('surface client-canvas-card', className)}>
      <header><Icon size={20} /><h2>{title}</h2></header>
      <div className="client-canvas-card-body">{body}</div>
    </section>
  )

  const overview = card('overview', 'Обзор', AddressBook, <>
    <section className="client-note-block"><div className="section-head"><div><h3>Заметка о клиенте</h3></div></div><textarea rows={3} placeholder="Общий контекст для администраторов и руководителей" /><div><small>Заметка пока не заполнена</small><Button variant="secondary" size="sm" disabled>Сохранить заметку</Button></div></section>
    <div className="client-form-block"><h3>Клиент</h3><div className="form-grid"><Field label="Статус"><select><option>{isLead ? 'В процессе' : 'Обучается'}</option></select></Field><Field label="Имя"><input defaultValue={isLead ? 'София' : 'Алиса'} /></Field><Field label="Фамилия"><input defaultValue={isLead ? 'Крылова' : 'Воронцова'} /></Field><Field label="Телефон"><input defaultValue={isLead ? '+7 915 208-44-63' : '+7 999 418-22-17'} /></Field><Field label="Электронная почта"><input defaultValue={isLead ? '' : 'alisa@example.ru'} /></Field><Field label="Основной филиал"><select><option>Садовая</option></select></Field><Field label="Рекламный источник"><select><option>{isLead ? 'Сайт' : 'Рекомендация'}</option></select></Field></div></div>
    <div className="client-form-block"><h3>Параметры клиента</h3><div className="form-grid"><Field label="Ответственный"><select><option>Елена Смирнова</option></select></Field><Field label="Возраст"><input value={isLead ? '' : '16'} readOnly /></Field><Field label="Направления"><div className="chip-input"><span>{isLead ? 'Вокал' : 'Фортепиано'}</span><button type="button" title="Изменить направления" onClick={() => openVisualScreen('settings.crm.fields')}><PencilSimple size={15} /></button></div></Field><label className="switch-row inline-switch"><span>Чёрный список</span><input type="checkbox" /><i /></label></div><button type="button" className="client-expansion" onClick={() => openVisualScreen('settings.crm.fields')}><SlidersHorizontal size={18} /><span><b>Дополнительные поля</b><small>Пользовательские данные клиента и ученика</small></span><CaretRight size={18} /></button></div>
    {!isLead && <div className="client-info-grid"><section className="info-panel"><h3>Финансы</h3><dl><div><dt>Всего оплачено</dt><dd>16 500 ₽</dd></div><div><dt>Списано за уроки</dt><dd>8 250 ₽</dd></div><div><dt>Баланс</dt><dd>8 250 ₽</dd></div></dl></section><section className="info-panel"><h3>Обращение</h3><dl><div><dt>Дата обращения</dt><dd>12.08.2026</dd></div><div><dt>Дата визита</dt><dd>15.08.2026</dd></div></dl></section></div>}
    {isLead && <div className="client-info-grid"><section className="info-panel"><h3>Обращение</h3><dl><div><dt>Дата обращения</dt><dd>12.08.2026</dd></div><div><dt>Дата визита</dt><dd>15.08.2026</dd></div></dl></section><section className="info-panel"><h3>Связи и активность</h3><p>1 пробное занятие, связанных учеников нет</p></section><section className="info-panel full"><h3>Кандидаты на связь</h3><p>Подходящих карточек учеников не найдено</p></section></div>}
  </>, 'client-card-overview')

  const contacts = card('contacts', 'Контакты', UsersThree, <div className="contact-stack"><div className="section-head"><div><h3>Семья</h3><p>Семья не указана</p></div><Button variant="secondary" size="sm" icon={<Plus size={16} />} target="clients.contact.create">Добавить</Button></div><div className="contact-divider" /><div className="section-head"><div><h3>Контактные лица</h3><p>Контактные лица не указаны</p></div><Button variant="quiet" size="sm" icon={<Plus size={16} />}>Добавить контактное лицо</Button></div><div className="contact-divider" /><div className="section-head"><div><h3>Доступ в приложение</h3><p>Связанных аккаунтов пока нет</p></div>{!isLead && <Button variant="secondary" size="sm">Пригласить</Button>}</div>{isLead && <div className="linked-account-row"><span><b>Найден аккаунт с тем же телефоном</b><small>sofia@example.ru</small></span><Button variant="quiet" size="sm">Связать</Button></div>}</div>, 'client-card-contacts')

  const lessonsSection = card('lessons', 'Занятия', CalendarBlank, <div className="client-lessons-section"><div className="section-head"><div><h3>Постоянное расписание</h3><p>Действующие и завершённые планы занятий</p></div><Button icon={<Plus size={17} />} onClick={() => setModal('recurring')}>Добавить расписание</Button></div><div className="empty-state compact"><span><CalendarBlank size={24} /></span><b>Постоянных расписаний пока нет</b></div><button type="button" className="calendar-expansion" onClick={() => openVisualScreen('schedule.week')}><b>Календарь занятий</b><span>Месяц, неделя и день по этому клиенту</span><CaretRight size={18} /></button></div>)

  const payments = !isLead ? card('payments', 'Оплаты', Receipt, <div className="workspace-placeholder"><div className="section-head"><div><h3>Оплаты и личный счёт</h3><p>Исправления сохраняют исходную запись и историю пересчёта</p></div><Button icon={<Plus size={17} />} onClick={() => openVisualScreen('clients.payment.create')}>Добавить оплату</Button></div><div className="payment-table"><div><span><b>16 500 ₽</b><small>14.08.2026 · Безналичная оплата</small></span><span>Абонемент «Развитие»</span><Badge tone="success">Проведено</Badge><Button variant="ghost" size="sm" icon={<PencilSimple size={16} />} target="clients.payment.correct">Изменить</Button></div></div></div>) : null

  const subscriptions = card('subscriptions', 'Абонементы', CreditCard, <div className="workspace-placeholder"><div className="section-head"><div><h3>Абонементы</h3><p>Выданные пакеты, остатки и привязанные оплаты</p></div><Button icon={<Plus size={17} />}>Выдать абонемент</Button></div>{isLead ? <div className="empty-state compact"><span><CreditCard size={24} /></span><b>Абонемент ещё не выдан</b><p>Выдача оплаченного абонемента переведёт лида в ученики.</p></div> : <div className="subscription-panel"><div><Badge tone="success">Действует</Badge><h3>Развитие · 8 занятий</h3><p>До 28.09.2026</p></div><div className="subscription-metrics">{[['Всего', '8'], ['Использовано', '4'], ['Зарезервировано', '0'], ['Оплачено', '8'], ['Доступно', '4'], ['Долг', 'Нет']].map((metric) => <span key={metric[0]}><small>{metric[0]}</small><b>{metric[1]}</b></span>)}</div><Button variant="secondary" size="sm" icon={<PencilSimple size={16} />}>Изменить и пересчитать</Button></div>}</div>)

  const progress = card('progress', 'Прогресс', TrendUp, <div className="progress-board"><div><small>Направление</small><b>{isLead ? 'Вокал' : 'Фортепиано'}</b></div><div><small>Текущий уровень</small><b>{isLead ? 'Не указан' : 'Продолжающий'}</b></div><div><small>Цель обучения</small><b>{isLead ? 'Не указана' : 'Подготовка к выступлению'}</b></div><div className="progress-note"><small>Заметка о прогрессе</small><p>{isLead ? 'Прогресс появится после начала обучения.' : 'Уверенно читает ноты, продолжаем работу над динамикой.'}</p></div></div>)

  const historyTasks = card('history_tasks', 'История и задачи', ListChecks, <div><Segmented items={['Задачи', 'Комментарии', 'История']} value={historyTab} onChange={setHistoryTab} />{historyTab === 'Задачи' && <div className="history-list"><div><CheckSquare size={19} /><span><b>Согласовать время пробного занятия</b><small>Елена Смирнова · сегодня, 17:00</small></span><Badge tone="info">Открыта</Badge></div></div>}{historyTab === 'Комментарии' && <div className="history-list"><div><ChatsCircle size={19} /><span><b>Елена Смирнова</b><small>Клиенту удобно заниматься после 18:00.</small></span><time>14.08</time></div></div>}{historyTab === 'История' && <div className="history-list"><div><Clock size={19} /><span><b>Статус изменён</b><small>Новый → В процессе · Елена Смирнова</small></span><time>14.08</time></div><div><UserPlus size={19} /><span><b>Карточка создана</b><small>Источник: Сайт</small></span><time>12.08</time></div></div>}</div>)

  const documents = card('documents', 'Документы', FileText, <div className="empty-state compact"><span><FileText size={24} /></span><b>Документов пока нет</b><p>Поддерживаемые документы появятся в этом разделе.</p></div>)

  return <section className="client-workspace"><header><span className="client-header-icon">{isLead ? <UserCircle size={22} /> : <GraduationCap size={22} />}</span><span><h2>{isLead ? 'София Крылова' : 'Алиса Воронцова'}</h2><small><span className="client-state-dot" />Клиент · {isLead ? 'Лид · В процессе' : 'Ученик · Баланс: 0 ₽'}</small></span><Button variant="ghost" size="icon" title="Назад" onClick={onClose}><CaretLeft size={24} /></Button></header><div className="client-workspace-body"><aside><div className="section-jump-card">{sections.map(([id, label, Icon]) => <button type="button" className={activeSection === id ? 'active' : ''} key={id} onClick={() => jumpTo(id)}><Icon size={16} />{label}</button>)}</div></aside><main className="client-canvas-scroll"><div className="client-canvas"><div className="client-canvas-top">{overview}{contacts}</div>{lessonsSection}<div className="client-canvas-pair">{subscriptions}{progress}</div>{payments}{historyTasks}{documents}</div></main></div><footer>{isLead && <Button variant="secondary">Прикрепить к ученику</Button>}<Button variant="secondary" onClick={() => openVisualScreen('schedule.week')}>Открыть в расписании</Button><Button variant="ghost" onClick={onClose}>Назад</Button><Button onClick={() => notify('Изменения сохранены')}>Сохранить</Button></footer></section>
}

function LessonDrawer({ onClose, setModal, notify }: { onClose: () => void; setModal: (name: ModalName) => void; notify: (message: string) => void }) {
  return <DrawerFrame title="Матвей Соколов" subtitle="15.08.2026 · 10:30 - 11:30" onClose={onClose}><div className="detail-list"><div><span><UserCircle size={18} /></span><small>Ученик</small><b>Матвей Соколов</b></div><div><span><ChalkboardTeacher size={18} /></span><small>Педагог</small><b>Илья Морозов</b></div><div><span><Buildings size={18} /></span><small>Аудитория</small><b>Аудитория 1</b></div><div><span><Clock size={18} /></span><small>Время</small><b>15.08.2026 · 10:30 - 11:30</b></div><div><span><Info size={18} /></span><small>Статус</small><b>Конфликт</b></div><div><span><Warning size={18} /></span><small>Конфликты</small><b>Пересечение аудитории</b></div></div><div className="drawer-action-stack"><Button variant="secondary" icon={<PencilSimple size={17} />} onClick={() => { onClose(); setModal('lesson') }}>Перенести или изменить</Button><Button variant="danger" onClick={() => { onClose(); openVisualScreen('schedule.lesson.cancel') }}>Отменить занятие</Button></div></DrawerFrame>
}

export default App
