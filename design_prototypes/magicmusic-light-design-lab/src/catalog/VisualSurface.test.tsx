import { renderToStaticMarkup } from 'react-dom/server'
import { describe, expect, it, vi } from 'vitest'
import { VisualSurface } from './VisualSurface'
import { screenById } from './screenManifest'

function renderScreen(screenId: string) {
  const entry = screenById.get(screenId)
  if (!entry) throw new Error(`Unknown test screen: ${screenId}`)
  return renderToStaticMarkup(
    <VisualSurface entry={entry} state="content" onNavigate={vi.fn()} />,
  )
}

describe('visual click-through contexts', () => {
  it('renders a settings dialog over the real users surface', () => {
    const markup = renderScreen('settings.user.detail')

    expect(markup).toContain('Пользователи и доступы')
    expect(markup).not.toContain('class="atlas-dialog-context"')
  })

  it('renders a group chat with its own selected conversation', () => {
    const markup = renderScreen('chat.group')

    expect(markup).toContain('Команда филиала')
    expect(markup).toContain('6 участников')
    expect(markup).not.toContain('была недавно')
  })

  it('matches the production staff chat folders and creation routes', () => {
    const inbox = screenById.get('chat.inbox')

    expect(inbox?.tabs?.map((tab) => tab.label)).toEqual([
      'Лиды',
      'Ученики',
      'Архив',
    ])
    expect(inbox?.actions?.map((action) => action.target)).toEqual([
      'chat.create.menu',
    ])

    const createMenu = screenById.get('chat.create.menu')
    expect(createMenu?.actions?.slice(0, 2).map((action) => action.target)).toEqual([
      'chat.group.create',
      'chat.channel.create',
    ])
  })
})
