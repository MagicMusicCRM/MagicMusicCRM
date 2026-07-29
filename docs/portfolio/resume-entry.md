# MagicMusicCRM - Resume Entry

---

## MagicMusicCRM

**Роль:** Solo Architect / Full-Stack Engineer

**Стек:** Flutter · Dart · Riverpod · NestJS 11 · TypeScript · PostgreSQL · Redis · Socket.IO · Docker · Caddy · Selectel VPS · Firebase Messaging · Sentry · Resend · МТС Exolve

Production CRM и мессенджер для сети музыкальных школ. Система охватывает полный операционный цикл: лиды, расписание, уроки, оплаты, абонементы, домашние задания, мессенджер, приватные файлы и управленческая аналитика для ролей клиент / преподаватель / администратор / управляющий. Опубликовано в Google Play и App Store.

- Спроектировал и реализовал продукт end-to-end в одиночку: Flutter-клиент, NestJS/TypeScript backend, PostgreSQL-схему с 49 миграциями, VPS-инфраструктуру на Selectel и полный release pipeline - от архитектуры до production-деплоя.

- Перевёл продукт с Supabase BaaS на собственный backend без потери данных: построил детерминированный migration pipeline, экспортировал и перенёс 69 таблиц / 23 188 строк / 36 storage-объектов, провёл staging-проверку с dry-run отчётами и rollback-сценарием.

- Разработал безопасный import-pipeline для переноса данных из legacy CRM в собственную PostgreSQL: dry-run по умолчанию, backup gate перед применением, отчёты по расхождениям - 22 839 уроков и 22 778 участий проверено до применения, 2 070 дублирующихся записей выявлено и помечено; итоговый production snapshot: 35 132 урока, 5 806 платежей.

- Построил realtime-мессенджер на Socket.IO: direct / group / channel / admin чаты, typing, presence, read states, реакции, закрепление, редактирование и пересылка сообщений, голосовые и файловые вложения; end-to-end latency в smoke-сценариях - 52–60 ms.

- Реализовал private file storage вне public web root: загрузка через backend API, отдача по одноразовым signed-токенам с проверкой владельца и роли - для чатов, голосовых сообщений, аватаров и домашних заданий.

- Обеспечил многоуровневую безопасность на уровне backend: server-side RBAC с ownership policies для 5 ролей, refresh-token rotation с обнаружением повторного использования, OTP, юридические согласия, lifecycle удаления аккаунта и audit log на чувствительные операции.

- Настроил коммуникационный стек на backend: Resend как основной email-провайдер, SMTP TLS fallback с exponential retry и защитой от header injection, outbox/worker-drain модель; SMS и OTP через МТС Exolve.

- Провёл performance-аудит production API: большинство REST-эндпоинтов - менее 500 ms, PostgreSQL cache hit ~99,96%, deadlocks 0; выявил и задокументировал SQL hot paths, разработал план оптимизации через DTO split, переработку запросов и таргетированную realtime-инвалидацию.

- Выстроил production-операционный контур: Docker Compose + Caddy TLS, зашифрованные бэкапы, restore drill и rollback runbooks; release gates - 43 backend suite / 432 теста, Flutter analyze clean / 233 теста, security audit и realtime smoke; delivery велся через систему задач с фазовыми acceptance criteria и evidence-driven закрытием.

- Применял AI-агентов (Antigravity, Codex, Claude Code) как engineering force multiplier: ускорение реализации, code review, QA и документирование - при сохранении авторского контроля над архитектурой, бизнес-правилами и всеми production-проверками.
