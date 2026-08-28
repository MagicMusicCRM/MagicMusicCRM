# Light theme Wave 1 — local color audit

Дата: 28 августа 2026 года. Ветка: `codex/light-visual-wave-1`.

## Граница аудита

В baseline было `76` Flutter-файлов с локальными `Colors.*` или `Color(0x...)` вне
центральной темы. После Wave 1 grep всё ещё видит файлы с намеренными
исключениями; само наличие literal не считается дефектом.

## Заменено в Wave 1

- Фоны, surfaces, text, borders, input, buttons, navigation, dialog, sheet, menu,
  toast, tooltip, scrollbar и skeleton переведены на `AppColor` и `AppTheme.production`.
- Белый текст на среднем золоте заменён на `AppColor.onGold`; светлый
  `onBrand` разрешён только на тёмном `brandSolid`.
- Исправлены notification bell, drag feedback лидов/учеников, client tabs,
  отправка файла/голоса, today marker, role chips, profile actions и auth errors.
- Исторические `TelegramColors.dark*`/`light*` остались временным compile bridge,
  но оба набора ссылаются на одну светлую палитру.

## Намеренные исключения

- Status/domain colors: lesson state, data quality, role identity, schedule resources,
  danger/success/warning/info и presence/unread markers.
- Media: avatar gradients, image viewer scrim, crop overlay, thumbnail placeholders и
  белые glyphs на проверенном тёмном media/status фоне.
- Effects: alpha overlays, shimmer transparency и декоративные resource colors,
  которые не несут UI-текст.

Новый raw literal для UI chrome запрещён; новый status/media literal требует явного
контекста и contrast-проверки.
