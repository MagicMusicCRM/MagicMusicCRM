export type PrototypeRole =
  | 'client'
  | 'teacher'
  | 'admin'
  | 'manager'
  | 'director'
  | 'system_admin'

export type ScreenKind =
  | 'auth'
  | 'dashboard'
  | 'list'
  | 'board'
  | 'schedule'
  | 'card'
  | 'form'
  | 'dialog'
  | 'sheet'
  | 'settings'
  | 'analytics'
  | 'chat'
  | 'state'
  | 'update'

export type ScreenState = 'content' | 'empty' | 'loading' | 'error' | 'forbidden'

export type ScreenAction = {
  label: string
  target: string
  tone?: 'primary' | 'secondary' | 'danger'
}

export type ScreenRow = {
  title: string
  subtitle: string
  meta?: string
  status?: string
  target?: string
}

export type ScreenMetric = {
  label: string
  value: string
  detail?: string
}

export type ScreenDefinition = {
  id: string
  group: string
  subgroup?: string
  title: string
  description: string
  roles: PrototypeRole[]
  kind: ScreenKind
  state?: ScreenState
  tabs?: Array<{ label: string; target: string }>
  actions?: ScreenAction[]
  rows?: ScreenRow[]
  metrics?: ScreenMetric[]
  fields?: string[]
  notes?: string[]
  nativeRoute?: string
}

export const roleLabels: Record<PrototypeRole, string> = {
  client: 'Клиент',
  teacher: 'Преподаватель',
  admin: 'Администратор',
  manager: 'Управляющий',
  director: 'Директор',
  system_admin: 'Системный администратор',
}
