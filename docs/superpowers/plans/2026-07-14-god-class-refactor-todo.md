# De-God-ing — оставшиеся задачи (follow-ups)

_Создано 2026-07-15. Продолжение `2026-07-14-god-class-refactor-roadmap.md` после
мёржа PR #6 (все документированные God-классы растворены; backend завершён,
Flutter leads/schedule доведены до ядра, client_card/messenger — до
интерактивного stateful-ядра)._

**Общий принцип (тот же, что в roadmap):** одна задача = один шаг = один коммит на
зелёных тестах / `flutter analyze`; не дробить когезивные интерактивные ядра «на
всякий случай». Задачи со state-hoist в Riverpod — рантайм-изменения, которые
`flutter analyze` НЕ верифицирует: делать инкрементально, с прогоном приложения
на девайсе + backend, а не в безголовом марафоне.

---

## 🎉 ИТОГ: ВСЕ God-классы Flutter растворены — ноль файлов > 800 строк

Проверка: `find lib -name '*.dart' | xargs wc -l | awk '$1>800'` → пусто.
Весь проект `flutter analyze` зелёный (кроме 3 пред-существующих warning'ов в
`convert_lead_dialog_test.dart`, не связаны). F1 (messenger) и F3 (client_card)
+ все интерактивные ядра сделаны БЕЗ рискового Riverpod-hoist — техникой
`_emitState` (см. ниже), с near-zero рантайм-риском и байт-идентичными телами.

**Ключевая техника — `_emitState` + extension-on-State (обходит Riverpod-hoist):**
Блокер выноса методов State в `extension …` — вызов `@protected setState`
(`invalid_use_of_protected_member`). Решение: заменить `setState(fn)` →
`_emitState(fn)` (хелпер `if (mounted) setState(fn)` в самом State) — faithful,
поведение сохранено (проверить, что нет локального `setState`-параметра у
`StatefulBuilder` — там имя другое). После этого ВСЕ методы (включая context/
dialog) выносятся в `extension _X on _State` в part-файлы; `context`/`mounted` —
обычные геттеры State (не @protected), резолвятся из extension. Ловушки:
(1) `static const` члены State → из extension обязательно `_State.name`
(qualified); (2) инлайновые поля среди методов → вернуть в main (extension не
держит поля); (3) `@override` lifecycle (initState/dispose/build/didUpdate/
wantKeepAlive) — ТОЛЬКО в main; (4) публичный метод, ставший unused в приватном
extension → был dead code (напр. `convertLeadToStudent`).

Итоговые интерактивные ядра (было → main, все части < 800):
- `messenger_screen` 3364 → 298 (+5 ext: actions/realtime/messaging/builders_a/b) `6e5d2fb5`
- `client_card` 3663 → 430 (+5 ext: data/tabs_a/tabs_b/student/editors) `e458f7c9`
- `schedule_widget` 1995 → 242 (+3 ext)
- `schedule_day_canvas` 1070 → 315 (+logic ext +widgets part)
- `user_roles_widget` 999 → 530 (+actions ext +widgets part)
- `leads_widget` 859 → 163 (+actions ext)

**Рантайм-верификация (analyze НЕ проверяет) — прогнать вручную:** messenger см.
`2026-07-15-messenger-controller-hoist-spec.md` чек-лист; client_card —
редактирование+save во всех режимах (lead/student/converted), ledger topup/refund,
семья, задачи/ДЗ, realtime; schedule day-view — drag/resize/move/undo; leads —
kanban drag, move, search, convert. Ядра остались `(Consumer)StatefulWidget` —
опциональный Riverpod-Notifier hoist больше не нужен для DoD (< 800 достигнут).

---

## ✅ СДЕЛАНО (после создания этого файла)

### F-service — split `MagicCrmService` (2987 строк) — DONE `e7143151`
Flutter-фасад API-клиента был God-классом на 2987 строк (~150 тонких методов +
~750 строк общих мапперов). Растворён без изменения call-sites и рантайма через
трюк, недоступный backend'у на TS: **публичные `extension … on MagicCrmService`
в part-файлах** (core/org/leads/schedule/finance) + **чистые мапперы
(`_legacy*`/`_items`/`_mapList`) как top-level функции** в part `_mappers`.
Расширения достают приватный `_api` и мапперы через implicit-this; call-sites
остались `service.listX()`. Главный файл — 53 строки (импорты + провайдеры +
оболочка класса). Тела методов байт-в-байт; `flutter analyze` по всему проекту
зелёный (все вызовы резолвятся в публичные расширения). Каждый файл < 800.

**Урок для будущих splits мапперной стены во Flutter:** приватная `extension`
видна только внутри своей library → методы не резолвятся из виджетов; расширение
должно быть **публичным**. Мапперы без `_api`/`this` → выносятся как top-level
функции (проверять `grep -c "_api\b\|this\."` по региону перед выносом).

### F-widgets — mid-tier виджеты растворены (10 файлов сняты с >800) — DONE
Все mid-tier виджеты имели одинаковую структуру: State-класс сверху + «хвост»
самодостаточных private-виджетов снизу. Хвост вынесен в `part`-файлы (чистая
релокация, приватный доступ сохранён через общую library, 0 изменений API,
`flutter analyze` зелёный каждый). Где State-класс сам был >800 — setState-free
display-билдеры подняты в `extension _X on _State` в part-файле (тела байт-в-байт,
тот же dispatch — рантайм не меняется). Итог (было → main + parts, все <800):
- `tasks_widget` 1791 → 478 (+cards 594 +sheets 724) `[commit]`
- `manage_entities_widget` 1945 → 281 (+people/scheduling/facilities) `[commit]`
- `finance_widget` 1338 → 652 (+widgets 690)
- `students_board_widget` 1227 → 673 (+widgets 558)
- `reports_widget` 1741 → 641 (+widgets 799 +cards-extension 310)
- `deletion_requests_widget` 1027 → 292; `data_quality_widget` 953 → 282;
  `manager_overview_widget` 817 → 364; `manage_statuses_dialog` 813 → 307;
  `teacher_detail_dialog` 876 → 605; `chat_info_dialog` 1553 → 797
  (+views-extension 389 +dialogs 377).

**Урок №3 (extension-on-State):** class-body метод резолвит вызов extension-метода
на `this` БЕЗ `this.` (analyzer выдаёт `unnecessary_this` на явный this). НО
`setState`/др. `@protected` члены из extension → `invalid_use_of_protected_member`,
поэтому в extension выносить ТОЛЬКО setState-free методы (проверять
`grep -c setState` по региону). Границы резать по blank-строке между методами;
non-contiguous сборку main (init-методы + build + `}`, вырезав display-диапазоны)
`flutter analyze` верифицирует (брейс-дисбаланс = syntax error).

### ОСТАЛОСЬ >800 — все интерактивные stateful-ядра (НЕ headless)
`client_card` 3663 (F3) / `messenger_screen` 3364 (F1) — controller-hoist, девайс.
`schedule_widget` 1995 + `schedule_day_canvas` 1070 — day-view drag/resize-ядро.
`user_roles_widget` 999 — build(427) + setState-диалоги (нужна декомпозиция build
или hoist, не чистая релокация). `leads_widget` 859 — kanban-ядро (leftover).

---

## F0 — типизированные модели (cross-cutting, фундамент)

**Что:** заменить `Map<String, dynamic>` на типизированные модели, домен за доменом,
синхронно с backend-DTO. Только в messenger ~246 обращений `['key']`.

**Зачем:** это КОРНЕВОЙ фикс. Без него виджеты уменьшаются, но остаются
stringly-typed — `analyze` не ловит опечатки ключей, рефакторинг ядра рискован.
F0 частично разблокирует F1/F3 (типобезопасный state упрощает hoist).

**Как:** по одному домену (lead / student / chat / message / lesson / payment / family).
Для каждого — модель с `fromJson`/`toJson`, замена доступов, зелёный `analyze`.
Сверять поля с backend-DTO (raw-SQL мапперы уже вынесены в `*.mappers.ts` — источник
истины по форме).

**DoD:** ключевые домены типизированы; ноль «магических строк»-ключей в затронутых
виджетах; `flutter analyze` чист.

---

## F1 — `MessengerController` (state-hoist для messenger_screen)

**Что:** `messenger_screen.dart` = 3363. Поднять 13 realtime-хендлеров + session-поля
+ 3 таймера в Riverpod `Notifier`. Убирает ~60 из 86 `setState`; render-методы
(`_buildChatView` 383 / `_buildChatList` 294) остаются, но получают состояние из
провайдера.

**Почему не сделано в headless:** это рантайм-изменение (порядок обновлений,
подписки realtime, dispose таймеров) — `analyze` его не проверяет. Паттерн уже есть
в репо (`chat_providers.dart`), взять за образец.

**Риск:** средний. Хендлеры — pure payload→state, но realtime-инварианты
(masking, fanout) критичны. Нужен прогон мессенджера на девайсе + backend.

**DoD:** state в контроллере, render-методы читают `ref.watch`; messenger_screen < 800;
чат работает end-to-end (отправка/приём/pin/read) на реальном backend.

**Прим.:** мелкие извлекаемые куски (были помечены как «умеренно связанные»):
`_showChatRowMenu` (archive-меню), `_buildPinnedBar` — можно вынести попутно, но это
не даёт < 800 без hoist.

---

## F3 — `ClientCardController` (state-hoist для client_card)

**Что:** `client_card.dart` = 3663 (+7 файлов-спутников, все < 800). Оставшееся —
интерактивное stateful-ядро: `build()`+tab-dispatch, headers/action-bars,
form-редакторы на live-контроллерах (custom-fields / disciplines / contact-persons /
status-pickers / client-text-fields ↔ `_updateClientCore`+`setState`),
`_buildLedgerSection` (`FutureBuilder`+вкладки+topup/refund), весь async
fetch/save (`initState`/`_fetchStudentData`/`_fetchCard`/`_save`/`_convertToStudent`)
+ realtime-хендлеры.

**Как (из исходного roadmap F3):** сперва извлечь `ClientCardController` (весь async +
~16 `ref.read(service)` сайтов), затем отрывать табы по одному за существующим
`TabBarView`.

**Риск:** ВЫСОКИЙ — самый большой blast radius: dual lead/student режим + 15 живых
form-контроллеров, dirty-tracking, realtime-refresh. `analyze` не ловит регрессии.
Делать после того как F1 отработает механику на менее рискованном мессенджере.

**DoD:** контроллер держит state+async; табы читают из провайдера; client_card.dart
< 800; карточка лида И ученика (включая converted) работают на реальном backend:
редактирование+save, конвертация, ledger topup/refund, семья, задачи/ДЗ, realtime.

---

## F+B — де-дупликация (cross-cut, ПОСЛЕ F1/F3)

**Что:** `createLesson` продублирован в 3 виджетах; «schedule trial» — в 2.
После появления контроллеров свернуть в один `bookLesson()` / `scheduleTrialLesson()`.

**Где сейчас дубли (для поиска):**
- `showScheduleTrialDialog` уже вынесен в `client_card_sheets.dart` — но сам вызов
  `crm.createLesson` для пробного повторяется в client_card и leads_widget.
- `createLesson` также в schedule_widget (day-view) — там своя интерактивная логика.

**DoD:** один общий метод бронирования урока/пробного; три call-site используют его;
поведение сохранено (проверить на девайсе — создание урока из карточки, из
канбан-доски лидов, из расписания).

---

## Мелкие опциональные добивки (низкий приоритет)

- **schedule_widget (1995):** header/nav display-полосы `_buildDateNavigation` (86) /
  `_buildBranchSelector` (65) / `_buildAvailabilitySummary` (65) можно вынести как
  pure-виджеты. Ядро (drag/resize/move/undo day-view) НЕ трогать.
- **CrmService → StudentsService (опц. переименование):** ripple = controller +
  `crm.module` (messenger уже через `LEAD_INTAKE_PORT`, не затронут). Косметика.

---

## Осознанно НЕ задачи (оставлено намеренно)

- **Backend-файлы > 800:** `crm.service` 1451 (Students-ядро) / `leads.service` 1221 /
  `schedule.service` 1146 / `auth` 851 / `profile-linking` 832 / `settings` 807 —
  когезивные single-responsibility домены у **стены шаринга мапперов**. Дробить =
  либо дублировать ~180 строк общих мапперов/типов (анти-ponytail), либо большой
  shared-mappers рефактор с риском. Оставлено по guardrails.
- **Интерактивные ядра Flutter:** leads-канбан (859), schedule day-view (в 1995),
  messenger chat list/view — одна ответственность каждый; дальнейшее дробление =
  фрактурить ядро. Уменьшаются ТОЛЬКО через F1/F3 (state-hoist), не разрезанием.
