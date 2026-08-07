# v7 — INT-S3 Recurring Plans

**Дата:** 2026-08-07

**Статус:** PASS

## Сквозной результат

- Один versioned Plan aggregate покрывает individual/group create, effective
  edit, end и history без переписывания прошлых Lesson snapshots.
- Client Card показывает active планы раскрытыми, ended history свёрнутой и
  отдельную bounded двухстрочную tray для каждого плана.
- Отсутствие preferred schedule не скрывает Plan или фактические Lessons.
- Create/edit/end используют одни и те же адаптивные поверхности на Windows и
  Android; Back закрывает редактор и сохраняет раскрытый контекст карточки.
- End требует reason, preview и idempotent commit; participant subscriptions,
  future Lessons, reservations и tray проходят PostgreSQL reconciliation.
- Роли без schedule-read capability не создают provider и не отправляют скрытых
  запросов.

## Проверки

| Gate | Результат |
|---|---:|
| Schedule Plan PostgreSQL lifecycle | 6/6 |
| Targeted Flutter plan/card/editor | 28/28 |
| Flutter analyze | PASS |
| Windows x64 device lifecycle | 1/1 PASS |
| Android 15 / API 35 lifecycle | 1/1 PASS |
| Android logcat | Flutter/FATAL exceptions = 0 |
| v7 reconcile ×2 | `issues=[]` / `issues=[]` |
| Full Flutter regression | 632/632 |
| Full backend regression | 155/155 suites, 1223/1223 tests |
| Backend typecheck / build | PASS / PASS |
| Access / shadow | 297/297; access 1782, schedule 2000, unexplained 0 |
| Inventory stale checks | v4/v6/v7 PASS; unowned 0 |

## Вывод

S3 принят: Plan lifecycle и его каноническая Client Card поверхность совпадают
на backend, desktop и mobile. Следующая задача — `T5.1.1`, подключение уже
реализованной commerce integrity к профильным секциям карточки клиента.
