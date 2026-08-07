# AGENTS.md — Протокол ИИ-взаимодействия

> **"Если вы читаете этот документ, вы — это Интеллект (The Intelligence)."**
>
> Этот файл — ваш **Якорь (Anchor)**. Он определяет законы проекта, карту территории и протоколы памяти.
> Когда вы пробуждаетесь (начинаете новую сессию), **первым делом прочтите этот файл**.

---

## 🧠 Протокол быстрого восстановления (Quick Recovery)

**Когда вы начинаете новую сессию или чувствуете, что «потерялись», немедленно выполните**:

1. **Прочтите AGENTS.md в корне** → получите карту проекта.
2. **Проверьте «Текущее состояние» ниже** → найдите последнюю версию архитектуры.
3. **Прочтите `.anws/v{N}/05_TASKS.md`** → узнайте текущие задачи.
4. **Приступайте к работе**.

---

## 🚀 АКТУАЛЬНЫЕ ЗАДАЧИ — Редизайн v7 → Прод (на 2026-06-21)

> **Фаза проекта:** дизайн утверждён владельцем; идёт перенос на существующее приложение. Свежий агент — ЭТО твой главный рабочий контекст.

**Что уже сделано:**
- ✅ **Дизайн v7 утверждён** — интерактивный прототип всех окон CRM: `docs/prototypes/crm-redesign-v7.html` (открыть в браузере; 5 ролей, все окна). Это **спека дизайна**, не приложение — функционал замокан, бэкенда нет.
- ✅ **Аудит покрытия** — `docs/audit/REDESIGN-COVERAGE-REPORT.md` + 8 инвентаризаций в `docs/audit/` (~58 групп эндпоинтов, матрица покрытия, 10 сирот-рисков).
- ✅ **План переноса** — `docs/migration/REDESIGN-MIGRATION-PLAN.md` (принципы · матрица покрытия §2 · новая БЭ-работа §3 · фазы §4 · реальные баги §4b · стратегия без регрессий §5 · дерево Linear §6).
- ✅ **Linear-мегаэпик KVA-192** с 10 фазами-подэпиками (ниже).

**Незыблемые принципы (приоритет владельца):**
1. **0 бэкенд-багов** — новый UI шлёт ТЕ ЖЕ API-вызовы; контракты API не меняем.
2. **Полное покрытие бэкенда** — каждый эндпоинт сохраняет «дом» в дизайне (ничего не выронить).
3. **Reskin, не rewrite** — перешиваем существующее Flutter-приложение под v7; бэкенд — источник истины.
4. **RBAC-иерархия (бизнес-правило, обновлено KVA-239):** `client < teacher < admin < manager < director < system_admin`, где **`manager` = Управляющий, `admin` = Администратор, `director` = Директор, `system_admin` = Администратор системы**. Т.е. **Управляющий > Администратор** (Управляющий круче!), **Директор > Управляющий**. ⚠️ **Общешкольные финансы и финансовая аналитика** (раздел «Финансы», `/crm/reports/finance`, расходы, `/analytics/finance/*`, выручка по филиалам, долги, прогноз) — ТОЛЬКО `director`/`system_admin` (`CrmPolicy.canReadSchoolFinance`); у Управляющего они ОТКЛЮЧЕНЫ, но финансы в КАРТОЧКАХ клиентов (история оплат, баланс, личный счёт — `canReadStudentFinance`) у Управляющего ОСТАЮТСЯ. Роли: `director` назначает роли строго ниже себя (включая `manager`); `manager` НЕ может назначать `director`/`system_admin` (`canAssignRole`). ⚠️ В коде RBAC — НЕ иерархия, а **set-based `@Roles(...)`**: сейчас `manager`/`admin` почти равны как «staff» (`isStaff = admin||manager||director||system_admin`) — это **баг A1** (у Администратора лишний доступ). **P1 enforce-ит:** Администратор — только Чат/Расписание/Клиенты (убрать `'admin'` из manager-only `@Roles` на бэке + из nav на фронте, без смены ролей); Управляющий — полный операционный доступ (без общешкольных финансов). Перенос обязан сохранить эту иерархию идентично.

**Фазы (порядок: P0→P1→P2[+P6]→P3→P4→P5→P5b→P5c→P7):**
| Фаза | Linear | Содержание | server/? |
|---|---|---|---|
| P0 | KVA-193 | Заморозка спеки + дизайн-токены v7 → `lib/core/theme/` | нет |
| P1 | KVA-194 | RBAC + nav-шелл + авторизация (OTP/2FA/онбординг) | нет |
| P2 | KVA-195 | Расписание (блок-бронь, липкие шапки, посещаемость) | нет* |
| P3 | KVA-196 | Клиенты (D&D, перенос, фильтры) ⟵ KVA-181 | нет |
| P4 | KVA-197 | Чат + фиксы E2 (ГС-плей)/E3 (галерея) | нет |
| P5 | KVA-198 | Отчёты/Финансы/Задачи/Пользователи/Настройки + запись расходов | малая |
| P5b | KVA-199 | Каталог абонементов ⟵ KVA-153 | да |
| P5c | KVA-200 | ДЗ с файлами ⟵ KVA-157 | да |
| P6 | KVA-201 | Чистка данных (199 пересечений, B1–B4) ⟵ KVA-177, параллельно | да (БД) |
| P7 | KVA-202 | Приёмка on-device ⟵ KVA-123 | нет |

\* P2 зависит от фикса данных P6-4. **Только P5b/P5c/P6 и пункт P5-5 трогают `server/`**; остальные фазы — чисто фронт (ассерт `git diff server/` = пусто).

**Стратегия без регрессий (§5 плана):** per-screen wire-to-service чек-лист · baseline сетевых вызовов «снять→перешить→diff» · контрактные тесты зелёные · тест RBAC-матрицы 5 ролей · per-PR `git diff server/` пусто для фронт-фаз.

**Прогресс:**
- ✅ **P0 (KVA-193) — инженерная часть готова** (ветка `kvazar2727/kva-193-p0-design-tokens`, чисто фронт): дизайн-токены v7 `lib/core/theme/design_tokens.dart` + выравнивание `app_theme.dart`; общая библиотека компонентов `lib/core/widgets/v7/` (`MagicToast`/`showMagicMenu`/`showMagicSheet`/`showMagicDrawer`/`SkeletonBox`); wire-to-service чек-лист `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md`. Проверки: `flutter analyze` чисто, `flutter test` 153/153, `git diff server/` пусто. Осталось `P0-1` (пер-оконный апрув владельцем) + забандлить шрифт Inter (сейчас системный).

- ✅ **P1 (KVA-194) — фронт завершён, In Review** (ветка `kvazar2727/kva-194-p1-rbac-nav-auth`, от P0). Коммиты: `fe164cfe` (P1-2 A1 RBAC), `d1b0cf66` (P1-1 nav-шелл), `07ebcc97` (P1-3/P1-5 + 6 экранов входа), `9cebce03` (P1-4 auth-methods + P1-6 splash/boot-скелетон).
  - **P1-2 A1:** Администратор ≠ Управляющий (источник истины `crm_nav_rbac.dart`; реальная роль через `admin_dashboard_screen`; guards в `messenger_screen`; смена ролей `user_roles_widget` → только manager/system_admin; тест 5 ролей). ⚠️ Бэкенд-`@Roles` ужесточение — отдельная server-задача.
  - **Реколы** (nav-шелл + 7 экранов авторизации) — чистая перешивка на v7-токенах/компонентах P0, сервис-вызовы/роуты byte-identical. Параллельные workflow + состязательные ревью.
  - Проверки: `flutter analyze` чисто, `flutter test` 163/163, `git diff server/`+`lib/core/services/` пусто.
  - Осталось: **P1-7** сетевой baseline (нужен seeded backend). Follow-up: вынести `_V7Field`/`_V7PrimaryButton` в общий файл; выверить текст онбординг-слайдов; owner-визуальная приёмка.

**▶ Следующий шаг:** `/forge` по `.anws/v7/05_TASKS.md`: `T6.1.1` — полный
regression/security/reconciliation gate финального кандидата v7.

---

## 🗺️ Карта (Территориальная осведомленность)

Вот как организован этот проект:

| Путь | Описание | Протокол доступа |
|------|----------|------------------|
| `src/` | **Слой реализации**. Фактическая кодовая база. | Чтение/запись через Task. |
| `.anws/` | **Корень унифицированной архитектуры**. Содержит версии и историю изменений. | **Только чтение**(старые) / **Запись один раз**(новые). |
| `.anws/v{N}/` | **Текущая истина**. Последнее определение архитектуры. | Всегда ищите максимальную версию `v{N}`. |
| `.anws/changelog/` | **История изменений**. Записи обновлений `anws`. | Обслуживается автоматически, не удалять. |
| `Workflows` | **Рабочие процессы**. `/genesis`, `/blueprint` и др. | Читать соответствующие файлы процессов. |
| `.nexus-map/` | **База знаний**. Картография структуры кода. | Генерируется через `nexus-mapper`. |

## 🛠️ Реестр рабочих процессов (Workflows)

> [!IMPORTANT]
> **Приоритет процессов**: Когда задача соответствует какому-либо процессу или вы считаете, что она **очевидно, в основном или даже просто предположительно** подходит под сценарий процесса — **вы обязаны сначала прочитать соответствующий файл** и строго следовать шагам. Процессы — это тщательно разработанные протоколы, а не просто рекомендации.
>
> **Порядок запуска**:
> 1. Если задача соответствует сценарию, немедленно откройте файл процесса.
> 2. **Строго следуйте** шагам, описанным в процессе.
> 3. Делайте паузы на контрольных точках для подтверждения пользователем.

| Процесс | Когда запускать | Результат |
|---------|-----------------|-----------|
| `/quickstart` | Новый пользователь / Непонятно, с чего начать | Оркестрация других процессов |
| `/genesis` | Новый проект / Глобальный рефакторинг | PRD, Архитектура, ADRs |
| `/probe` | Перед изменениями / Приемка проекта | Отчет о рисках `.anws/v{N}/00_PROBE_REPORT.md` |
| `/design-system` | После genesis | Технический дизайн в `04_SYSTEM_DESIGN/*.md` |
| `/blueprint` | После genesis | Список задач `05_TASKS.md` + Wave-блоки в AGENTS.md |
| `/change` | Точечные правки существующих задач | Обновление TASKS + SYSTEM_DESIGN (только правки) |
| `/explore` | При исследовании новых технологий | Исследовательский отчет |
| `/challenge` | Перед принятием важных решений | Отчет о критике `07_CHALLENGE_REPORT.md` |
| `/forge` | Кодинг и выполнение | Код + Обновление Wave-блоков в AGENTS.md |
| `/craft` | Создание процессов/навыков/промптов | Документация Workflow / Skill / Prompt |
| `/upgrade` | После `anws update` | План обновления и миграция на новую версию |

---

## 📜 Конституция (The Constitution)

1. **Версия — это Закон**: Не «заплатки» в архитектуре, а «эволюция». Изменения требуют создания новой версии.
2. **Явный Контекст**: Все решения записываются в ADR, а не остаются в «памяти чата».
3. **Перекрестная Проверка**: Перед кодингом сверяйтесь с `05_TASKS.md`. Делаю ли я то, что запланировано?
4. **Эстетика**: Документация должна быть красивой. Используйте Markdown и Emoji.

---
## 🔄 Проектная зона сохранения (State Retention)

<!-- AUTO:BEGIN — Зона сохранения состояния (Не изменять границы блока вручную) -->

## 📍 Текущее состояние (Обновляется процессами)

> **Примечание**: Этот блок автоматически поддерживается процессами `/genesis`, `/blueprint` и `/forge`.

- **Последняя версия архитектуры**: `.anws/v7` (Financial & Lesson Integrity)
- **Активный список задач**: `.anws/v7/05_TASKS.md` — следующая задача `T6.1.1`
- **Фаза**: `/genesis`, `/design-system` и `/blueprint` завершены; выполняется `/forge`
- **Последнее обновление**: `2026-08-07`

### 🌊 Wave v7/S0 — Architecture Foundation ✅
_PRD подтверждён владельцем 2026-08-07. Concept model, Architecture Overview и ADR-007..010 фиксируют один существующий Flutter/NestJS/PostgreSQL runtime, `SYS-COMMERCE-INTEGRITY`, append-only payment lifecycle/reversal/exclusion, единый атомарный lesson transition и узкие client-finance capabilities Admin/Manager/Director со staff-visible reasons. Новые зависимости и deployable не вводятся. Следующий шаг `/design-system`: детальный дизайн v7._

### 🌊 Wave v7/S1 — Detailed Design ✅
_Commerce, Schedule, Client Card и Access/Audit спроектированы в `.anws/v7/04_SYSTEM_DESIGN/`. Challenge исправил one-time refund funding, protected mixed configuration publish и auto-completion bypass; открытых Critical/High нет. CH-V7-04 требует inventory всех ordinary finance queries и единого reporting exclusion. Следующий шаг `/blueprint`._

### 🌊 Wave v7/S2 — Blueprint ✅
_План прошёл шесть passes task review: 24 implementation tasks + 6 INT gates,
169 часов, прямое и обратное покрытие 11/11 требований и 11/11 stories,
открытых Critical/High нет. Реализация идёт волнами data → commerce → lesson
integrity → recurring plans → Client Card → release. Следующий шаг `/forge`:
`T1.1.1`._

### 🌊 Wave v7/S3 — Data Foundation ✅
_`T1.1.1..T1.1.4` и `INT-S0` закрыты 2026-08-07: migrations `0103..0105`
добавили payer/payment lifecycle/exclusions, plans/snapshots/note и restartable
legacy backfill без второго ledger. Down `0105→0103` и up прошли; targeted
96/96, typecheck/build, preflight 19/19 и commerce reconcile 13/13 зелёные;
inventory finance=164, lesson writes=13, unowned=0
(`docs/audits/v7-s0-data-foundation.md`). Следующий шаг `/forge`: `T2.1.1`._

### 🌊 Wave v7/S4 — Client Commerce 🚧
_`T2.1.1` закрыта 2026-08-07: подписанный purchase preview/commit блокирует
recipient+payer в стабильном UUID-порядке, проверяет обе branch-scopes и свежий
баланс, создаёт абонемент со всеми часами и один полный debit на счёте payer.
Personal account требует полной суммы; installment хранит отдельный график.
`T2.1.2` закрыта 2026-08-07: migration `0106`, единый lifecycle manual/due
payment records и opt-in due worker реализуют ровно три статуса; pending не
меняет баланс/долг, unpaid образует долг, а конкурентная верификация создаёт
один immutable ActualPayment. Legacy payment API делегирует тому же lifecycle;
найденный DELETE-trigger исправлен и защищён regression test. Gate: commerce
50/50, Actor Matrix/leak 9/9, full backend 152/152 suites и 1174/1174 tests,
typecheck/build, `0106` down→up, reconcile issues=0, inventory finance=192,
lesson writes=13, unowned=0. Следующий шаг `/forge`: `T2.1.3` — reversal и
единый reporting exclusion._

_`T2.1.3` закрыта 2026-08-07: migration `0107` добавила один
`security_invoker` reporting boundary для оплат, корректировок и payment
records. Paid reversal атомарно создаёт равную обратную проводку, exclusion,
audit/outbox и выдерживает concurrent/idempotent replay; pending/unpaid
получают technical void без денежного факта. Причина, актор и время остаются в
staff-only технической истории, а карточка/дашборды/аналитика/расписание/
таймлайн/экспорт исключают обе стороны. Due marker после void безопасно
создаётся повторно без потери истории. Gate: commerce 53/53, Actor Matrix/leak
9/9, full backend 152/152 suites и 1179/1179 tests, typecheck/build, `0107`
down→up, reconcile issues=0, inventory finance=233, reporting-safe reads=47,
lesson writes=13, unowned=0. Следующий шаг `/forge`: `T2.1.4` — отмена
абонемента и корректный refund._

_`T2.1.4` закрыта 2026-08-07: отмена абонемента рассчитывается от исходного
плательщика и разделяет подтверждённое финансирование и незакрытую часть.
Неиспользованная one-time покупка возвращается полностью даже без связанного
payment record; для рассрочки учитываются оплаченные части, прошлые возвраты,
использованные часы и активные резервы. Pending/unpaid записи закрываются
техническими exclusions, а один append-only credit исключает двойное
зачисление и выдерживает idempotent replay. Причина сохраняется в lifecycle,
audit и технической истории. Gate: commerce 55/55, Actor Matrix/leak 9/9,
full backend 152/152 suites и 1181/1181 tests, typecheck/build, reconcile
issues=0, inventory finance=241, reporting-safe reads=51, lesson writes=13,
unowned=0. Следующий шаг `/forge`: `T2.1.5` — client-finance capabilities,
scope, projections и audit reasons._

_`T2.1.5` закрыта 2026-08-07: production finance routes используют узкую
`commerce.client_finance.write`, legacy issue adapter инвентаризирован отдельно,
а каждая commerce mutation повторно проверяет актуальную capability внутри
транзакции до idempotency и денежных фактов. Recipient+payer проходят один
branch-scoped lock path и safe 404. Migration `0108` сохраняет отдельный
обязательный human `reason_text` (1..500) с loss-protected down; Client/Teacher
не получают technical reasons/comments, staff history bounded. Gate: commerce
57/57, Actor Matrix/leak 9/9, full backend 152/152 suites и 1188/1188 tests,
typecheck/build, `0108` down→up, reconcile issues=0/drift=0, route coverage
280/280, inventory finance=243, lesson writes=13, unowned=0
(`docs/audits/v7-client-finance-access.md`). Следующий шаг `/forge`: `INT-S1`._

_`INT-S1` закрыт 2026-08-07: PostgreSQL-backed цепочки purchase → installment →
pending/unpaid/paid → reversal/technical void → cancel/refund приняты для
recipient и отдельного payer. Commerce 57/57, Actor Matrix/leak 9/9, full backend
152/152 suites и 1188/1188 tests, typecheck/build зелёные. Два read-only
preflight дали одинаковый digest при 19/19 checks и findings=0; два v7 reconcile
дали `issues=[]`, signed v4 reconciliation — drift=0. Route coverage 280/280,
inventory finance=243/reporting-safe=51/lesson writes=13/unowned=0
(`docs/audits/v7-int-s1-client-commerce.md`). Следующий шаг `/forge`: `T3.1.1`._

### 🌊 Wave v7/S5 — Lesson Integrity 🚧
_`T3.1.1` закрыта 2026-08-07: единый immutable CRM Configuration snapshot
получил 7 типов списания и независимые 5 правил оплаты преподавателю, строгую
нормализацию 0–200%, minor units, contexts, archive-only stable keys и impact.
School default и sparse branch override versioned; Director publish/rollback
приняты. Manager может публиковать обычную branch-настройку только при
byte-equivalent защищённых сегментах; mixed publish отклоняется внутри
транзакции с writes=0 по `config.commerce.manage`. Migration `0109` down→up и
loss guard PASS. Gate: config 6/6, Actor Matrix/leak 9/9, full backend 152/152
suites и 1191/1191 tests, typecheck/build, reconcile issues=0/drift=0,
inventory finance=243/lesson writes=13/unowned=0
(`docs/audits/v7-commerce-catalogs.md`)._

_`T3.1.2` закрыта 2026-08-07: typed Commerce decision рассчитывает client
share 0–200%, fixed penalty и независимые teacher none/standard/percent/fixed/
hourly rules целочисленно, создавая exact N immutable client facts + один
teacher fact. Snapshot хранит key/label/color/share/rule/default/actual/reason и
раздельную effective revision каталогов. Subscription capacity проверяется под
lock: недостаток даёт writes=0, 200% атомарно расширяет reserve, zero settlement
освобождает его. Concurrent replay 8/8 стабилен; изменение catalog после записи
не меняет историю. Gate: calculation/configured PostgreSQL 9/9, commerce 58/58,
schedule regression 8/8, full backend 153/153 suites и 1197/1197 tests,
typecheck/build, reconcile issues=0, inventory unowned=0
(`docs/audits/v7-lesson-settlement-facts.md`). Следующий шаг `/forge`: `T3.1.3`._

_`T3.1.3` закрыта 2026-08-07: reschedule/cancel/explicit settle сведены в один
typed transition с HMAC preview token. Preview исполняет тот же Commerce port в
PostgreSQL savepoint; commit атомарно фиксирует source/successor, reservation,
exact client/teacher facts, transition, human reason, audit/outbox. Conflict,
stale fingerprint, исчерпанные часы и injected Commerce fault оставляют source
scheduled и 0 successor/facts. Group snapshot и per-client decisions сохраняются;
boolean adapter удалён. Gate: schedule 26/26, commerce 58/58, full backend
153/153 suites и 1197/1197 tests, typecheck/build, reconcile issues=0, access
288/288, inventory routes=300/DTO=729/finance=244/lesson writes=13/unowned=0
(`docs/audits/v7-unified-lesson-transition.md`). Следующий шаг `/forge`: `T3.1.4`._

_`T3.1.4` закрыта 2026-08-07: completion worker теперь ставит истёкший
Lesson в `settlement_pending` без transition/finance facts, а explicit settle
создаёт их ровно один раз. Общий guard оставляет direct PATCH только для notes;
inventory fail-closed отклоняет неизвестного temporal caller. Atomic bulk
preview/commit использует одну причину, HMAC token, idempotency/audit/outbox и
одну PostgreSQL transaction до 500 Lessons; stale второй элемент откатывает
первый полностью. Migration `0110` down→up PASS. Gate: schedule 27/27, full
backend 154/154 suites и 1209/1209 tests, typecheck/build, Flutter analyze и
palette 7/7, access 290/290, inventory routes=302/DTO=739/finance=243/lesson
mutations=7/unknown=0/unowned=0 (`docs/audits/v7-lesson-no-bypass.md`).
Следующий шаг `/forge`: `T3.1.5`._

_`T3.1.5` закрыта 2026-08-07: drag/drop, resize, editor, details и Client Card
tray используют один adaptive `LessonDecisionController` с обязательными
reason, settlement и независимой оплатой преподавателю до mutation. Preview
показывает source/successor, client hours/money, teacher amount, conflicts и
non-color markers; retry сохраняет ввод и idempotency identity. Старые Flutter
`updateLesson`/raw PATCH/direct delete/optimistic undo удалены. Gate: targeted
schedule/client 72/72, Flutter analyze clean, backend catalog/RBAC 60/60,
typecheck/build, inventory routes=303/reachable=255/lesson mutations=7/
unknown=0/unowned=0 (`docs/audits/v7-lesson-decision-flow.md`). Следующий шаг
`/forge`: `INT-S2`._

_`INT-S2` закрыт 2026-08-07: config → normal/paid-miss/free/penalty/group →
move/cancel/settle → worker и единый Flutter LessonDecision flow приняты без
обходов. Targeted PostgreSQL/RBAC 18/18 suites и 130/130, full backend 154/154
suites и 1211/1211, full Flutter 626/626 и analyze clean. Windows и Android 15
API 35 interaction smoke 1/1 на каждой платформе. Reconcile ×2 `issues=[]`,
preflight ×2 19/19 с одинаковым digest, access 291/291, shadow unexplained=0,
inventories unknown/unowned=0 (`docs/audits/v7-int-s2-lesson-integrity.md`).
Следующий шаг `/forge`: `T4.1.1`._

### 🌊 Wave v7/S6 — Recurring Plans ✅
_`T4.1.1` закрыта 2026-08-07: один versioned/idempotent Plan aggregate
атомарно создаёт named individual/group plan, N existing series, bounded
unique Lessons и явные participant→subscription assignments. Open-ended plans
продлевает существующий worker; group Lessons получают immutable participant
snapshots и per-client reservations. Effective edit закрывает rows накануне,
сохраняет past snapshots/exception lineage, освобождает только заменяемые
future reservations и создаёт continuations с точной даты. Concurrent create
даёт commit+replay, concurrent edit — один commit+stale reject. Gate: targeted
PostgreSQL 3/3, full backend 155/155 suites и 1217/1217 tests,
typecheck/build, reconcile `issues=[]`, access 294/294, inventories
routes=306/DTO=768/finance=244/lesson mutations=7/unknown=0/unowned=0
(`docs/audits/v7-schedule-plan-aggregate.md`). Следующий шаг `/forge`:
`T4.1.2`._

_`T4.1.2` закрыта 2026-08-07: actor-bound HMAC preview фиксирует Plan,
last date/reason и точный Series/Lesson/reservation impact. Один versioned,
idempotent commit заканчивает Plan/active Series, отменяет только более поздние
unsettled Lessons через lifecycle transition с zero-financial decision,
освобождает reservations и сохраняет past/terminal history. Fault injection
подтвердил полный rollback, stale preview — zero partial write. Actor-scoped
tray использует opaque `(scheduled_at,id)` cursor, page ≤40, markers без
hidden finance и no duplicates; list ограничивает ended history двадцатью
планами. Gate: targeted PostgreSQL 6/6, full backend 155/155 suites и
1223/1223 tests, typecheck/build, reconcile `issues=[]`, access 297/297,
shadow unexplained=0, inventories routes=309/DTO=776/finance=246/lesson
mutations=7/unknown=0/unowned=0 (`docs/audits/v7-schedule-plan-end-tray.md`).
Следующий шаг `/forge`: `T4.1.3`._

_`T4.1.3` закрыта 2026-08-07: каноническая карточка Student показывает
active expanded/ended collapsed individual и group планы сразу после
предпочтительного расписания; отсутствие предпочтения не скрывает планы или
fallback Lessons. Каждому плану принадлежит bounded двухстрочная tray с
authoritative lifecycle/settlement/relation markers и cursor arrows. Create,
effective edit и end переиспользуют существующие v7 adaptive surfaces и один
`PreferredScheduleEditor`; end требует reason, impact preview и стабильный
idempotency identity. Forbidden role не создаёт provider и не делает schedule
requests. Group plan доступен участнику одним SQL projection с teacher/room/
branch labels без N+1. Gate: responsive widget 6/6 (360/840/1200, text 1.25),
Flutter full 632/632 и analyze clean; Plan PostgreSQL 6/6, backend full 155/155
suites и 1223/1223 tests, typecheck/build; access 297/297, shadow access=1782/
schedule=2000/unexplained=0, reconcile `issues=[]`, inventories unowned=0
(`docs/audits/v7-client-card-recurring-plans.md`). Следующий шаг `/forge`:
`INT-S3`._

_`INT-S3` закрыт 2026-08-07: individual/group create, effective edit, end и
history подтверждены одним Plan aggregate от PostgreSQL до Client Card.
Targeted backend 6/6 и Flutter 28/28; Windows x64 и Android 15 API 35 прошли
одинаковый on-device lifecycle 1/1, включая Back с сохранением раскрытого
контекста, create/edit, reason→preview→commit и ended history. Android logcat
без Flutter/FATAL exceptions. Двойной reconcile вернул `issues=[]`; полный
baseline остаётся Flutter 632/632 и backend 155/155 suites, 1223/1223 tests,
access 297/297, shadow unexplained=0, inventories unowned=0
(`docs/audits/v7-int-s3-recurring-plans.md`)._

### 🌊 Wave v7/S7 — Client Workspace 🚧

_`T5.1.1` закрыта 2026-08-07: каноническая Student Card подключает
signed purchase preview/commit с другим payer, три payment status,
verification/reversal и technical history. Общее меню Actions удалено,
subscription/homework/archive команды остались в профильных секциях.
Gate: Flutter analyze clean и 633/633; commerce 58/58; backend 155/155 suites,
1223/1223 tests; двойной reconcile `issues=[]`
(`docs/audits/v7-client-card-commerce-ui.md`). `T5.1.2` добавила одну
versioned Lead/Student note с optimistic concurrency и conversion preservation,
а также bounded staff-only operational history с точными reason,
author и time. Teacher/Client не делают скрытых запросов. Gate:
Flutter analyze clean и 635/635; backend 155/155 suites, 1227/1227 tests;
двойной reconcile `issues=[]`
(`docs/audits/v7-client-note-operational-history.md`). `T5.1.3` вынесла
Subscriptions и Progress в отдельные Lead/Student sections, удалила
дубль issue из action-bar, добавила desktop section-jumps и сохранила
payments/installments collapsed. Gate: Flutter analyze clean и 637/637;
routes=22, reachable=260, wire=274/274, unowned=0; server diff empty
(`docs/audits/v7-client-card-composition.md`). `T5.1.4` встроила два
независимых Director-only commerce-каталога в тот же versioned Configuration:
color+text preview, archive/reorder, exact money/percent conversion,
draft/dirty Back, impact publish и rollback. Manager controls отсутствуют,
Admin/Teacher/Client config requests=0. Gate: Flutter analyze clean и 642/642;
configuration role/dirty/back 10/10, backend PostgreSQL 7/7; inventories
unowned=0 (`docs/audits/v7-director-commerce-catalog-ui.md`). Следующий шаг
`/forge`: `INT-S4`._

_`INT-S4` закрыт 2026-08-07: одна production Client Card принята для
Lead/Student и ролей 3/4/5. Реальные login/restart/logout/relogin прошли на
Windows и Android 15, детерминированная card story — `3/3` на каждой
платформе. Targeted Flutter `41/41`, backend PostgreSQL/RBAC `102/102`;
Teacher forbidden requests=0, duplicate actions=0, причины и техистория
видимы staff. Device gate нашёл и закрыл dialog overflow при IME-анимации;
Android app logcat после повтора чист. Inventories routes=22,
reachable=260/261, wire=274/274, finance=251, lesson mutations=7,
unknown/unowned=0, server diff empty
(`docs/audits/v7-int-s4-client-workspace.md`). Следующий шаг `/forge`:
`T6.1.1`._

### 🌊 Wave v7/S8 — Final Candidate ⛔

_`T6.1.1` выполнена до единственного внешнего security blocker: backend 155/155
suites и 1227/1227 tests, Actor Matrix/leak 9/9, Flutter analyze и 642/642,
двойные inventory/preflight/reconcile с unowned=0/drift=0, current tracked
Gitleaks=0, npm/Trivy/Semgrep Critical/High=0. Windows и Android прошли
real-account relogin и v7 story diagnostics. History-aware scan доказал, что один
текущий HolliHop credential присутствует в 23 находках трёх старых коммитов.
Версия не повышена, release artifacts не выпущены, задачи не закрыты. Требуются
ротация ключа у провайдера и явное разрешение на coordinated history rewrite;
затем gate запускается заново (`docs/audits/v7-t6-regression-security-blocked.md`)._

_History rewrite отрепетирован в отдельном local clone без remotes: два имени
старого bugreport и три уникальных credential/token значения очищены во всех
revisions; сохранены 761/761 commits, 4/4 heads и 22/22 tags, current HEAD tree
byte-identical, history Gitleaks=0. `origin` не затронут. Production runbook
использует ref freeze и explicit expected-old-SHA leases
(`docs/audits/v7-history-rewrite-rehearsal.md`)._

### 🌊 Wave v6/S0 — Evidence & UX Foundation ✅
_Owner подтвердил полное выполнение v6. `V6-001..005` и `INT-S0` закрыты 2026-08-04: воспроизводимый generator покрывает 21 GoRouter route, 248/259 production-reachable Dart files, 256/256 service calls, route/surface/navigation/input/back ownership с unowned=0; v4 inventory обновлён и снова проходит stale-check. Baseline: Flutter analyze clean и 486/486 tests, backend typecheck/build clean, 150/150 suites и 1160/1160 tests, actor/payload 9/9, targeted workflow contracts 68/68 (`docs/audits/v6-s0-baseline.md`). Следующий шаг `/forge`: `V6-101` canonical location adapter._

### 🌊 Wave v6/S1 — Navigation Kernel ✅
_`V6-101..105` и `INT-S1` закрыты 2026-08-04: один `EntityRouteRegistry` обслуживает canonical metadata/direct links/breadcrumbs, production workspace смонтирован для staff roles, account-scoped tabs и per-tab Back/Forward переживают restart и безопасно очищаются при logout/role change. Один typed navigation path управляет desktop current/new-tab и compact GoRouter stack, сохраняет source state и не prefetch-ит forbidden entity. Gate: Flutter analyze clean, 503/503 tests, Windows debug build PASS, inventory stale-check routes=21/reachable=255/workspaceProduction=2/unowned=0, registry definitions=1, direct entity route bypass=0, server diff empty (`docs/audits/v6-int-s1-navigation-workspace.md`). Следующий шаг `/forge`: `V6-201` adaptive surface policy._

### 🌊 Wave v6/S2 — Adaptive Surfaces & Mobile Back ✅
_`V6-201..205` и `INT-S2` закрыты 2026-08-04: adaptive surface/expandable sheet/Back/dirty contracts поставлены; Lesson quick view использует sheet→drawer, длинный Lesson edit — fullscreen route, searchable selector — sheet→drawer, delete — concise confirmation. CH-02/03 закрыты: duplicate content/mutation=0, один ahead-of-time Back/dirty contract проверен реальными Android edge gestures. Gate: Flutter analyze clean, targeted 29/29 и full 523/523; Android API 35 sheet/Back/modal 3/3, Windows modal 1/1, visual token review/logcat clean; widths 360/600/839/840, keyboard/SafeArea PASS; inventory unowned=0, wire baseline unchanged, server diff empty (`docs/audits/v6-int-s2-adaptive-surfaces-back.md`). Следующий шаг `/forge`: `V6-301` explicit desktop scrollbar ownership._

### 🌊 Wave v6/S3 — Desktop Input & Visual Consistency ✅
_`V6-301..305` и `INT-S3` закрыты 2026-08-04. Desktop получил явное владение 13 scroll surfaces, mouse wheel/Shift+wheel/edge handoff, keyboard focus/semantic tooltips для всех 91 production IconButton и единые loading/empty/error/forbidden states; duplicate create action в общих задачах удалён. Official Inter 4.1 bundled локально, motion использует 160/240/300 ms tokens и отключается через reduced motion; responsive/text-scale matrix 360/600/840/1000/1200 проходит. CH-05/07/10 закрыты. Gate: Flutter analyze clean, targeted 29/29 и full 538/538; Windows visual 6/6 и physical mouse 1/1, exception=0; inventory routes=21/reachable=260/state gaps=0/unowned=0, wire baseline и зависимости без изменений, server diff empty (`docs/audits/v6-int-s3-desktop-ui-foundation.md`). Следующий шаг `/forge`: `V6-401` canonical client workspace route._

### 🌊 Wave v6/S4 — Client Workspace, Lessons & Payments ✅
_`V6-401..406` и `INT-S4` закрыты 2026-08-04: canonical Student/Lead workspace, preferred schedule, bounded branch Month/Week/Day calendar, immutable Payments, effective configurable Student funnel и typed linked navigation смонтированы в production routes. CH-06/11 закрыты bounded actor-visible requests и независимыми relation/lifecycle markers с non-color legend. Gate: Flutter analyze clean, V6 65/65 и full 586/586; Windows + Android 15 device 2/2; backend typecheck/build, commerce 38/38 и client/funnel/actor scope 21/21; inventory routes=21/reachable=264/workspaceProduction=2/unowned=0, wire 260/260 owned, server diff empty (`docs/audits/v6-int-s4-client-workspace.md`). Следующий шаг `/forge`: `V6-501` canonical tasks._

_`V6-407` закрыта 2026-08-07: desktop Client Card сведена в один scrollable workspace, rail остаётся видимым, а все staff entry points canonicalize-ятся под `Клиенты > Лид/Ученик > имя`. Students и Leads используют общий toolbar/FAB; один обязательный Advertising source UUID переносится Lead→Student миграцией `0102`, legacy `adSource` скрыт без потери labels. Gate: Flutter analyze clean и full suite PASS; backend typecheck/build, 152/152 suites и 1159/1159 tests; migration down→up; inventory routes=22/reachable=253/workspaceProduction=2/unowned=0; Windows/APK release build и APK v2 signature PASS (`docs/audits/v6-final-candidate-156.md`)._

### 🌊 Wave v6/S5 — Tasks, Analytics & Configurable CRM ✅
_`V6-501` закрыта 2026-08-04: production destination, client cards, Lead quick action и Overview используют один SharedTask provider/model; legacy UUID losslessly resolve-ится через canonical link, detail/history и typed entity transition общие. Write controls fail-closed от уже загруженного capability snapshot, duplicate production routes/providers/actions=0. Gate: Flutter analyze clean, targeted 14/14 и full 590/590; backend typecheck/build, task 5/5, route-policy batch 41/41 и full 151/151 suites + 1169/1169 tests; inventory routes=21/reachable=261/wire=261/261/unowned=0 (`docs/audits/v6-canonical-tasks.md`). Следующий шаг `/forge`: `V6-502` task audience/branch UX и language audit._

_`V6-502` закрыта 2026-08-04: backend preview показывает fixed people и dynamic branch/school membership до отправки, дедуплицирует пересечения и возвращает reconciled count после create/update; неизвестный preview блокирует submit. Picker исключает Client accounts, school selector заменяет избыточные узкие selectors, task language унифицирован. Editor использует v7 adaptive drawer на Windows и expandable full-width sheet на Android. Gate: Flutter analyze clean, targeted 33/33 и full 593/593; Windows/Android 15 device 2/2; backend typecheck/build, tasks 6/6, route policy 37/37 и full 151/151 suites + 1170/1170 tests; inventory routes=21/reachable=261/wire=262/262/unowned=0 (`docs/audits/v6-task-audience-ux.md`). Следующий шаг `/forge`: `V6-503` unified dashboard filters._

_`V6-503/504` закрыты 2026-08-04: production использует один capability-projected dashboard вместо отдельных «Отчёты»/«Финансы»/«Сводка»; единый period/branch filter сохраняется в workspace/direct-link state и нормализованно применяется к clients/lessons/permitted finance/export. Секции имеют независимые loading/error/retry, count↔drilldown reconciliation, а tasks явно помечены как current queue без неприменимого period/scope. Manager/Client/Teacher/Admin не создают school-finance provider/request; forbidden dashboard actor-safe. Legacy finance dashboard/KPI implementation удалены. Gate: Flutter analyze clean, targeted dashboard/realtime 14/14 и full 598/598; backend reporting scope + payload leak 10/10; inventory routes=21/reachable=259/workspaceProduction=2/unowned=0, server diff empty (`docs/audits/v6-unified-dashboard.md`)._

_`V6-505/506` и `INT-S5` закрыты 2026-08-04: production route `/crm/configuration` объединяет categories, Lead/Student fields, layout/placements, reusable option sets, allowlisted business numbers и immutable revisions. School default + sparse branch override, draft→impact preview→publish и rollback используют один expected-version/transaction contract; существующие формы потребляют effective metadata. Три typed capability поддерживают Director delegation, assigned-branch Manager и hard-deny Admin/Teacher/Client; forbidden UI не делает config requests, audit/reason/invalidation сохранены. Уточнение владельца от 2026-08-06 оставило `Варианты для полей` единственным UI-источником значений select-полей; старые inline-списки losslessly преобразуются в наборы. Gate: Flutter analyze clean и full 613/613; backend config/access 6/6 suites + 89/89, full 151 suites + exact repaired preflight 1/1; typecheck/build, migration 0097 down→up, inventory routes=22/reachable=260/unowned=0 (`docs/audits/v6-unified-crm-configuration.md`). Следующий шаг `/forge`: `V6-601` capability-projected navigation for five personas._

### 🌊 Wave v6/S6 — Role Workspaces & Cross-App UX Audit ✅
_`V6-601..605` и `INT-S6` закрыты 2026-08-04: capability-projected shell enforce-ит persona ceiling и effective snapshot; Admin получает только Chat/Schedule/Clients и task hard-deny, Manager — operational workspace без school finance, Director — finance/config/access. Client self-scope и Teacher assigned-only Day/Week read-only workflow, Back/deep links, routed states, semantics, scrollbars и single primary actions приняты. 26-point pack готов к owner execution. Gate: Flutter analyze clean и 601/601; role/workflow 72/72, UX/accessibility 24/24; backend 152/152 suites и 1177/1177, invalidation/actor/leak 10/10, typecheck/build; migration 0098 down→up; Windows + Android 15 device 2/2; inventory routes=22/reachable=260/state gaps=0/unowned=0 (`docs/audits/v6-role-workspace-acceptance.md`, `docs/audits/v6-user-workflow-acceptance.md`). Следующий шаг `/forge`: `V6-701` owner real-account UAT._

_Финальный инженерный кандидат обновлён до `1.2.3+156` 2026-08-07: поверх проверенного `1.2.2+155` добавлены единая длинная Client Card, постоянный navigation rail, canonical client route tails, общий Leads/Students board contract и один обязательный Advertising source Lead→Student. Gate: Flutter analyze/full suite, backend 152/152 suites и 1159/1159 tests, migration `0102` down→up, inventory unowned=0, Windows release и APK v2 signature PASS (`docs/audits/v6-final-candidate-156.md`). Следующий шаг остаётся `V6-701` owner UAT на аккаунтах 1..5._

### 🌊 Wave v4/S0 — Baseline & Evidence
_`INT-S0` закрыт 2026-07-25: detached clean revision прошёл current-state inventory, lock install, backend typecheck/build, explicit platform PostgreSQL 5/5, full backend 103/103 suites и 929/929 tests, два стабильных read-only preflight-run, signed clean/drift reconciliation, Flutter analyze и 400/400 tests; skipped integration suites=0, lock/tracked diff=0._

### 🌊 Wave v4/S1 — Access Control Foundation
_`T2.1.1` закрыта: migration `0076`, 20 versioned capabilities, 6 active role packages, 120 explicit allow/deny facts, typed registry/OpenAPI parity и fail-closed unknown key; PostgreSQL 6/6, full backend 104/104 suites и 935/935 tests (`docs/audits/v4-capability-registry.md`). `T2.1.2` закрыта: effective access следует порядку active/registry → root/invariant → package → override → resource scope; Teacher hard-deny нельзя снять override, `system_admin` получает root allow с resource validation, Director управляет только ролями ниже себя, Admin/Manager denied, последний active `system_admin` защищён; exact suite 30/30, full backend 105/105 suites и 965/965 tests (`docs/audits/v4-hard-invariant-evaluator.md`). `T2.2.1` закрыта: migration `0077`, v4 role/package/override API, expected versions, idempotent replay, confirmation reset, before/after/reason audit и minimal outbox атомарны; Manager=403, Director только ниже себя, `system_admin` только через emergency surface; PostgreSQL 6/6, migration down→up, full backend 106/106 suites и 972/972 tests (`docs/audits/v4-access-mutations.md`). `T2.2.2` закрыта: 6 actor-aware projection profiles, self/assigned/branch scope до сериализации, Teacher allowlist для client/search/schedule/chat/export с нулём contacts/representatives/finance/subscriptions/cost/debt, отдельные cache/OpenAPI partitions; exact 19/19, full backend 107/107 suites и 991/991 tests (`docs/audits/v4-client-projections.md`). `T2.2.3` закрыта: migration `0078`, независимые `shared_with_teacher`/`version`, assigned Teacher SQL projection, атомарный staff toggle с idempotency/audit/outbox и body-free realtime; PostgreSQL 8/8, migration down→up, full backend 108/108 suites и 999/999 tests (`docs/audits/v4-comment-sharing.md`). `T2.3.1` закрыта: dynamic capability intersection встроен в JWT boundary, 234/234 private routes имеют registry mapping + resource scope, unexplained allow=0; repository scope чужой группы для Teacher закрыт, targeted 56/56, full backend 110/110 suites и 1026/1026 tests (`docs/audits/v4-access-coverage.md`). `T2.3.2` закрыта: post-commit safe `access.invalidated` с monotonic accessVersion доставляется всем user sessions и при package change всем authenticated sockets, Flutter refetch-ит session projection/router, следующий REST request читает current DB policy, `system_admin` скрыт из profile/staff business lists; exact two-session PostgreSQL 1/1, full backend 111/111 suites и 1028/1028 tests, Flutter analyze clean и 401/401 tests (`docs/audits/v4-access-invalidation.md`). `T2.4.1` закрыта: PostgreSQL Actor Matrix проверяет 234 private routes × 6 actors = 1404 решений (1146 allow, 258 deny), unknown/missing scopes/unexplained allow=0; Teacher JSON/search/schedule/chat/export/realtime/log scan leaks=0, central logger дополнительно маскирует cost/debt/payment/subscription/comment/representative fields; exact 8/8, full backend 113/113 suites и 1037/1037 tests (`docs/audits/v4-actor-matrix.md`). Следующий шаг `/forge`: `T3.1.1` единый ClientRef resolver/search._

### 🌊 Wave v4/S2 — Lesson Integrity
_`T3.1.1` закрыта: единый `ClientRefDto` требует явный `{type: lead|student, id}`, resolver и общий поиск применяют Client/Teacher resource scope внутри PostgreSQL, projection содержит только actor-safe ФИО/type/lifecycle, чужие UUID дают safe 404, архивные записи — стабильный tombstone; exact PostgreSQL 6/6 (`docs/audits/v4-client-ref.md`). `T3.1.2` закрыта: migration `0079` нормализует versioned Lead sources, `source_id`, system/custom field definitions и typed values с lossless legacy backfill; strict Lead/Student validators дают field-level 422 и phone normalization warning, Director/system_admin config CRUD versioned/archivable, смена типа с values заблокирована; down→up PASS, exact PostgreSQL 6/6, Actor Matrix 244 routes × 6 actors = 1464/1464, full backend 116/116 suites и 1051/1051 tests, inventory 256 routes/561 DTO fields/0 unowned (`docs/audits/v4-client-config.md`). `T3.2.1` закрыта: публичный Lead webhook переведён на HMAC-SHA256 + 300 s replay window и UUID ingestion key, strict v4 Lead payload, Platform Integrity transaction Lead+audit+`inbound.lead.created`; migration `0080` добавляет unique `inbound_id`, duplicate возвращает тот же Lead даже после архивации source, manual/chat создают 0 inbound notifications; down→up PASS, exact PostgreSQL 1/1, targeted 48/48, Actor Matrix 1464/1464, full backend 117/117 suites и 1050/1050 tests, inventory 256 routes/558 DTO fields/0 unowned (`docs/audits/v4-inbound-lead.md`). `T3.2.2` закрыта: migration `0081` создаёт/backfill-ит unique `ClientConversionLink`; отдельная strict conversion command под advisory lock даёт один Student/link при concurrent requests, переносит compatible custom values и client relations, subscription conversion пишет тот же link; source Lead archive доступен только Director/system_admin и не затрагивает Student; down→up PASS, exact PostgreSQL 1/1, Actor Matrix 246 routes × 6 = 1476/1476, full backend 118/118 suites и 1051/1051 tests, inventory 258 routes/559 DTO fields/0 unowned (`docs/audits/v4-client-conversion.md`). `T3.2.3` закрыта: migration `0082` добавляет monotonic Lead/Student version и aggregate sync; единый batched preview собирает future lesson/task/subscription/finance impact, archive требует Director/system_admin + expectedVersion/confirm/reason и атомарно пишет tombstone/audit/outbox, повтор идемпотентен, conversion/user/fact links сохраняются; down→up PASS, exact PostgreSQL 1/1, Actor Matrix 248 routes × 6 = 1488/1488, full backend 119/119 suites и 1053/1053 tests, inventory 260 routes/564 DTO fields/0 unowned (`docs/audits/v4-client-archive.md`). `T4.1.1` закрыта: migration `0083` добавляет explicit Lesson lifecycle/version, immutable snapshots/transitions, unique terminal/financial references, predecessor/successor и terminal reservation lifecycle; legacy statuses синхронизируются compatibility trigger-ом, aggregate version монотонна; down→up PASS, exact PostgreSQL 1/1, Actor Matrix 1488/1488, full backend 120/120 suites и 1054/1054 tests, inventory 260 routes/564 DTO fields/0 unowned (`docs/audits/v4-lesson-lifecycle-schema.md`). `T4.1.2` закрыта: migration `0084` добавляет IANA timezone, weekly/exception BranchHours, recurring/interval TeacherAvailability и effective-dated multi-branch assignments; versioned reference API даёт детерминированные UTC intervals на DST boundary, Teacher read self-only, operational writes следуют capability package; preflight показывает отдельный active-Teacher-without-branch blocker; down→up PASS, exact 2/2 suites и 5/5 tests, Actor Matrix 252 routes × 6 = 1512/1512, full backend 122/122 suites и 1061/1061 tests, inventory 264 routes/566 DTO fields/0 unowned (`docs/audits/v4-schedule-reference.md`). `T4.2.1` закрыта: единый `ScheduleConstraintEngine` применяет half-open interval rules, BranchHours, TeacherAvailability/Branch и indexed Teacher/Client/Room conflict arms с `excludeLessonId`; все structured violations возвращаются детерминированно с resource/Lesson refs; exact 2/2 suites и 6/6 tests, full backend 124/124 suites и 1067/1067 tests (`docs/audits/v4-schedule-constraint-engine.md`). `T4.2.2` закрыта: POST/PATCH Lesson используют единый versioned/idempotent command, complete effective draft, immutable financial/completion snapshot и один constraint path; create/edit/drag дают одинаковые violations, legacy force bypass закрыт; exact PostgreSQL 1/1, Actor Matrix 1512/1512, full backend 125/125 suites и 1068/1068 tests, inventory 264 routes/573 DTO fields/0 unowned (`docs/audits/v4-lesson-write-parity.md`). `T4.2.3` закрыта: migration `0085`, finite weekly recurrence разворачивается в IANA timezone филиала, все occurrences до первого write проходят общий validator/constraint engine, Series+Lessons+snapshots+audit/outbox атомарны и idempotent; Nth conflict возвращает failedIndex/violations и persisted=0, DST series создаётся полностью; down→up PASS, exact PostgreSQL 1/1, Actor Matrix 1512/1512, full backend 126/126 suites и 1069/1069 tests, inventory 264 routes/584 DTO fields/0 unowned (`docs/audits/v4-atomic-lesson-series.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.2.4` atomic reschedule/cancel._

_Актуализация 2026-07-26: `T4.2.4` закрыта: preview/confirm reschedule/cancel требует expected version, reason и явное финансовое решение; successor/predecessor и `LessonTransition` создаются в одной Platform Integrity transaction, а конфликт или сбой commerce-boundary откатывает source/successor/audit целиком. Exact PostgreSQL 1/1, Actor Matrix 1536/1536, access coverage 256/256, full backend 127/127 suites и 1070/1070 tests, inventory 268 routes/593 DTO fields/0 unowned (`docs/audits/v4-lesson-transitions.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.2.5` удалить attendance write-domain и ввести derived metric._

_Актуализация 2026-07-26: `T4.2.5` закрыта: attendance endpoint/service/DTO и Flutter controls удалены, generic Lesson status write закрыт; migration `0086` оставляет `lesson_participation` read-only legacy evidence и создаёт metric view только из `successfully_completed`. Exact 2/2, migration down→up PASS, Actor Matrix 1524/1524, access coverage 254/254, full backend 127/127 suites и 1059/1059 tests, Flutter analyze clean и 398/398 tests, inventory 266 routes/591 DTO fields/0 unowned/0 attendance mutations (`docs/audits/v4-no-attendance-domain.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.3.1` перешить Lesson form и conflict UX._

_Актуализация 2026-07-26: `T4.3.1` закрыта: Flutter Lesson form использует единый actor-scoped ClientRef selector, независимый trial marker и explicit immutable completion/financial/compensation snapshot; edit/drag versioned, mutation metadata стабильно при retry, legacy `force` bypass удалён. Preview и authoritative structured violations блокируют запись, показывают resource refs и ссылки на конфликтующие Lesson. Exact widget 4/4 + client-search regression 1/1, schedule service 53/53, full backend 127/127 suites и 1059/1059 tests, Flutter analyze clean и 399/399 tests (`docs/audits/v4-lesson-form-conflict-ux.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.3.2` state/reservation color projections._

_Актуализация 2026-07-26: `T4.3.2` закрыта: единый Flutter mapper вычисляет neutral/success/rescheduled token только из authoritative Lesson lifecycle + terminal reservation; локальные status colors удалены из schedule, client history и linked cards, trial везде остаётся отдельным золотым marker. Read-only Lesson projection дополнена последним `reservationState`, editable color/type отсутствует. Exact palette 6/6, trial regression + palette 7/7, full backend 127/127 suites и 1059/1059 tests, Flutter analyze clean и 405/405 tests (`docs/audits/v4-lesson-state-palette.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.3.3` read-only Teacher calendar День/Неделя._

_Актуализация 2026-07-26: `T4.3.3` закрыта: Teacher route открывает responsive read-only calendar только День/Неделя с loading/empty/error/retry, assigned-only Lesson query и limited client/history/homework drilldown. Edit/create/drag/reschedule/cancel/attendance affordances удалены; Flutter выполняет только actor-scoped GET, прямой Teacher Lesson update подтверждён PostgreSQL `403` без изменения aggregate. Exact widget/route 5/5, identity regression 1/1, direct-write PostgreSQL 2/2, full backend 127/127 suites и 1060/1060 tests, Flutter analyze clean и 410/410 tests (`docs/audits/v4-teacher-calendar-read-only.md`). `T4.4.1` ждёт `T8.2.1`; следующий доступный шаг `/forge`: `T5.1.1` idempotent Lesson settlement port._

_Актуализация 2026-07-29: `T5.1.1` закрыта: transaction-scoped Lesson settlement сериализуется по `lessonId` и создаёт ровно один immutable client charge/debt fact и один teacher compensation fact из valid LessonSnapshot. Teacher compensation поддерживает только `fixed/hourly/none`; hourly использует snapshot duration и округление до minor units, none даёт нулевой fact, процентная оплата преподавателя не добавлена. Migration `0087` down→up PASS, exact PostgreSQL 2/2, Lesson regression 7/7, Actor Matrix/leak 8/8, full backend 128/128 suites и 1062/1062 tests, typecheck/build clean (`docs/audits/v4-lesson-settlement.md`). `T3.2.4` ждёт `INT-S3`, `T4.4.1` ждёт `T8.2.1`; следующий доступный шаг `/forge`: `T5.1.2` catalog/snapshot/ledger schema._

_Актуализация 2026-07-29: `T8.2.1` закрыта: migration `0088` добавляет durable Lesson completion claims с `FOR UPDATE SKIP LOCKED`, lease/reclaim, bounded backoff и видимым poison; единая Platform Integrity transaction терминализирует Lesson, создаёт settlement facts, transition, reservation result, audit/outbox и completed claim без дублей. Readiness показывает backlog/retry/poison/oldest due. Exact PostgreSQL 4/4, kill-before/after-commit и two-worker PASS, migration down→up PASS, Lesson/platform regression 18/18, Actor Matrix/leak 8/8, full backend 129/129 suites и 1067/1067 tests, typecheck/build clean, inventory 266 routes/591 DTO fields/0 unowned (`docs/audits/v4-lesson-completion-worker.md`). `T3.2.4` ждёт `INT-S3`; следующий доступный шаг `/forge`: `T4.4.1` schedule concurrency/property suite._

_Актуализация 2026-07-29: `T4.4.1` закрыта: единый `test:schedule-v4` gate покрывает 2 000 seeded interval cases, 64 randomized weekly-series samples в четырёх IANA timezone, параллельные create/drag/reschedule и two-worker completion. Advisory locks/version guards оставляют ровно одного победителя, terminal/financial facts детерминированы; Flutter inventory подтверждает attendance routes/mutations/controls=0. Exact schedule 9/9 suites и 25/25 tests, full backend 129/129 suites и 1071/1071 tests, Flutter 411/411, analyze/typecheck/build clean (`docs/audits/v4-schedule-concurrency.md`). `INT-S2` ждёт `INT-S1`; следующий доступный шаг `/forge`: `T5.1.2` catalog/snapshot/ledger schema._

### 🌊 Wave v4/S3 — Subscription Integrity
_Актуализация 2026-07-29: `T5.1.2` закрыта: migration `0089` добавляет versioned catalog price в minor units, immutable issued commercial snapshot с percent/fixed discount shape, installments, append-only ActualPayment/obligation/lifecycle facts и typed repository. Процентная скидка проверяется от указанной базовой суммы (`8000 − 20% = 6400`), фиксированная скидка поддержана; teacher compensation остаётся только `fixed/hourly/none`. Payment/ledger/Lesson fact UPDATE/DELETE отклоняются PostgreSQL. Migration down→up PASS, exact schema 2/2, targeted regression 16/16, full backend 130/130 suites и 1073/1073 tests, typecheck/build clean, inventory 266 routes/591 DTO fields/0 unowned (`docs/audits/v4-commerce-schema.md`). Следующий шаг `/forge`: `T5.2.1` Subscription Package catalog._

_Актуализация 2026-07-29: `T5.2.1` закрыта: versioned Subscription Package catalog вынесен в отдельный service/repository; Admin/Manager получают только active read, Director/system_admin — atomic create/update/archive/restore с expected version, idempotency, before/after audit и minimal outbox. Teacher package-read стал hard-deny. Migration `0090` синхронизирует package/aggregate versions и сохраняет защищённую immutable catalog-version history, поэтому поздний retry возвращает исходный result, а destructive rollback fail-closed. Использованный package архивируется без разрыва FK; реальные issue до/после update сохраняют immutable snapshot старой/новой package version. Flutter получил role-safe management projection, editor с явной stale-version перезагрузкой, согласованные active/all cache, полную per-row mutation lock, reversible archive/restore и active-only selector. Exact backend 15/15, widget 7/7, Actor Matrix 1530/1530, full backend 131/131 suites и 1083/1083 tests, Flutter analyze clean и 420/420 tests, inventory 267 routes/600 DTO fields/0 unowned (`docs/audits/v4-package-catalog.md`). Следующий шаг `/forge`: `T5.2.2` issue/discount/installment/payment flow._

_Актуализация 2026-07-29: `T5.2.2` закрыта: выдача атомарно и idempotent создаёт immutable snapshot, точные obligations и рассрочку без ложной выручки; процентная скидка считается от указанной суммы (`8000 − 20% = 6400`), фиксированная скидка и обязательная причина поддержаны. ActualPayment записывается отдельной append-only cash/cashless командой, duplicate retry не создаёт второй факт. Flutter client-card получил адаптивную форму со стабильными mutation identities и отдельным partial payment. Exact backend 32/32 и Flutter 7/7 (`docs/audits/v4-subscription-issue-payment.md`). Следующий шаг `/forge`: `T5.2.3` preview/confirm замены._

_Актуализация 2026-07-29: `T5.2.3` закрыта: подписанный пяти-минутный preview связывает actor/student/version/package, used/future usage, payment total и детерминированный reservation plan. Confirm повторно блокирует и пересчитывает данные, затем одной Platform Integrity transaction закрывает old subscription, создаёт ровно один immutable snapshot, differential debt/overpayment, переносит допустимые резервы и освобождает overflow; payments не копируются и не меняются. Flutter client-card показывает used/future, предупреждения, перенос/освобождение и итоговый долг/переплату, сохраняя stable retry identity. Exact PostgreSQL 4/4, Flutter 2/2, TypeScript clean (`docs/audits/v4-subscription-replace.md`). Следующий шаг `/forge`: `T5.2.4` preview/confirm отмены._

_Актуализация 2026-07-29: `T5.2.4` закрыта: подписанный preview показывает immutable payments/write-offs/balance и будущие занятия/резервы. Confirm повторно блокирует и проверяет snapshot, затем одной versioned/idempotent transaction переводит issued subscription в `cancelled`, освобождает future reservations и создаёт только lifecycle/audit/minimal outbox; занятия и все finance facts остаются byte/amount-identical. Flutter client-card получил явный preview/confirm с reason code и stable retry. Exact PostgreSQL 3/3, Flutter 2/2, TypeScript clean (`docs/audits/v4-subscription-cancel.md`). Следующий шаг `/forge`: `T5.3.1` role-scoped subscription/finance surfaces._

_Актуализация 2026-07-29: `T5.3.1` закрыта: отдельные fact-based `/crm/me/commerce` и `/crm/students/:studentId/commerce` дают Client только own read-only, Admin/Manager только branch-scoped client-card, Director business-wide и system_admin emergency projection; Teacher блокируется до SQL и получает 0 finance keys/events/export. Global finance reads оставлены только Director/system_admin, cache partitions разделены по profile/actor/access/scope, realtime использует finance-only room и только active Client user audience с payload `{scope}`. Flutter self/card sections перешиты на scoped projections. Exact core 11/11, boundary 48/48, Flutter role contract 3/3; единственный review-проход закрыл 3/3 High. Один full batch выявил только 5 stale fixtures (backend 4, Flutter 1), все исправлены и targeted-зелёные; unresolved failures=0, backend typecheck/build и Flutter analyze clean (`docs/audits/v4-commerce-role-projections.md`). Следующий шаг `/forge`: `T5.3.2` reservation/lesson integration._

_Актуализация 2026-07-29: `T5.3.2` закрыта: Lesson create/series/reschedule теперь атомарно выделяют capacity-checked reservation; replace/cancel и completion сериализуются блокировками issued/reservation aggregate. Settlement использует реально перенесённое покрытие, не создаёт post-cancel subscription write-off, терминализирует reservation вместе с Lesson/facts и после commit инвалидирует schedule/client-finance projections менее чем за 2 s; future Lessons сохраняются. Exact PostgreSQL race 2/2, targeted commerce/schedule regression 19/19, typecheck clean (`docs/audits/v4-subscription-lesson-reservations.md`). Следующий шаг `/forge`: `T5.4.1` commerce actor/concurrency/reconciliation suite._

_Актуализация 2026-07-29: `T5.4.1` закрыта: единый `test:commerce-v4` gate покрывает catalog/schema/issue/payment/replace/cancel/reservation race/settlement/projections; Actor Matrix и payload scan подтверждают права и отсутствие утечек. Commerce-scoped signed reconciliation сравнивает 10 named payment/balance/snapshot/installment/obligation/lifecycle/Lesson/reservation invariants: clean 10=10, unexplained drift=0; negative fixture обнаруживает 1/1 injected drift. Commerce regression 8/8 suites и 35/35 tests, Actor Matrix/leak 2/2 suites и 9/9 tests, typecheck clean (`docs/audits/v4-commerce-concurrency-reconciliation.md`). `INT-S3` ждёт `INT-S2`; следующий доступный шаг `/forge`: `T6.1.1` SharedTask schema._

### 🌊 Wave v4/S4 — CRM & Shared Work
_Актуализация 2026-07-29: `T6.1.1` закрыта: migration `0092` создаёт единый SharedTask, selector audiences user/branch/allBranches, unique TaskClose, persisted reminders, append-only audience-resolution audit и lossless legacy links. Conservative backfill объединяет только exact payload+creator+timestamp copies с разными recipients; ambiguous rows остаются отдельными. Exact fixture: 2 exact→1, 2 ambiguous→2, links/audiences 4/4, append-only guard и migration down→up PASS, typecheck clean (`docs/audits/v4-shared-task-schema.md`). Следующий шаг `/forge`: `T6.2.1` SharedTask API._

_Актуализация 2026-07-29: `T6.2.1` закрыта: versioned/idempotent SharedTask API валидирует schedule/audience/EntityLink и вычисляет current user/branch/allBranches membership. Concurrent two-close даёт state/audit/close/outbox=1 и один stable result; потеря branch membership сразу убирает доступ. Exact PostgreSQL 2/2, typecheck clean (`docs/audits/v4-shared-task-api.md`). Следующий шаг `/forge`: `T6.2.2` non-blocking reminders/realtime close._

_Актуализация 2026-07-29: `T6.2.2` закрыта: persisted reminder worker использует SKIP LOCKED claim, lease/reclaim, dedupe, bounded retry/poison и current audience recipients; email/push имеют in-app fallback. Close атомарно отменяет pending reminders и после commit посылает body-free invalidation в CRM/user rooms менее чем за 2 s; list возвращает open/overdue counters. Exact reminder 1/1, targeted SharedTask 3/3, typecheck clean (`docs/audits/v4-task-reminders-realtime.md`). Следующий шаг `/forge`: `T6.3.1` desktop/mobile Task UX._

_Актуализация 2026-07-29: `T6.3.1` закрыта: Flutter экран общих задач подключён к текущему Task-разделу, использует v4 create/update/list/close, поддерживает audience user/branch/allBranches, all-day/interval, reminder badge/panel и явный close pending/error/retry. Mobile collapsed filter ровно 56 px, advanced filters scrollable; desktop filters inline. Exact widget 4/4, Flutter analyze clean, backend targeted 3/3 и typecheck clean (`docs/audits/v4-shared-tasks-ui.md`). Следующий шаг `/forge`: `T6.4.1` task audience/concurrency/device suite._

_Актуализация 2026-07-29: `T6.4.1` закрыта: единый `test:tasks-v4` gate покрывает conservative migration, user/users/branch/allBranches, matched-selector audit, permission loss before close, concurrent two-close, reminder outage/fallback и overlapping workers. Backend gate 3/3 suites и 5/5 tests; Flutter desktop/mobile 4/4, filter=56 px, duplicate close/audit/outbox=0, unauthorized close=0, reminder blocking=0. Один review-проход устранил N+1 projections и сохранил reminder при edit; полный batch regression: backend 140/140 suites и 1126/1126 tests, Flutter 434/434, typecheck/build/analyze clean (`docs/audits/v4-task-audience-regression.md`). Следующий доступный шаг `/forge`: `T3.3.1` Lead/Student/config forms; `T3.2.4` остаётся заблокирована до `INT-S3`._

### 🌊 Wave v4/S1 — Flutter Access Integration
_Актуализация 2026-07-30: `T1.1.1` закрыта: authenticated `/access/me` отдаёт effective capability snapshot с account/accessVersion/scopes; Flutter shell key-ит snapshot по account/version, вычисляет destinations из capabilities и после `access.invalidated` пересоздаёт boundary без старого чувствительного UI. Exact Flutter 3/3, backend route policy 34/34, typecheck clean (`docs/audits/v4-capability-shell.md`). Следующий шаг `/forge`: `T1.1.2` Director access editor/emergency root surface._

_Актуализация 2026-07-30: `T1.1.2` закрыта: access editor доступен только Director/system_admin, показывает package/effective/override, требует reason и reset confirmation, а stale `409` перечитывает server truth без partial UI. Director видит/назначает только lower roles и не получает `system_admin` account/filter/option; root использует отдельный emergency surface. Exact Flutter 4/4, PostgreSQL 6/6, typecheck clean (`docs/audits/v4-access-editor.md`). Следующий шаг `/forge`: `INT-S1` Access & Privacy gate._

_Актуализация 2026-07-30: `INT-S1` закрыт: новый S1 sprint gate проверил task/evidence inventory, access policy/mutations/invalidation 7/7 suites и 103/103 tests, Actor Matrix + teacher payload scan 2/2 suites и 9/9 tests, Flutter capability shell/editor/RBAC 25/25; Manager mutations denied, Director lower-only, system_admin hidden/emergency root, invalidation≤5 s. Финальный пакетный regression: backend 140/140 suites и 1128/1128 tests, Flutter 441/441, analyze/typecheck/build clean; authenticated-only `/access/me` не блокируется personal deny (`docs/audits/v4-s1-access-privacy.md`). Следующий шаг `/forge`: `INT-S2` Lesson Integrity._

_Актуализация 2026-07-30: `INT-S2` закрыт: S2 gate подтвердил task/evidence inventory, schedule lifecycle/concurrency 9/9 suites и 25/25 tests, Actor Matrix/payload leak 2/2 suites и 9/9 tests, Flutter lesson/conflict/palette/Teacher surfaces 16/16; attendance mutation routes/controls=0, two-worker completion создаёт один settlement/audit не позднее 60 s, typecheck clean (`docs/audits/v4-s2-lesson-integrity.md`). Следующий шаг `/forge`: `INT-S3` Subscription Integrity._

_Актуализация 2026-07-30: `INT-S3` закрыт: S3 gate подтвердил commerce actor/concurrency 8/8 suites и 35/35 tests, Actor Matrix/payload leak 2/2 suites и 9/9 tests, Flutter catalog/issue/replace/cancel/finance 17/17, clean reconciliation 10/10 invariants с drift=0 и negative fixture с ровно одним signed diff; typecheck clean (`docs/audits/v4-s3-subscription-integrity.md`). Следующий шаг `/forge`: `T3.2.4` role-aware Client Card read model._

_Актуализация 2026-07-30: `T3.2.4` закрыта: единый `GET /crm/clients/:type/:id/card` собирает header/indicators/stable sections за 3 bounded queries независимо от числа строк и сохраняет student compatibility route. Full/Teacher/Client projections применяют effective capabilities до SQL sections; Teacher получает только assigned lessons/homework и shared comments, запрещённые keys=0, чужой UUID=safe 404. Exact 3/3 suites и 10/10 tests, Actor Matrix/leak/card 3/3 suites и 13/13 tests, 268 private routes × 6 = 1608/1608, full backend 141/141 suites и 1133/1133 tests, Flutter 441/441, typecheck/build/analyze clean, inventory 280 routes/641 DTO fields/0 unowned (`docs/audits/v4-client-card-read-model.md`). Следующий шаг `/forge`: `T3.3.1` Lead/Student/config forms._

_Актуализация 2026-07-30: `T3.3.1` закрыта: manual Lead/Student write-boundary подключён к strict validators T3.1.2 и атомарному typed-value persistence; Flutter формы требуют ФИО/телефон/source либо branch/status, показывают field-level 422 без потери ввода и обновляют inactive source. Director/system_admin configuration UI поддерживает versioned source/custom-field CRUD/archive, без capability control отсутствует, 403 остаётся внутри экрана. Exact Flutter 4/4, backend 3/3 suites и 9/9 tests, typecheck/analyze clean (`docs/audits/v4-client-forms.md`). Следующий шаг `/forge`: `T3.3.2` Client Card/archive/comment UX._

_Актуализация 2026-07-30: `T3.3.2` закрыта: Teacher открывает отдельную actor-scoped read-only карточку только с занятиями/ДЗ/shared comments; staff сохраняет полную карточку, archive preview/confirm доступен только Director/system_admin, comment share использует явный versioned toggle. Exact Flutter 4/4, затронутый CRM regression 18/18, analyze clean (`docs/audits/v4-client-card-ux.md`). `INT-S4` закрыт: CRM lifecycle/privacy 6/6 suites и 21/21 tests, SharedTask 3/3 suites и 5/5 tests, Actor Matrix/leak 2/2 suites и 9/9 tests, Flutter mobile/desktop 12/12; manual notifications=0, duplicate inbound Lead/notification=1/1, concurrent close result=1, mobile filter=56 px (`docs/audits/v4-s4-crm-tasks.md`). Следующий шаг `/forge`: `T7.1.1` status summary и общий filter spec._

_Пакетный regression 2026-07-30: backend 141/141 suites и 1135/1135 tests, Flutter 449/449, typecheck/build/analyze clean. Единственная найденная регрессия была в старом realtime test fixture без нового capability source; fixture исправлен и точечно прошёл 4/4._

### 🌊 Wave v4/S5 — Connected Workspace
_Актуализация 2026-07-30: `T7.1.1` закрыта: versioned Client Status filter применяется одним actor-scoped SQL predicate к summary и drilldown; Manager видит только назначенные филиалы, Director/system_admin — business scope, Admin и Manager с Director-disabled `report.status.read` получают 403. Ответы содержат typed EntityLink/filter и safe ClientRef rows. Exact PostgreSQL 1/1 suite и 2/2 tests, typecheck clean (`docs/audits/v4-client-status-reporting.md`). Следующий шаг `/forge`: `T7.1.2` lesson/finance read models и hard scope._

_Актуализация 2026-07-30: `T7.1.2` закрыта: Lesson Success считает только `lifecycle_state=successfully_completed`, Manager получает branch-scoped metric, Director/system_admin — business scope. School Finance использует append-only `payments.amount_minor` как ActualPayment и не читает expected installments; Admin/Manager получают 403, finance-row links существуют только в root-business projection. Exact PostgreSQL 1/1 suite и 2/2 tests, typecheck clean (`docs/audits/v4-reporting-hard-scope.md`). Следующий шаг `/forge`: `T7.2.1` валидный OOXML export._

_Актуализация 2026-07-30: `T7.2.1` закрыта: ExcelJS создаёт настоящий `.xlsx` с Unicode/date/money/formula types и обязательным structural validation. До 10 000 строк export синхронный, 10 001–100 000 — private async job с owner-only download и TTL, свыше 100 000 отклоняется; CSV/XLSX и legacy finance façade имеют корректные extension/MIME. Exact PostgreSQL/OOXML 1/1 suite и 3/3 tests, streaming fixture 10 001 строк, validator PASS, migration `0093` down→up PASS, inventory 287 routes/658 DTO fields/0 unowned, access coverage 275/275 (`docs/audits/v4-ooxml-export.md`). `T7.2.2` ждёт `T1.2.1`; следующий доступный шаг `/forge`: `T1.2.1` desktop workspace shell._

_Пакетный regression 2026-07-30: backend 144/144 suites и 1140/1140 tests, Flutter 449/449, typecheck/build/analyze clean. Единственный блокер — legacy SharedTask migration fixture откатывал последнюю миграцию вместо целевой `0092`; fixture сделан version-aware и точечно прошёл 1/1._

_Актуализация 2026-07-30: `T1.2.1` закрыта: versioned EntityLink v1 типизирует Client/Lesson/Task/Subscription/Payment/User/Homework/Chat/Report и server report variants, registry строит один canonical target через capability/projection policy. Teacher Client route limited; forbidden/deleted/archived/unknown завершаются safe state без infinite load. Exact Flutter 4/4, targeted analyze clean (`docs/audits/v4-entity-link-registry.md`). `T7.2.2` разблокирована; следующий шаг `/forge`: reports/drilldown/export UI._

_Актуализация 2026-07-30: `T7.2.2` закрыта: role-safe Reports surface показывает Manager status/lesson metrics без school finance, Director/system_admin — finance rows; loading/empty/error/forbidden явные. EntityLink filter без потерь открывает drilldown и восстанавливает source, client row ведёт в actor-safe target. Sync/async export показывает progress/error, owner-only job скачивается и открывается platform handler. Exact widget 4/4, reports/finance regression 4/4, targeted analyze clean (`docs/audits/v4-reporting-ui.md`). Следующий шаг `/forge`: `T1.2.2` mobile context stack/restoration._

_Актуализация 2026-07-30: `T1.2.2` закрыта: restorable ContextRouteState хранит только EntityLink и filters/date/scroll/column; 4-level mobile drilldown последовательно восстанавливает каждый source screen и не рендерит desktop tabs. Pending authenticated deep link после входа строит `home → target` с корректным Back. Exact Flutter 4/4, targeted analyze clean (`docs/audits/v4-mobile-context-navigation.md`). Следующий шаг `/forge`: `T1.2.3` desktop WorkspaceController._

_Пакетный regression 2026-07-30: `T1.2.1`, `T7.2.2`, `T1.2.2` закрыты атомарно; backend 144/144 suites и 1140/1140 tests, Flutter 461/461, typecheck/build/analyze clean. Inventory 287 routes/658 DTO fields/0 unowned, access coverage 275/275. Один review-проход закрыл finance-row production detail target; unresolved blockers=0._

_Актуализация 2026-07-30: `T1.2.3`–`T1.2.6` закрыты: desktop WorkspaceController держит 1–10 tab-local route/form scopes при общей session/cache/realtime; account/schema restore не сохраняет DTO/token/dirty values и global logout очищает все окна ≤2 s. Versioned projection cache дедуплицирует invalidation, clean tabs refetch-ятся параллельно, dirty input получает Reload/Merge/Cancel conflict без silent overwrite. Hover `⋯`, linked open-new, D&D order persistence и Save/Discard/Cancel close guard покрыты. Exact workspace 16/16; один review-проход закрыл late-open после logout, конкурентное close/reorder и безопасный Cancel close-others. Полный regression: backend 144/144 suites и 1140/1140 tests, Flutter 477/477, typecheck/build/analyze clean; inventory 287 routes/658 DTO fields/0 unowned, access coverage 275/275. Следующий шаг `/forge`: `T1.3.1` полная матрица связанных переходов._

_Актуализация 2026-08-01: `T1.3.1` закрыта: PRD §8 сведён в единый реестр из 53 typed EntityLink-переходов для 13 source-контекстов; 6 ролей получают canonical target либо safe forbidden, unknown=0, filters/date/scroll/column сохраняются. `T1.4.1` закрыта на реальных Flutter device runners: workspace/widget regression 24/24, Windows 2/2 и Android 15/API35 2/2; context loss/silent overwrite/cross-account leak=0, logout gate ≤2 s. Для Windows Build Tools 2026 локально установлен ATL, а pinned plugins получили только compile-time legacy `/await` acknowledgement без обновления зависимостей (`docs/audits/v4-workspace-device.md`). `INT-S5` закрыт: reporting/OOXML 7/7, six-role privacy 9/9, Flutter reporting/EntityLink 12/12, device gate 24/24 + Windows 2/2 + Android 2/2, реальный Excel открыл fixture без repair; transition coverage=100%, leaks/warnings/overwrite=0. Пакетный regression: backend 144/144 suites и 1140/1140 tests, Flutter 481/481, typecheck/build/analyze clean, inventory 287 routes/658 DTO fields/0 unowned (`docs/audits/v4-s5-connected-workspace.md`). Следующий шаг `/forge`: `T8.3.1` production preflight v4._

_Актуализация 2026-08-01: `T8.3.1` закрыта на PostgreSQL 17 production-schema staging copy: backup SHA-256 зафиксирован, dry-run нашёл 1 однозначную access-link строку, первый apply изменил 1 строку, второй — 0; review queue=0, read-only preflight 16/16 и blockers=0. Exact PostgreSQL integration 1/1, typecheck clean (`docs/audits/v4-production-backfill.md`). Следующий шаг `/forge`: `T8.3.2` v4 data migration dry-run._

_Актуализация 2026-08-01: `T8.3.2` закрыта на отдельной backup-restored PostgreSQL staging copy: 7/7 обязательных migrations, 8/8 named invariants, source/target 21/21, violations/pending batches=0 и повторный read-only digest стабилен. Rollback `0093→0092` + forward `0092→0093` сохранил counts; reconciliation 14 invariants, facts 1/1, drift=0, signature verified; exact PostgreSQL 1/1 (`docs/audits/v4-migration-dry-run.md`). Следующий шаг `/forge`: `T8.3.3` compatibility/shadow parity gates._

_Актуализация 2026-08-01: `T8.3.3` закрыта: shadow corpus проверил 1 650 access решений и 2 000 seeded half-open schedule cases; единственный diff классифицирован как legacy-stricter/intersection-safe, unexplained=0. Access/schedule defaults остаются shadow, v4 enable блокируется при unknown diff, domain kill switches документированы и публикуются runtime readiness. Exact 3 suites и 9/9 tests. Пакетный regression `T8.3.1–T8.3.3`: backend 148/148 suites и 1 147/1 147 tests, Flutter 481/481, typecheck/build/analyze clean, inventory 287 routes/658 DTO fields/5 schema tables/0 unowned. System Node.js/npm восстановлен; security audit показывает inherited `exceljs→uuid` moderate без dependency change — явный вход T8.4.1 (`docs/audits/v4-shadow-parity.md`). Следующий шаг `/forge`: `T8.4.1` full technical/UAT gates._

_Актуализация 2026-08-01: `T8.4.1` и `T8.4.2` технически закрыты с явным owner exception для security gate. Release evidence имеет `pass_with_owner_exception`, `productionApproved=false`, known High=1 и backlog #16/#17; security checks не объявлены зелёными. Backend 148/148 suites и 1148/1148 tests, Flutter analyze clean и 482/482 tests, migration/preflight/reconciliation/shadow drift=0, Windows 3/3 и Android retry 3/3, backup/restore, worker/outbox и alert drill PASS. Staging rehearsal подтвердил shadow→v4, unexplained-diff block, kill-switch rollback, forward recovery, health/auth/realtime/outbox 6/6 suites и 54/54 tests, immutable facts preserved (`.anws/v4/08_RELEASE_READINESS_REPORT.md`, `docs/audits/v4-rollout-rehearsal.json`). `INT-S6` остаётся открытым: production запрещён до Critical/High=0 и восстановления GitHub admin/private repository доступа._

_Актуализация 2026-08-03: owner-refinement для `T4.2.3`/`T5.1.1`/`T8.3.1` реализован migration `0094`: индивидуальные серии материализуются rolling-окном 60 дней, существующие групповые Lesson получают immutable participant snapshots и отдельный client fact на участника при одном teacher fact, replacement reservation сохраняет фактическое покрытие. Backfill формирует явную `manualMappingTable`; неподтверждённые строки остаются release blockers. Targeted 62/62 + blocking-regression 9/9, backend 150/150 suites и 1160/1160 tests, Flutter analyze clean и 482/482 tests, typecheck/build clean. Fresh production backup `859dbf4a…` восстановлен в изолированную PostgreSQL-копию: migration `0094` PASS, read-only proof `25006`/stable, 16 checks дают 1329 blockers и 81 phone warnings. Из blockers 1318 — отсутствующая personal-account price для 144 Students и 1 Group, остальные 11 — access/branch/subscription mappings. HolliHop price list даёт доказуемую индивидуальную разовую цену 4000 ₽, но она и цена Group не применяются без owner-confirmation. Следующий шаг: подтвердить эти две ценовые mapping-группы, затем повторить apply/replay/preflight до blockers=0._

_Актуализация 2026-08-03: owner hotfix wave `T1.5.1`/`T4.3.4`/`T7.2.3`/`INT-HF1` закрыта: серверный поиск сохраняет текущий экран и применяет debounce/latest-wins; расписание имеет только `Месяц / Неделя / День`, а переход из карточки открывает месяц с серверным Lead/Student-фильтром; report drilldown использует существующий `/analytics/v4/client-status/clients`. Targeted Flutter 10/10 и ScheduleService 53/53; полный regression backend 150/150 suites и 1160/1160 tests, Flutter 485/485, analyze/typecheck/build clean; Windows release build запущен и отвечает._

_Актуализация 2026-08-03: regression-fix `T4.3.4`: отдельный display-only Week calendar удалён; режим `Неделя` переиспользует рабочий `ScheduleDayCanvas` и те же create/details/move/resize server paths, поддерживает перенос между днями с сохранением комнаты и exact Mon–Sun query. Targeted schedule/client-navigation 12/12, Flutter analyze clean и полный Flutter regression 486/486._

_Актуализация 2026-07-30: `T3.3.2` закрыта: production launcher маршрутизирует Teacher в отдельную actor-scoped read-only карточку с горизонтальными tabs Lesson/Homework/shared Comments; запрещённые contacts/finance/tasks не строятся даже из лишнего payload. Staff-карточка получила Director/system_admin-only archive preview с impact/links/versioned confirm и tombstone contract. Comment share использует независимый `sharedWithTeacher` + expectedVersion, не меняя kind. Exact role UX 4/4, затронутые legacy card/finance 18/18, Flutter analyze clean (`docs/audits/v4-client-card-ux.md`). Следующий шаг `/forge`: `INT-S4` CRM & Shared Work._

### 🌊 Wave v3/S0 — Architecture and Linear Backlog
_Текущая фаза: `.anws/v3` создана для перехода с Supabase Cloud на собственный NestJS/PostgreSQL backend. Следующий шаг: завести Linear project `MagicMusicCRM v3 Backend Independence`, подтвердить INT-S0 и перейти к инфраструктурной волне._

### 🌊 Wave v3/S2-S3 — Backend Core and Auth Boundary
_Локальный NestJS backend scaffold создан. `S2` и `S3` закрыты после local gates и staging smoke: request-id/log redaction, health, audit, RBAC, password signup/login, refresh rotation/reuse detection, logout-all, OTP/password reset и optional Google OAuth fail-closed проверены. Следующая волна: `S4` Feature APIs._

### 🌊 Wave v3/S1 — Staging Infrastructure Rehearsal
_Selectel staging server `161.104.50.105` поднят для `api.phantom-net.ru`: Docker Compose, Caddy TLS, PostgreSQL, Redis и NestJS API работают. `S1` закрыт: firewall/listeners, encrypted backup/off-server copy, destructive restore drill, monitoring timer, forced alert drill и rollback restart smoke проверены._

### 🌊 Wave v3/S4 — Feature APIs
_`S4` закрыта: Profile/CRM, Messenger REST/WebSocket, private File API, Legal/Account Deletion API, Notifications provider fallback and full Feature API smoke completed on `api.phantom-net.ru`. Migrations `0002`-`0006`, role-scoped policies, audit evidence and log secret checks passed. Следующий шаг: `S5` migration pipeline from Supabase export._

### 🌊 Wave v3/S5 — Migration Pipeline
_`S5` закрыта. `T5.1` подтверждена реальным Supabase export через session pooler `aws-1-eu-central-2.pooler.supabase.com:6543`: `69` tables, `23,188` rows, `36` storage objects, `0` warnings. `T5.2` закрыта после dry-run на Selectel staging v3 PostgreSQL: `22,709` source rows, `25,002` planned rows, `1,105/1,105` messages, rollback confirmed. `T5.3` закрыта: storage/file_objects dry-run скачал `36/36` объектов, signed download API smoke прошёл. `INT-S5` закрыт после второго full dry-run and `.anws/v3/08_CUTOVER_READINESS_REPORT.md`. Следующий шаг: `S6` Flutter cutover._

### 🌊 Wave v3/S6 — Flutter Cutover
_Последнее обновление 2026-06-17: `INT-S6` закрыт по user acceptance staged Android/Windows v3 smoke evidence. S6 считается завершенным этапом: Flutter runtime переведен на owned v3 REST/WebSocket/File API, Android baseline smoke на real device `I2405` ранее прошел login/onboarding/legal/dashboard/chat send, Windows debug build/runtime smoke and no-secret integration smoke passed. Stable-device Android private file/deletion checklist перенесен в S7 launch hardening follow-up и больше не блокирует S6._
_Последнее обновление 2026-06-15: `INT-S6` частично проверен against `api.phantom-net.ru/api`. `flutter doctor -v` clean, Android licenses accepted, Android/Windows debug builds passed, Windows runtime smoke kept the fresh `magic_music_crm.exe` alive for 20 seconds. Real Android device `I2405` on Android 15 previously passed login, onboarding, legal consent, dashboard chat list, Administration chat open and message send; message `AndroidSmokeMessage` was confirmed through v3 API as `f73a5583-14f5-42b5-901e-a9c472e3dd8e`, and logcat had no Flutter/Dart/Fatal app errors. Added no-secret `integration_test/app_launch_smoke_test.dart` plus `docs/runbooks/flutter-integration-smoke.md`; Windows runner smoke starts with in-memory token store/no-op notifications, reaches the Russian login gate, validates empty login errors, checks the fake authenticated account-deletion form and reaches `Запрос принят`. Added `docs/runbooks/android-real-device-smoke.md` and `scripts/android_real_device_smoke.ps1` for the remaining stable-device private file, real-backend deletion, CRM workflow, log evidence and cleanup checklist; helper `-CheckOnly` passes. Milestone остается открытым: run integration smoke/helper on a stable Android target, then real-device Android private file upload/download and account deletion against the real backend._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` закрыт. Добавлен `npm run smoke:realtime` harness, который через публичный `api.phantom-net.ru/api` проверяет health, signup/login, administration chat, Socket.IO `/realtime`, `room.join`, REST send and `message.created` event match. Staging smoke passed: user `b51deb51-60c2-4013-8ef9-5dd18488d755`, chat `3dfdd20a-00cc-4156-a7d3-95d88ff79071`, message/event `8c3324d2-b8f6-4f07-97ca-fd370d2aa698`; temp users soft-deleted. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `120` tests), `npm run build`, log secret grep clean except benign route names. Следующий шаг: `INT-S6` Android/Windows smoke._
_Последнее обновление 2026-06-12: `T6.5/KVA-108` закрыт. `ChatAttachmentService` переведен с Supabase Storage SDK на v3 `/files` multipart upload and one-time download tokens; migrated messenger/profile flows теперь используют `attachment_file_id` / `avatarFileId`; backend profile update validates own `profile_avatar`, and FilesPolicy allows chat members to read chat-bound files. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `120` tests), `npm run build`; Flutter `flutter test` (`52` tests), targeted analyze clean, full `dart analyze` только с `9` archive info-lints; staging deploy on `api.phantom-net.ru/api` passed after backup `magicmusiccrm-staging-20260612T172231Z.tgz.enc`, file smoke passed with byte match and one-time token reuse `404`. Следующий шаг: close remaining `T6.4` realtime smoke gap, then `INT-S6` Android/Windows smoke._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` продвинут legacy screen slice. `messenger_screen.dart` переведен с Supabase Auth/DB/realtime and `SupaMessageService`/`SupaMessengerService` на v3 auth/profile, `MagicMessengerService` and `MagicRealtimeService`; `CreateGroupChatDialog` переведен на `/admin/profiles` + `/messenger/groups`; full Flutter tests pass (`47`). Следующий срез: `chat_info_dialog.dart` v3 contract, затем `T6.5` private file/voice attachments._
_Последнее обновление 2026-06-12: `T6.4/KVA-108` продвинут shared provider slice. `chat_providers.dart` переведен с Supabase Auth/DB/realtime на v3 `MagicAuthService` + `MagicProfileAdminService` + `MagicMessengerService`; `MagicMessengerService` расширен group/channel/post контрактами; targeted analyze/tests and full Flutter tests passed. Следующий срез: migrate legacy `messenger_screen.dart` / `chat_info_dialog.dart` onto v3 realtime/API state._
_T6.4 стартовал: добавлен `MagicRealtimeService` over Socket.IO `/realtime`, `socket_io_client 3.1.5`, unit tests for auth/path/join/typing/presence/event mapping, and `TeacherChatWidget` now consumes v3 `message.created/message.updated` realtime events after REST direct-chat bootstrap. Следующий срез: migrate legacy `messenger_screen.dart` and `admin_chat_dashboard.dart` from Supabase realtime/DB to `MagicMessengerService` + `MagicRealtimeService`._
_Последнее обновление 2026-06-12: `T6.3/KVA-108` закрыт после teacher chat slice. `MagicMessengerService` добавлен, `TeacherChatWidget` переведен на v3 `/crm` + `/messenger`, local Flutter tests and staging direct-chat smoke passed. Следующий шаг: `T6.4` messenger realtime flows, затем `T6.5` file/storage flows._
_`T6.1` и `T6.2` закрыты. `T6.3` в работе (`KVA-108`): добавлен `MagicCrmService`, client lessons/homework/subscription/progress переведены на `/crm`, profile load/save переведён на `/profile/me`; backend CRM contract расширен для `/crm/branches`, `/crm/rooms` read/write, `/crm/groups`, `/crm/students/:id/groups`, `/crm/lead-statuses` read/write, `/crm/subscriptions`, `/crm/comments` read/write, `/crm/expected-payments`, `/crm/lessons/:id/attendance`, `/crm/overview`, `/crm/leads` read/write/delete, `/crm/payments`, `/crm/tasks`, `/crm/student-balances`, `/crm/reports/finance`, `/settings/admin-chat-avatar`, `/admin/settings/admin-chat-avatar`, lesson `branchId/roomId/isTrial/leadId`; `PATCH /crm/students/:id` added for manager/admin student profile/custom-data updates with audit; `app.expenses`, `app.system_settings`, migrations `0009_lesson_attendance` and `0010_lead_management` добавлены для migration-compatible reports/settings/attendance/leads; `CreateLessonDialog`, `ScheduleWidget`, `TeacherScheduleWidget`, `TeacherStudentsWidget`, `AdminOverviewWidget`, `ManagerOverviewWidget`, `ConversionTrackingWidget`, `UserRolesWidget`, `LessonsKanbanWidget`, `LessonAttendanceDialog`, `LeadsWidget`, `LeadDetailDialog`, `ManageStatusesDialog`, `FinanceWidget`, `TopUpDialog`, `TasksWidget`, `DebtorsWidget`, `ReportsWidget`, `FinancialDashboardWidget`, `CreateRoomDialog`, `SupaSettingsService`, `ManageEntitiesWidget`, `StudentDetailDialog` и `StudentDetailScreen` переведены с прямого Supabase на v3 API. Backend разрешает assigned teacher обновлять только `status/notes` своего lesson and attendance on own lessons; attendance contract persists `present/absent` plus `passReason`; lead contract supports status create/delete, lead create/list/update/soft-delete, lead comments/tasks and lead-only trial lessons; finance contract поддерживает `from/to/studentId/limit` и student summary; task contract поддерживает `status/studentId` filters and display names; student balance contract computes paid/cost/balance server-side; report contract computes monthly revenue/expenses/attendance, teacher revenue and room load server-side; room write contract supports manager/admin create/update/soft-delete with audit; settings contract supports authenticated admin-avatar read and admin-only validated write; entity management reads students/teachers/lessons/groups/rooms/staff via v3 services and updates lesson cancel/reschedule via `/crm/lessons/:id`; student detail dialog loads/saves student and comments through v3 one-shot APIs; full student detail screen now loads student, payments, lessons, tasks, active groups, balance, comments and expected payments through v3 APIs and saves comments, tasks, individual price and contract URL through backend writes. Проверки: backend `npm run typecheck`, `npm test` (`28` suites, `119` tests), `npm run build`; Flutter `flutter test` (`34` tests), targeted `dart analyze` clean; full `flutter analyze` has pre-existing info-level lints outside this slice. Staging deploy/smoke on `api.phantom-net.ru/api` passed after encrypted backups: health, reference endpoints, subscriptions, seeded progress comments, authenticated `/crm/overview`, unauth `401`, `/crm/leads`, `/crm/lessons?isTrial=true`, `/admin/profiles`, admin role update, `/crm/payments` list/create/filter, client payment write `403`, `/crm/tasks` create/list/filter/status update, client task write `403`, `/crm/student-balances?debtOnly=true`, client balance list `403`, migration `0007_expenses_reports`, `/crm/reports/finance` admin `200` with monthly/teacher/room aggregates, unauth report `401`, client report `403`, cleanup `1/1/1/1/1/1/2/2`, `/crm/rooms` create/list/update/delete smoke with unauth `401`, client write `403`, room cleanup, migration `0008_system_settings`, settings smoke with unauth `401`, manager write `403`, invalid URL `400`, setting cleanup/restore, `PATCH /crm/students/:id` + `POST/GET /crm/comments` smoke with audit events `crm.student_updated`/`crm.comment_created`, `/crm/students/:id/groups` + `/crm/expected-payments` smoke returned `1/1`, migration `0009_lesson_attendance` applied (`1/1`), `/crm/lessons/:id/attendance` read/save smoke returned `2/2`, migration `0010_lead_management` applied (`1/1/1/1`), lead status/lead/comment/task/lead trial smoke passed, temporary smoke cleanup `users=0/leads=0/lessons=0`, and strict API log secret grep found only benign route/module names. Следующий шаг: teacher chat, T6.4 messenger и T6.5 files._

### 🌊 Wave v3/S7 — Security and Launch
_Последнее обновление 2026-06-17: `S7` закрыт under clarified launch scope. HolliHop был только one-time bulk extraction source и не является runtime dependency/launch blocker; credential rotation сейчас не планируется; public API endpoint остается `api.phantom-net.ru`, смена адреса не планируется. `T7.3/KVA-114`, `T7.4/KVA-115` и `INT-S7/KVA-116` закрыты: `npm run security:gate` после корректировки gate проходит `7 pass / 4 warn / 0 fail`, backend `npm run typecheck` passes, HTTPS health на `api.phantom-net.ru` passes, realtime/auth smoke passed with message/event `3747cdde-1f90-4299-90a1-b35716cafdf9`, private file smoke passed with byte match and one-time token reuse `404`, email-provider smoke sent notification `8fcf4bd9-0376-447d-8a8b-3a5be368beab` via `resend/sent`, API restart rollback smoke recovered on attempt `2`. Следующий этап: `S8` desktop UX/UI stabilization._
_`S7` pre-release gate completed 2026-06-12 and evidence is in `.anws/v3/09_S7_RELEASE_EVIDENCE.md`. Codex Security repository pass generated `C:\tmp\codex-security-scans\MagicMusicCRM\c683807_20260612T204722\report.md` and `report.html`; official validator passed. Fixed in working tree: `server/exports`/`server/storage` excluded from Git and Docker context, chat attachment IDOR closed via `assertCanReadChat`, login and OTP verify lockouts added with migration `0011`, SSH bootstrap now disables root/password login by default, and test PostgreSQL bind is localhost-only. Current gates passed: backend `npm run typecheck`, `npm test` (`28` suites, `123` tests), `npm run build`, `npm audit --audit-level=moderate`; Flutter `flutter analyze` (`No issues found`) and `flutter test` (`52` tests); staging health and `npm run smoke:realtime`; `npm run security:gate` returned `7` pass, `4` warning, `0` fail. Google Play AAB `v1.1.6+116` built at `build/app/outputs/bundle/release/app-release.aab`, SHA-256 `D6E0BE113070FC62F41171F403351702A39ABE1C5291A0882247D04106C5DF5D`. Последнее обновление 2026-06-15: guarded HolliHop archive DB-backed dry-run passed as one-time migration evidence after backup `magicmusiccrm-staging-20260615T131610Z.tgz.enc`; report `hollihop-import-2026-06-15T13-40-42-091Z.json`, batch `3c4fc480-74a7-4801-a0e2-45c26972004a`, warnings `tasks_source_missing`/`timeline_sources_missing`, secret grep clean._

### 🌊 Wave v3/S8 — Desktop UX/UI Stabilization
_Последнее обновление 2026-06-18: `S8` remediation выполнена (`T8.1`–`T8.4` закрыты в Linear: `KVA-119`–`KVA-122`): schedule loading/empty/error+retry с видимым header, trustworthy task FAB с pending/error feedback, lead columns modal loading/empty/error states + board scroll affordance, lead status-menu current-state marker, role/activity/finance clarity. Проверки: `flutter analyze` clean, `flutter test` 94/94 (вкл. `test/features/s8_desktop_ux_states_test.dart`). Осталась 1 задача — `INT-S8` (`KVA-123`, In Review): нативная Windows-сборка и живой Computer-Use desktop re-audit заблокированы окружением без сети (CMake `firebase_core` SDK download) и должны быть выполнены в сетевом окружении перед закрытием gate и публичным релизом. `KVA-117`/`KVA-118` оставлены In Review до прохождения acceptance. Acceptance write-up: `docs/audits/windows-ux-ui-2026-06-18/report.md`._ Linear `KVA-117`/`KVA-118` и дочерние `KVA-119`–`KVA-123` закрыты. Следующий этап: дальнейший P2 polish (design tokens, overview hierarchy)._
_Последнее обновление 2026-06-16: локальный manager-role Windows audit `docs/audits/windows-ux-ui-2026-06-16/report.md` выявил новые product-quality blockers после v3 cutover. Критические trust failures: Schedule может зависать в безымянной blank/skeleton state, Task FAB не открывает create flow и не показывает pending/error feedback, lead columns modal рендерится пустым серым телом. Дополнительно зафиксированы `P1/P2` проблемы в lead board affordance, role/status mutation clarity, manager-facing reports activity copy, finance form guidance и design-token consistency. В `.anws/v3/05_TASKS.md` создан remediation backlog `T8.1`-`T8.4` + `INT-S8`; те же follow-ups привязаны к текущему stabilization parent `KVA-117` в Linear. Следующий шаг: выполнить `T8.1` и `T8.2`, затем повторить Windows audit до закрытия `INT-S8`._

### 🌊 Wave v3/S9 — Four-role Android Demo Workflow
_Последнее обновление 2026-07-19: `T9.6` закрыт. Исправлены повторный вход после logout, гонка состояния при password login, подсказка номера телефона, keyboard-safe отправка файлов/изображений и системное имя чата «Администрация». На production OTP bypass ограничен ровно `magic1@gmail.com`–`magic5@gmail.com`; migration `0074_image_message_type` применена. Реальный smoke подтвердил создание direct-чата, загрузку JPEG, доставку `image`, видимость и авторизованное скачивание получателем. Релиз `1.2.2+148` (Setup/Windows ZIP/APK/AAB) лежит в корневой `dist` и опубликован; оба update-манифеста указывают на build `148`, все публичные URL отвечают HTTP 200. Flutter analyze clean и `400/400` тестов; backend typecheck/build, `100/100` suites и `918/918` тестов зелёные._
_Последнее обновление 2026-07-19: `T9.5` закрыт. Перед выдачей первого абонемента клиент сохраняет незаписанные правки лида, поэтому конверсия копирует актуальную карточку. Production обновлён до migration `0073` (`73/73`, health green); поля `workplace`, `position`, `individualPrice` убраны из CRM-схемы без удаления исторических данных. Релиз `1.2.2+147` (Setup/Windows ZIP/APK/AAB) опубликован, оба update-манифеста указывают на build `147`; Flutter `394/394`, backend `98/98` suites (`913/913`)._
_Последнее обновление 2026-07-18: `S9` завершён и готов к записи. Backend с migration `0072_demo_workflow_invariants` развернут на production и health green: лид сохраняется через пробное/ДЗ и атомарно конвертируется только при выдаче абонемента; обычное посещение списывает стоимость один раз, пробное не списывает; реальный PUSH подтверждён. Проверки: backend `96/96` suites, `907/907` tests, typecheck/build; Flutter analyze clean, `392/392` tests; demo runner `14/14` tests и полный dry-run сценария green. Подписанные APK/AAB `1.2.2+145` собраны, старая версия удалена и новая установлена на точные AVD `Client`, `Teacher`, `Admin`, `Manager`; вход четырёх аккаунтов в соответствующие роли подтверждён. Production fixture `magic1@gmail.com` очищена после проверенного backup. Сценарий содержит `43` автоматических шага с пятисекундными показами и единственный ручной guarded reset; мутационный запуск сохранён для OBS-дубля, чтобы запись начиналась с чистого состояния._

### Технологические решения
- Dart/Flutter/Riverpod/GoRouter client и NestJS/TypeScript/PostgreSQL backend сохраняются без новых зависимостей.
- Денежные и lesson-команды используют одну PostgreSQL-транзакцию, expected version, idempotency и append-only facts.
- Quality Gates: targeted + full backend/Flutter, PostgreSQL concurrency/fault tests, Actor Matrix, migration down→up, reconciliation twice, Windows/Android smoke и owner UAT.

### Границы систем
- **SYS-APP-EXPERIENCE**: shell, routes, tabs, Back/deep-link и adaptive surfaces.
- **SYS-UI-FOUNDATION**: v7 components, accessibility, input и responsive layout.
- **SYS-ACCESS-SCOPE**: capabilities и actor/resource scope.
- **SYS-CRM-WORKSPACE**: Lead/Student, Client Card и общая staff-note.
- **SYS-SCHEDULE**: lessons, recurring plans, conflicts и temporal lifecycle.
- **SYS-COMMERCE-INTEGRITY**: wallet, subscriptions, installments, reversals, settlement и teacher accrual.
- **SYS-OPERATIONS**: tasks, dashboards, technical history и bounded drilldowns.
- **SYS-PLATFORM-QUALITY**: transactions, audit/outbox, reconciliation, migrations и release gates.

### Активные ADR
- ADR-001..006: наследованные v6 runtime/UX/navigation/access/release решения.
- ADR-007: существующий Flutter/NestJS/PostgreSQL runtime без нового сервиса/event-store.
- ADR-008: append-only клиентские финансы и reporting exclusion pair.
- ADR-009: единый атомарный lesson transition через Commerce port.
- ADR-010: client-finance capabilities Admin/Manager/Director и видимые причины.

---

## 🌳 Структура проекта (Project Tree)

> **Примечание**: Поддерживается процессом `/genesis`.

```text
MagicMusicCRM/
├── lib/                      # Flutter: app/UI/CRM/Schedule/Operations
├── server/
│   ├── src/access-control/   # RBAC/resource scope
│   ├── src/crm/commerce/     # money/hours integrity
│   ├── src/crm/schedule/     # temporal lesson integrity
│   └── db/migrations/        # PostgreSQL evolution
├── test/                     # Flutter regression
├── integration_test/         # device acceptance
└── .anws/v7/                 # active architecture
```

---

## 🧭 Навигация (Navigation Guide)

> **Примечание**: Поддерживается процессом `/genesis`.

- **Обзор архитектуры**: `.anws/v7/02_ARCHITECTURE_OVERVIEW.md`
- **ADR**: `.anws/v7/03_ADR/` — источник истины кросс-системных решений.
- **Детальный дизайн**: `.anws/v7/04_SYSTEM_DESIGN/`.
- **Список задач**: `.anws/v7/05_TASKS.md` — активный `/forge` backlog.
- **PRD**: `.anws/v7/01_PRD.md`.
- **Concept model**: `.anws/v7/concept_model.json`.

<!-- AUTO:END -->

---

## 🛡️ Операционные Правила (Magic Music Rules)

> [!IMPORTANT]
> **Принципы разработки в этом проекте (v1):**
>
> 1. **Префиксная Сервисная Модель**: Все новые сервисы, работающие напрямую с Supabase, ДОЛЖНЫ иметь префикс `Supa` (например: `SupaStudentService.dart`, `SupaLessonService.dart`).
> 2. **Декомпозиция Виджетов**: Запрещено писать SQL-подобные запросы (`Supabase.instance.client.from(...)`) напрямую в методах `build()` или обработчиках событий виджетов. Логика должна быть вынесена в провайдеры (Riverpod) или `Supa`-сервисы.
> 3. **Стейт-менеджмент**: Основной инструмент — **Riverpod**. Не используйте `StatefulWidget` для хранения глобальных данных, работайте через провайдеры.
> 4. **Языковой стандарт**: Весь UI-текст должен быть на русском языке (`ru`). Комментарии и код — на английском.
> 5. **Дизайн-код (Flat Magic)**:
>    - Придерживайтесь схемы **Deep Charcoal & Sophisticated Gold** (`#C5A059`).
>    - **ЗАПРЕЩЕНО** использовать свечение (`boxShadow`), яркие градиенты и эффект глянца для основных кнопок. Стиль должен быть плоским (Flat) и матовым.
>    - Для Desktop используйте `ConstrainedBox(maxWidth: 450)` для центрирования контента.
> 6. **Проактивность Агента**: Если я вижу в коде нарушение этих правил (например, прямой вызов Supabase в UI или "вырвиглазные" цвета), я ОБЯЗАН предложить рефакторинг перед выполнением основной задачи.
> 7. **Синтаксическая безопасность**: При редактировании глубоко вложенных деревьев виджетов (Scaffold -> Safe -> Center -> Scroll -> Constrained) ВСЕГДА проверяйте количество закрывающих скобок. Рекомендуется использовать `write_to_file` для перезаписи всего метода `build` при обнаружении коррупции.

---
## 🔐 Env / Ops Recovery

> [!IMPORTANT]
> Реальные env-файлы ignored. Не коммитьте секреты, backup-архивы, Firebase private key, HolliHop key, Supabase service role, DB URL с паролями или Telegram token.

| Файл | Назначение |
|------|------------|
| `server/.env` | Локальный NestJS backend, DB, email/push providers, HolliHop key, local migration DB URL. |
| `server/.migration.env` | Безопасные дефолты импортов: dry-run, batch size, Supabase export dir, HolliHop mode. Секреты брать из `server/.env`. |
| `infra/staging/.env` | Staging Docker Compose runtime для `api.magicmusiccrm.ru`. |
| `infra/staging/.backup.env` | Backup root/storage root/encryption passphrase для `backup-staging.sh` и `restore-staging.sh`. |
| `infra/staging/.monitor.env` | Health URL, disk threshold, service list and alert sink for `monitor-staging.sh`. |
| `infra/staging/.deploy.env` | SSH/deploy координаты: `magicdeploy@161.104.49.153` (`api.magicmusiccrm.ru`; старый `161.104.50.105`/`api.phantom-net.ru` выведен из эксплуатации 2026-07), key `C:/Users/potyl/.ssh/mmcrm_proxy_ed25519`, remote `/opt/magicmusiccrm`. |
| `.flutter.env` | Build-time values for Flutter; Flutter still needs these passed as `--dart-define`. |

Минимальные проверки после env-правок:
- `cd infra/staging && docker compose --env-file .env config -q`
- `cd server && npm run typecheck`
- `flutter analyze`

---
> **Самопроверка**: Готовы? Предложите пользователю запустить `/quickstart` для новой задачи.
