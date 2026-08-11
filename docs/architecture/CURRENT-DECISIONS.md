# MagicMusicCRM — действующие архитектурные решения

Статус: active. Обновлено 2026-08-11.

## Инженерный процесс

DECISION: RepoWise является единственным активным code-intelligence и
agent-navigation слоем проекта. Он используется для overview, поиска symbols и
контекста, оценки риска, health и dead-code анализа. Generated process
framework, обязательные фазовые workflows и вручную поддерживаемые карты кода
не являются источником истины.

Полная запись: `docs/architecture/ADR/ADR_001_REPOWISE_FIRST.md`.

Следствия:

- `AGENTS.md` остаётся коротким и не генерируется RepoWise автоматически;
- решения и продуктовые правила хранятся в обычных текущих документах;
- индекс RepoWise локальный и обновляется из живого checkout;
- low-confidence или mock retrieval проверяется по исходнику;
- documentation ceremony не блокирует небольшую безопасную реализацию.

## Runtime

DECISION: Production использует один owned runtime:
Flutter → NestJS → PostgreSQL, с Redis/Socket.IO и private file storage.
Supabase и HolliHop не являются клиентскими runtime-зависимостями.

DECISION: Flutter вызывает backend только через существующие API
clients/services/providers. Riverpod владеет разделяемым состоянием; прямой
доступ widget к БД запрещён.

## Доступ и данные

DECISION: Авторизация, capability и resource scope проверяются backend. Роль
задаёт baseline, назначения филиалов и узкие capabilities уточняют scope.

DECISION: Финансовые, lesson settlement и audit facts неизменяемы. Исправления
создаются append-only reversal/correction facts внутри transaction с expected
version, idempotency и outbox.

DECISION: Физическое удаление организационной сущности с историческими ссылками
не используется. Decommission выполняется через preview, blockers/remediation,
commit и archive/tombstone.

## UX

DECISION: Приложение имеет единственную тёмную тему Deep Charcoal &
Sophisticated Gold. Русский — язык UI; desktop и mobile используют общий
канонический navigation/entity contract.

DECISION: Скрытие forbidden UI не заменяет backend security и не должно
инициировать запрещённый API request.

## Release

DECISION: Release-ready означает полный автоматический gate плюс platform smoke
и owner UAT для заявленного кандидата. Старое evidence не переносится на новый
build автоматически.

DECISION: Production mutation/deploy требует явного разрешения владельца,
нового backup, проверенного restore/rollback и post-deploy reconciliation.
