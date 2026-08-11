# Полный RepoWise-аудит MagicMusicCRM

Дата: 2026-08-11
Checkout: `a12cca5` до governance cutover
Метод: RepoWise graph/symbol/risk/health/dead-code + точечная проверка живого
Flutter/NestJS/SQL-кода и актуального UAT evidence.

## Итог

Приложение технически зрелое и production-развёрнуто, но продукт нельзя считать
полностью завершённым. Главный очевидный пробел — асимметричный lifecycle:
организационные сущности можно создавать, но значительную часть нельзя штатно
закрыть, расформировать, архивировать или безопасно восстановить.

Это не повод добавлять простой `DELETE branch`. У филиала много исторических и
операционных связей; схема использует смесь `CASCADE`, `SET NULL` и
restrict/default FK. Физическое удаление либо сотрёт часть данных, либо оставит
осиротевшие проекции, либо будет заблокировано immutable finance/config facts.

## P0 — незавершённый organizational lifecycle

| Сущность | Реализовано | Отсутствует | Риск |
|---|---|---|---|
| Branch | list/create/update | preview/close/archive/history/restore | Филиал невозможно вывести из эксплуатации штатно |
| Room | list/create/update/soft-delete | impact preview, guards, restore | Используемую аудиторию можно скрыть из projections |
| Group | list/create/update/members | end/archive с plans/future lessons | Группу можно создать, но нельзя расформировать |
| Teacher | create/update | status UI, offboarding, account/session revoke | Архивирование не связано с доступом и будущей работой |
| Staff | create/update/status | атомарный access/session offboarding | CRM status сам по себе не отключает app account |
| Branch discipline | add/restore/reorder | unassign/archive | Добавленный chip нельзя убрать |
| Discipline/loss reason | list/create | rename/archive/restore/usage guard | Справочники необратимо разрастаются |

Нужен единый контракт:

```text
preview
  -> impact counts
  -> blockers
  -> canonical remediation (transfer/end/cancel)
  -> commit(reason, effectiveDate, expectedVersion, idempotencyKey)
  -> audit/outbox/history
```

Для Branch состояние должно быть как минимум
`active → closing → archived`. Историческое имя/identity сохраняется в
tombstone; активные Students/Leads, Staff/Teachers, Rooms/Groups, Plans/future
Lessons, Tasks/Chats и commerce references сначала переносятся или завершаются
явной командой.

## Другие незакрытые продуктовые доказательства

Owner mega-UAT содержит 100 уникальных сценариев: `10 PASS`, `29 PARTIAL`,
`61 PENDING`. Не доказаны полностью:

- role/device сценарии пяти ролей;
- весь CRM configuration publish/rollback/realtime цикл;
- Student Card desktop/mobile и связанные family/payer flows;
- subscription/payment/reversal/refund combinations;
- recurring plans, lesson transition и settlement drilldowns;
- messenger attachments/voice/channel lifecycle;
- loading/empty/error/forbidden/retry/offline/stale-version states;
- analytics filters, exports и entity-wide search.

Точный статус хранится в
`docs/audits/v7-owner-production-mega-uat-result.md`.

## Техническое здоровье

RepoWise dashboard на исходном checkout:

- средний health: `7.2`;
- hotspot health: `6.6`;
- worst score: `1.0`;
- 67 static performance findings;
- 198 dead-code candidates;
- только 20 high-confidence cleanup-ready exports, около 204 строк.

Основные hotspots для отдельного рефакторинга:

| Файл/модуль | Причина |
|---|---|
| `lib/features/crm/presentation/client_card/client_card_student.dart` | worst health, крупный UI aggregate |
| `lib/features/admin/presentation/widgets/crm_configuration_workspace.dart` | draft/catalog/publish/UI в одном файле |
| `lib/features/admin/presentation/widgets/shared_tasks_v4_panel.dart` | query, filters, audience editor и cards сцеплены |
| `server/src/crm/commerce/subscription-lifecycle.service.ts` | крупная transaction orchestration |
| `server/src/crm/crm.service.ts` | god-service и bug-magnet |
| `server/src/crm/lesson-settlement.repository.ts` | смешаны reads, writes, correction/reversal |

Cleanup нужно делать отдельными малыми изменениями после проверки runtime
dispatch. RepoWise не нашёл ни одного high-confidence package, безопасного для
автоматического удаления: его medium `zombie_package` кандидаты включали
`windows`, `android`, `infra` и integration tests, то есть были structural false
positives.

## Release и source-of-truth

На момент аудита production candidate был на 17 commits впереди `origin/main`.
Это recovery-риск: новый hotfix не должен стартовать со старого default branch.
Governance cutover должен быть fast-forward синхронизирован в GitHub.

Production build 181 и exact hotfix image прошли технические gates, но это не
закрывает owner UAT и не отменяет lifecycle findings.

## Приоритет

1. Branch close preview/commit и immutable archive identity.
2. Room usage guard + restore.
3. Group end/archive.
4. Atomic Staff/Teacher offboarding.
5. Reference-data archive/unassign/restore.
6. Новые owner-UAT строки для всех обратных lifecycle.
7. Затем — hotspot refactoring и проверенный dead-code cleanup.
