# График преподавателя в «Персонале» — локальная правка поверх 232

Решение владельца от 01.10.2026: рабочий график и отсутствия постоянно видны
на странице карточки преподавателя. Редактор использует существующие services,
capabilities и versioned-команды; отдельная модель или backend-изменения не нужны.
В настройках удалены графики и дублирующие списки Staff/Teacher. Общие настройки
аккаунтов, прав и уведомлений сохранены.

## Проверка

Команда из корня worktree: `node scripts/http-journey-check.cjs --audit-ui-usability`.
Условия: Windows/Flutter, PostgreSQL 17 на loopback `127.0.0.1:54329`, штатные
локальные synthetic owner/app роли. Runner создаёт изолированную БД, запускает
локальный API и удаляет БД после прогона. Production-данные не используются.

Финальный run: `172185e560c6481c91a91db8b73ae880`, 24 gate checks PASS, 0 FAIL,
0 server errors. Native шаги `TEACHER` и `PERSONNEL-SETTINGS` проверяют отсутствие
перехода в настройки, постоянно видимый редактор, сохранение рабочего интервала,
сохранение отсутствия общим действием карточки, защиту черновика при закрытии
и работу в окнах 1280×800 / 390×800.

Артефакты: `dist/http-journeys/172185e560c6481c91a91db8b73ae880/result.json`,
`ui-usability-director.json`, `ui-usability-windows.log`,
`ui-teacher-availability-wide.png`, `ui-teacher-availability-narrow.png`.
`flutter analyze --no-pub` и `git diff --check` — PASS.
Windows Release: `flutter build windows --release --target=lib/main.dart
--dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api` — PASS.
Сборка использует штатную генерацию plugin registrants для обычного приложения.

Проверка не заменяет ручную приёмку владельца. Эта правка не опубликована;
production API, схема, update-каналы и номер версии не менялись.
