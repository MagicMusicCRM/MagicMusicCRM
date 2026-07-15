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
