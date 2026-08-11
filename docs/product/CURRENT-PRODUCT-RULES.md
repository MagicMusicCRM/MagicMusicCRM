# MagicMusicCRM — текущие продуктовые правила

Этот документ хранит только действующие продуктовые инварианты. Подробный статус
приёмки находится в owner UAT, а реализация — в текущем коде и миграциях.

## Роли и scope

Иерархия: `client < teacher < admin < manager < director < system_admin`.

- Client видит только собственную область.
- Teacher видит назначенных учеников и своё расписание без staff-финансов.
- Admin работает с чатом, расписанием, клиентами и branch-scoped задачами.
- Manager получает операционный workspace назначенных филиалов без
  общешкольных финансов и финансовой аналитики.
- Director/system_admin управляют общешкольными финансами, конфигурацией и
  доступами.
- Финансы конкретной карточки клиента доступны Admin/Manager/Director через
  узкие client-finance capabilities.

Backend всегда проверяет capability и resource scope. UI не является security
boundary.

## Финансы

- Оплаты, сторно, возвраты, exclusions и technical history append-only.
- Статусы оплаты: `Не оплачен`, `Проведён, ожидает подтверждения`, `Оплачен`.
- Абонемент может покупаться со своего или чужого личного счёта, со скидкой,
  доплатой или рассрочкой; обязательство резервируется полностью.
- Отмена абонемента возвращает только допустимую сумму и не переписывает
  исходные факты.
- Типы списания и правила оплаты преподавателю конфигурируются; исторические
  snapshots неизменяемы.
- Любая денежная команда сохраняет transaction, expected version,
  idempotency, audit/outbox и reconciliation semantics.

## Занятия и расписание

- Перенос, отмена и расчёт занятия используют один
  `reason → preview → commit` flow.
- Постоянные планы именованные, индивидуальные или групповые, с conflict
  preview, обязательными преподавателем и аудиторией, active/ended history и
  bounded tray.
- Lesson settlement и teacher pay создают immutable facts; исправление идёт
  через reversal/correction, а не update/delete истории.

## CRM и operations

- Lead/Student используют каноническую карточку со staff note, комментариями,
  задачами, коммерцией, расписанием и entity navigation.
- Staff/Teacher создаются вместе с app user; выдача доступа старым сущностям
  атомарна.
- Используется одна task-модель. Teacher не является получателем staff-задач.
  Admin видит branch-scoped задачи и по умолчанию `Мои задачи + Сегодня`.
- Закрытие клиента завершает recurring work каноническими командами и сохраняет
  finance/history.

## Организационный lifecycle

Branch, Room, Group, Teacher и Staff нельзя считать завершёнными только потому,
что для них существует create/update.

- Branch закрывается через impact preview, blockers/remediation, reason,
  effective date и commit. Историческая tombstone-запись остаётся.
- Room можно архивировать только после проверки Group, future Lesson, recurring
  plan/series и conflict references; нужен restore.
- Group должна иметь end/archive flow с обработкой планов и будущих занятий.
- Staff/Teacher offboarding атомарно согласует CRM status, branch assignments,
  будущую работу, capability overrides, account и active sessions.
- Справочники и branch disciplines требуют usage-aware archive/unassign и
  restore; физическое удаление используется только там, где доказано отсутствие
  истории и ссылок.

## Приёмка

Единственный текущий статус 100 сценариев:
`docs/audits/v7-owner-production-mega-uat-result.md`.

Сценарий считается закрытым только при требуемых UI/API/DB evidence. `PARTIAL`
не равен `PASS`.
