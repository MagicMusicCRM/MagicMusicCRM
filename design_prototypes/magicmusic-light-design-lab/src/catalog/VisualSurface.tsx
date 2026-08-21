import type { ReactNode } from 'react'
import {
  ArrowLeft,
  Buildings,
  CalendarBlank,
  CaretRight,
  ChartBar,
  ChatCircleText,
  CheckCircle,
  Clock,
  CreditCard,
  FileText,
  GearSix,
  GraduationCap,
  Info,
  LockKey,
  MagnifyingGlass,
  Megaphone,
  Paperclip,
  PaperPlaneTilt,
  Plus,
  Receipt,
  ShieldCheck,
  SpinnerGap,
  UserCircle,
  UsersThree,
  WarningCircle,
  WifiSlash,
  X,
} from '@phosphor-icons/react'
import appLogo from '../../../../assets/icon.png'
import type { ScreenAction, ScreenDefinition, ScreenState } from './types'
import { screenById, screenManifest, withState } from './screenManifest'

type VisualSurfaceProps = {
  entry: ScreenDefinition
  state: ScreenState
  onNavigate: (target: string) => void
}

const iconByKind = {
  auth: LockKey,
  dashboard: ChartBar,
  list: FileText,
  board: UsersThree,
  schedule: CalendarBlank,
  card: UserCircle,
  form: FileText,
  dialog: Info,
  sheet: FileText,
  settings: GearSix,
  analytics: ChartBar,
  chat: ChatCircleText,
  state: Info,
  update: Info,
}

function ActionButton({ action, onNavigate }: { action: ScreenAction; onNavigate: (target: string) => void }) {
  return <button type="button" data-screen-target={action.target} className={`atlas-action atlas-action-${action.tone ?? 'primary'}`} onClick={() => onNavigate(action.target)}>{action.label}</button>
}

function StateSurface({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  const state = entry.state ?? 'empty'
  const copy = {
    loading: { icon: <SpinnerGap size={32} className="atlas-spinner" />, title: 'Загрузка данных', text: 'Подготавливаем актуальную информацию.' },
    empty: { icon: <FileText size={32} />, title: entry.title, text: entry.description },
    error: { icon: entry.id === 'state.offline' ? <WifiSlash size={32} /> : <WarningCircle size={32} />, title: entry.title, text: entry.description },
    forbidden: { icon: <ShieldCheck size={32} />, title: entry.title, text: entry.description },
    content: { icon: <CheckCircle size={32} />, title: entry.title, text: entry.description },
  }[state]

  return <div className={`atlas-state atlas-state-${state}`}>
    <span>{copy.icon}</span>
    <h2>{copy.title}</h2>
    <p>{copy.text}</p>
    <div className="atlas-actions">{entry.actions?.map((action) => <ActionButton key={`${action.label}-${action.target}`} action={action} onNavigate={onNavigate} />)}</div>
  </div>
}

function Metrics({ entry }: { entry: ScreenDefinition }) {
  if (!entry.metrics?.length) return null
  return <div className="atlas-metrics">{entry.metrics.map((metric) => <article key={metric.label}><span>{metric.label}</span><strong>{metric.value}</strong>{metric.detail && <small>{metric.detail}</small>}</article>)}</div>
}

function Rows({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  if (!entry.rows?.length) return null
  return <div className="atlas-rows">{entry.rows.map((item, index) => {
    const content = <>
      <span className="atlas-row-avatar">{item.title.split(' ').slice(0, 2).map((part) => part[0]).join('').toUpperCase()}</span>
      <span className="atlas-row-main"><b>{item.title}</b><small>{item.subtitle}</small></span>
      {item.meta && <span className="atlas-row-meta">{item.meta}</span>}
      {item.status && <span className="atlas-row-status">{item.status}</span>}
      {item.target && <CaretRight size={18} />}
    </>
    return item.target
      ? <button type="button" key={`${item.title}-${index}`} onClick={() => onNavigate(item.target!)}>{content}</button>
      : <div key={`${item.title}-${index}`}>{content}</div>
  })}</div>
}

function FormFields({ entry }: { entry: ScreenDefinition }) {
  if (!entry.fields?.length) return null
  return <div className="atlas-form-grid">{entry.fields.map((field, index) => {
    const isLong = /опис|комментар|причин|замет|материал/i.test(field)
    const isSelect = /роль|филиал|приоритет|способ|статус|категор|тип|направлен|преподавател|аудитор|абонемент|сотрудник/i.test(field)
    return <label className={isLong ? 'atlas-field-wide' : ''} key={field}>
      <span>{field}</span>
      {isLong ? <textarea defaultValue={index === 0 ? '' : undefined} placeholder="Введите текст" /> : isSelect ? <select defaultValue=""><option value="" disabled>Выберите значение</option><option>Первый вариант</option><option>Второй вариант</option></select> : <input defaultValue={/имя/i.test(field) ? 'Алиса' : ''} placeholder="Введите значение" />}
    </label>
  })}</div>
}

function ScheduleVisual({ onNavigate }: { onNavigate: (target: string) => void }) {
  const events = [
    ['09:00', 'Алиса Воронцова', 'Фортепиано · Аудитория 2'],
    ['11:00', 'Группа «Ритм»', 'Сольфеджио · Аудитория 4'],
    ['14:00', 'Матвей Соколов', 'Гитара · Аудитория 1'],
    ['17:00', 'София Крылова', 'Вокал · Аудитория 1'],
  ]
  return <div className="atlas-schedule">
    <div className="atlas-schedule-head"><b>Время</b>{['Пн, 17', 'Вт, 18', 'Ср, 19', 'Чт, 20', 'Пт, 21'].map((day) => <b key={day}>{day}</b>)}</div>
    <div className="atlas-schedule-grid">
      {events.map((event, index) => <button type="button" key={event[1]} style={{ gridColumn: index + 2, gridRow: index + 2 }} onClick={() => onNavigate(index === 3 ? 'schedule.conflict.inspector' : 'schedule.lesson.details')} className={index === 3 ? 'atlas-event conflict' : 'atlas-event'}><time>{event[0]}</time><b>{event[1]}</b><small>{event[2]}</small></button>)}
      {Array.from({ length: 30 }, (_, index) => <span key={index} />)}
    </div>
  </div>
}

function BoardVisual({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  const columns = ['Новые', 'В процессе', 'Пробный урок', 'Обучаются']
  return <div className="atlas-board">{columns.map((column, columnIndex) => <section key={column}><header><i /><b>{column}</b><span>{columnIndex + 1}</span></header><div>{(entry.rows ?? []).slice(columnIndex, columnIndex + 1).map((item) => <button type="button" key={item.title} onClick={() => item.target && onNavigate(item.target)}><span className="atlas-row-avatar">{item.title.split(' ').map((part) => part[0]).join('')}</span><b>{item.title}</b><small>{item.subtitle}</small><em>{item.meta}</em></button>)}</div></section>)}</div>
}

function ChatVisual({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  const folders = [
    ['Лиды', 'chat.inbox'],
    ['Ученики', 'chat.students'],
    ['Архив', 'chat.archive'],
  ] as const
  const selectedFolder = entry.id === 'chat.archive' ? 'chat.archive' : entry.id === 'chat.students' ? 'chat.students' : 'chat.inbox'
  const chatRows = entry.id === 'chat.archive'
    ? [['Павел Титов', 'Спасибо, всё получилось', '12 авг', '', 'chat.dialog']]
    : entry.id === 'chat.students'
      ? [['Алиса Воронцова', 'Задание отправлено преподавателю', '11:04', '', 'chat.dialog'], ['Родители группы «Ритм»', 'Концерт состоится в 18:00', 'Вчера', '', 'chat.group']]
      : [['София Крылова', 'Можно перенести занятие на пятницу?', '10:42', '2', 'chat.dialog'], ['Никита Орлов', 'Хочу записаться на гитару', '09:18', '1', 'chat.dialog'], ['Команда филиала', 'Елена: перенесла занятие', 'Вчера', '', 'chat.group'], ['Объявления', 'График концерта опубликован', 'Пн', '', 'chat.channel']]
  const isGroup = entry.id === 'chat.group'
  const isChannel = entry.id === 'chat.channel'
  const isSearch = entry.id === 'chat.search'
  const selectedName = isGroup ? 'Команда филиала' : isChannel ? 'Объявления' : 'София Крылова'
  const selectedMeta = isGroup ? '6 участников · 4 в сети' : isChannel ? 'Канал школы · 248 участников' : 'Лид · Садовая'
  const selectedInitials = selectedName.split(' ').slice(0, 2).map((part) => part[0]).join('').toUpperCase()

  return <div className="atlas-chat">
    <aside>
      <header className="atlas-chat-list-head"><button type="button" title="Профиль" onClick={() => onNavigate('profile.main')}><UserCircle size={19} /></button><b>MagicMusic</b><button type="button" title="Создать чат или канал" onClick={() => onNavigate('chat.create.menu')}><Plus size={19} /></button></header>
      <label><MagnifyingGlass size={17} /><input placeholder="Поиск" /></label>
      <nav className="atlas-chat-folders">{folders.map(([label, target]) => <button type="button" className={selectedFolder === target ? 'active' : ''} key={target} onClick={() => onNavigate(target)}>{label}{label === 'Лиды' && <i>3</i>}</button>)}</nav>
      <label className="atlas-chat-branch"><Buildings size={16} /><select aria-label="Филиал"><option>Все филиалы</option><option>Садовая</option><option>Петроградская</option></select></label>
      <small className="atlas-chat-section-label">{entry.id === 'chat.archive' ? 'Архив' : 'Диалоги'}</small>
      {chatRows.map((item) => <button type="button" className={item[0] === selectedName ? 'active' : ''} key={item[0]} onClick={() => onNavigate(item[4])}><span className="atlas-row-avatar">{item[0].split(' ').slice(0, 2).map((part) => part[0]).join('').toUpperCase()}</span><span><b>{item[0]}</b><small>{item[1]}</small></span><time>{item[2]}</time>{item[3] && <i>{item[3]}</i>}</button>)}
    </aside>
    <section>
      <header><span className="atlas-row-avatar">{isChannel ? <Megaphone size={18} /> : selectedInitials}</span><button type="button" className="atlas-chat-person" onClick={() => onNavigate(isGroup ? 'chat.group.edit' : isChannel ? 'chat.channel.edit' : 'chat.info')}><b>{selectedName}</b><small>{selectedMeta}</small></button><div className="atlas-chat-head-actions"><button type="button" title="Поиск по чату" onClick={() => onNavigate('chat.search')}><MagnifyingGlass size={18} /></button><button type="button" title="Информация" onClick={() => onNavigate(isGroup ? 'chat.group.edit' : isChannel ? 'chat.channel.edit' : 'chat.info')}><Info size={18} /></button></div></header>
      {isSearch && <div className="atlas-chat-search"><MagnifyingGlass size={17} /><input autoFocus placeholder="Поиск по сообщениям" defaultValue="занятие" /><span>1 из 3</span><button type="button" onClick={() => onNavigate('chat.dialog')}>Закрыть</button></div>}
      <div className="atlas-messages">
        <div className="atlas-chat-date">Сегодня</div>
        {isChannel
          ? <><p><b>Олег Романов</b>Концерт школы состоится 28 августа в 18:00.<small>09:30</small></p><p>Расписание выступлений уже доступно в приложении.<small>09:32</small></p></>
          : isGroup
            ? <><p><b>Елена Смирнова</b>Коллеги, занятие Матвея перенесено на понедельник.<small>12:31</small></p><p>Спасибо. Я проверю аудиторию.<small>12:34</small></p></>
            : <><p>Здравствуйте! Можно перенести занятие на пятницу?<small>10:42</small></p><p>Да, предложу свободное время.<small>10:44</small></p></>}
      </div>
      <footer><button type="button" title="Прикрепить файл" onClick={() => onNavigate('chat.file')}><Paperclip size={19} /></button><input placeholder="Напишите сообщение" /><button type="button" title="Отправить" onClick={() => onNavigate(entry.id)}><PaperPlaneTilt size={18} weight="fill" /></button></footer>
    </section>
  </div>
}

function AuthVisual({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  return <div className="atlas-auth-stage">
    <div className="atlas-auth-brand"><img src={appLogo} alt="Magic Music" /><span><b>Magic Music</b><small>Школа музыки</small></span></div>
    <section className="atlas-auth-card">
      <span className="atlas-auth-icon"><LockKey size={23} /></span>
      <h1>{entry.title}</h1><p>{entry.description}</p>
      <FormFields entry={entry} />
      <div className="atlas-auth-actions">{entry.actions?.map((action) => <ActionButton key={`${action.label}-${action.target}`} action={action} onNavigate={onNavigate} />)}</div>
    </section>
  </div>
}

function referencesScreen(entry: ScreenDefinition, target: string) {
  return entry.actions?.some((action) => action.target === target)
    || entry.tabs?.some((tab) => tab.target === target)
    || entry.rows?.some((row) => row.target === target)
}

function contextFor(entry: ScreenDefinition) {
  const queue = [entry.id]
  const visited = new Set(queue)
  while (queue.length) {
    const target = queue.shift()!
    const parents = screenManifest
      .filter((candidate) => candidate.group === entry.group && referencesScreen(candidate, target))
      .sort((left, right) => Number(right.roles.some((role) => entry.roles.includes(role))) - Number(left.roles.some((role) => entry.roles.includes(role))))
    for (const parent of parents) {
      if (visited.has(parent.id)) continue
      visited.add(parent.id)
      if (!['dialog', 'sheet', 'auth', 'state'].includes(parent.kind)) return parent
      queue.push(parent.id)
    }
  }

  const fallbackId = entry.group === 'Настройки системы' ? 'settings.root'
    : entry.group === 'Чат' ? 'chat.inbox'
      : entry.group === 'Расписание' ? 'schedule.week'
        : entry.group === 'Карточка клиента' ? 'clients.lead.card'
          : entry.group === 'Задачи' ? 'tasks.list'
            : entry.group === 'Профиль' ? 'profile.main'
              : 'overview.main'
  return screenById.get(fallbackId)
}

function DialogFrame({ entry, contextEntry, children, onNavigate }: { entry: ScreenDefinition; contextEntry?: ScreenDefinition; children: ReactNode; onNavigate: (target: string) => void }) {
  return <div className="atlas-dialog-stage">
    {contextEntry && <div className="atlas-dialog-context-surface" aria-hidden="true"><WorkspaceSurface entry={contextEntry} onNavigate={() => undefined} /></div>}
    <section className={`${entry.kind === 'sheet' ? 'atlas-sheet-frame' : 'atlas-dialog-frame'}${entry.tabs?.length ? ' atlas-dialog-with-tabs' : ''}`}>
      <header><span><h1>{entry.title}</h1><p>{entry.description}</p></span>{contextEntry && <button type="button" title="Закрыть" onClick={() => onNavigate(contextEntry.id)}><X size={18} /></button>}</header>
      {entry.tabs?.length && <nav className="atlas-dialog-tabs">{entry.tabs.map((tab) => <button type="button" key={tab.target} className={tab.target === entry.id ? 'active' : ''} onClick={() => onNavigate(tab.target)}>{tab.label}</button>)}</nav>}
      <div className="atlas-dialog-body">{children}</div>
      <footer>{entry.actions?.map((action) => <ActionButton key={`${action.label}-${action.target}`} action={action} onNavigate={onNavigate} />)}</footer>
    </section>
  </div>
}

function WorkspaceSurface({ entry, onNavigate }: { entry: ScreenDefinition; onNavigate: (target: string) => void }) {
  if (entry.kind === 'chat') {
    return <div className="atlas-chat-page" data-screen-id={entry.id}><ChatVisual entry={entry} onNavigate={onNavigate} /></div>
  }
  const Icon = iconByKind[entry.kind]
  return <div className={`atlas-page atlas-kind-${entry.kind}`} data-screen-id={entry.id}>
    <header className="atlas-page-head">
      <div className="atlas-breadcrumbs"><span>{entry.group}</span><CaretRight size={14} /><b>{entry.title}</b></div>
      <div className="atlas-title-row"><span className="atlas-title-icon"><Icon size={23} /></span><span><h1>{entry.title}</h1><p>{entry.description}</p></span><div className="atlas-head-actions">{entry.actions?.map((action) => <ActionButton key={`${action.label}-${action.target}`} action={action} onNavigate={onNavigate} />)}</div></div>
    </header>
    {entry.tabs?.length && <nav className="atlas-tabs">{entry.tabs.map((tab) => <button type="button" key={tab.target} className={tab.target === entry.id ? 'active' : ''} onClick={() => onNavigate(tab.target)}>{tab.label}</button>)}</nav>}
    <main className="atlas-content">
      {entry.kind === 'dashboard' && <div className="atlas-attention"><WarningCircle size={20} /><span><b>Требует внимания</b><small>Проверьте просроченные задачи и конфликты расписания</small></span><button type="button" onClick={() => onNavigate('schedule.conflicts')}>Открыть</button></div>}
      <Metrics entry={entry} />
      {entry.kind === 'schedule' && <ScheduleVisual onNavigate={onNavigate} />}
      {entry.kind === 'board' && <BoardVisual entry={entry} onNavigate={onNavigate} />}
      {(entry.kind === 'form' || entry.fields?.length) && <section className="atlas-form-card"><FormFields entry={entry} /></section>}
      {entry.kind === 'settings' && !entry.rows?.length && <div className="atlas-settings-cards">{['Организация', 'Расписание', 'Клиенты', 'Продажи и оплаты', 'Пользователи и доступы', 'Данные и обслуживание'].map((label, index) => <button type="button" key={label} onClick={() => onNavigate(['settings.organization', 'settings.schedule', 'settings.crm', 'settings.sales', 'settings.users', 'settings.data'][index])}><span><GearSix size={20} /></span><b>{label}</b><small>Открыть настройки раздела</small><CaretRight size={18} /></button>)}</div>}
      <Rows entry={entry} onNavigate={onNavigate} />
      {entry.notes?.length && <section className="atlas-notes"><Info size={20} /><div>{entry.notes.map((note) => <p key={note}>{note}</p>)}</div></section>}
      {entry.kind === 'card' && <div className="atlas-card-sections"><section><header><UserCircle size={19} /><b>Основная информация</b></header><p>Все связанные данные собраны на одной большой прокручиваемой карточке.</p></section><section><header><CalendarBlank size={19} /><b>Ближайшее действие</b></header><p>18 августа, 17:00 · Садовая</p></section><section><header><Receipt size={19} /><b>Рабочий контекст</b></header><p>История, комментарии и связанные записи доступны без смены окна.</p></section></div>}
    </main>
  </div>
}

export function VisualSurface({ entry, state, onNavigate }: VisualSurfaceProps) {
  const visibleEntry = withState(entry, state)
  if (state !== 'content' || entry.kind === 'state') {
    return <div className="atlas-standalone" data-screen-id={entry.id}><StateSurface entry={visibleEntry} onNavigate={onNavigate} /></div>
  }
  if (entry.kind === 'auth') return <div data-screen-id={entry.id}><AuthVisual entry={entry} onNavigate={onNavigate} /></div>
  if (entry.kind === 'dialog' || entry.kind === 'sheet') {
    return <div data-screen-id={entry.id}><DialogFrame entry={entry} contextEntry={contextFor(entry)} onNavigate={onNavigate}><Metrics entry={entry} /><FormFields entry={entry} /><Rows entry={entry} onNavigate={onNavigate} />{entry.notes?.length && <section className="atlas-notes"><Info size={20} /><div>{entry.notes.map((note) => <p key={note}>{note}</p>)}</div></section>}</DialogFrame></div>
  }
  return <WorkspaceSurface entry={entry} onNavigate={onNavigate} />
}

export function AtlasBackButton({ target, onNavigate }: { target: string; onNavigate: (target: string) => void }) {
  return <button type="button" className="atlas-back" onClick={() => onNavigate(target)}><ArrowLeft size={18} />Назад</button>
}
