# Prompt for Developer Agent - Implement Schedule Redesign and Rebuild Apps

Ты работаешь в проекте:

`C:\Projects\MagicMusicCRM`

Твоя задача - реализовать утвержденный UX/UI редизайн вкладки `Расписание` по визуальным примерам из этой папки.

Это фаза P2/KVA-195: расписание. Главный принцип проекта - reskin/wire-up existing app, not backend rewrite. API-контракты менять нельзя.

## Перед началом обязательно прочитай

1. `AGENTS.md`
2. `.anws/v3/05_TASKS.md`
3. `docs/migration/WIRE-TO-SERVICE-CHECKLIST.md`
4. `docs/migration/REDESIGN-MIGRATION-PLAN.md`
5. `docs/prototypes/crm-redesign-v7.html`
6. `docs/audits/ui-redesign-2026-06-24/schedule-redesign-flow.html`

Также открой все PNG из раздела "Визуальная спецификация" ниже. PNG являются UX specification, не декоративными картинками.

## Важное правило по server/

Это фронтовая задача.

Не меняй `server/`.

Перед началом сними baseline:

```powershell
git diff -- server > C:\Projects\MagicMusicCRM\docs\audits\ui-redesign-2026-06-24\schedule-server-diff-before.patch
```

После реализации сними повторно:

```powershell
git diff -- server > C:\Projects\MagicMusicCRM\docs\audits\ui-redesign-2026-06-24\schedule-server-diff-after.patch
```

Если baseline уже был не пустым, не трогай и не откатывай эти чужие изменения. В финальном ответе докажи, что твоя работа не изменила `server/` относительно baseline.

## Главная задача

Пересобрать UX расписания для администратора/управляющего:

- режимы `Год / Месяц / День`;
- `Месяц` как понятный календарный слой с переходом в день;
- `День` как рабочая сетка по времени с 08:00 до 00:00;
- вертикальное выделение временного диапазона для создания занятия;
- tap/click по одному часовому блоку создает занятие на 1 час;
- вертикальный перенос существующего занятия вверх/вниз меняет время;
- горизонтальный перенос существующего занятия меняет аудиторию/комнату с сохранением остальных данных;
- resize занятия за верхний/нижний край доступен только после hover/focus на занятии;
- drag near edge запускает autoscroll по горизонтали или вертикали, когда полотно больше экрана;
- мобильная версия должна оставаться usable: горизонтальный и вертикальный scroll, безопасные touch targets, без конфликтов жестов.

## Визуальная спецификация

Все ссылки ниже открываются из текущей папки `docs/audits/ui-redesign-2026-06-24/`.

### 1. День - статичная сетка

[schedule-flow-01.png](schedule-flow-01.png)

Что реализовать:

- сетка расписания от 08:00 до 00:00;
- широкий столбец времени;
- более узкие колонки аудиторий;
- рабочее полотно может быть шире и выше экрана;
- видимые scroll affordances;
- никаких повторяющихся текстов на ячейках вроде `Нажмите чтобы добавить занятие`;
- инструкция и правила работы только в легенде/панели, не в каждой ячейке.

### 2. День - вертикальное выделение нового занятия

[schedule-flow-02.png](schedule-flow-02.png)

Что реализовать:

- пользователь зажимает пустую ячейку и тянет строго вертикально;
- горизонтальное выделение диапазона запрещено;
- выделенный вертикальный диапазон показывает длительность;
- release открывает форму создания занятия с рассчитанными `scheduledAt`, `durationMinutes`, `roomId`;
- click/tap без drag создает 1 час.

### 3. День - форма создания по диапазону

[schedule-flow-03.png](schedule-flow-03.png)

Что реализовать:

- после release открывается компактная форма/side sheet создания занятия;
- пользователь выбирает ученика/группу/лида, преподавателя и аудиторию;
- конфликты отображаются до сохранения;
- сохранение использует существующий контракт `POST /crm/lessons` через `MagicCrmService.createLesson`;
- тело запроса должно оставаться совместимым: `scheduledAt`, `durationMinutes`, one-of `student/group/lead`, `teacherId`, `roomId`, `branchId` если уже используется текущим кодом.

### 4. День - hover resize handles

[schedule-flow-04.png](schedule-flow-04.png)

Что реализовать:

- ручки растягивания появляются только на hover/focus активного занятия;
- верхняя ручка меняет начало занятия;
- нижняя ручка меняет длительность;
- resize разрешен только вертикально;
- при resize не открывать окно занятия до release;
- после release обновить занятие через существующий update flow.

### 5. День - перенос существующего занятия

[schedule-flow-05.png](schedule-flow-05.png)

Что реализовать:

- при переносе существующего занятия не показывать dashed target blocks;
- исходное занятие остается подсвеченным на старом месте до drop;
- карточка в руках двигается за указателем;
- вертикальный drop меняет время;
- горизонтальный drop меняет комнату/аудиторию;
- остальные данные занятия сохраняются.

### 6. День - autoscroll при drag

[schedule-flow-06.png](schedule-flow-06.png)

Что реализовать:

- если карточку занятия поднести к правому/левому краю, запускается горизонтальный autoscroll;
- если поднести к верхнему/нижнему краю, запускается вертикальный autoscroll;
- edge zones должны быть видимыми во время drag;
- autoscroll должен работать и на desktop mouse, и на touch.

### 7. День - результат после drop

[schedule-flow-07.png](schedule-flow-07.png)

Что реализовать:

- после drop занятие стоит в новой аудитории/времени;
- старое место больше не подсвечено;
- показывается понятный success/undo state;
- при ошибке сохранения вернуть занятие на старое место и показать error feedback;
- не оставлять optimistic state как будто сохранение прошло, если API вернул ошибку.

### 8. Mobile adaptation

[schedule-flow-mobile.png](schedule-flow-mobile.png)

Что реализовать:

- мобильное расписание тоже является scrollable canvas;
- time column остается читаемым;
- room columns доступны горизонтальным scroll;
- вертикальный scroll не конфликтует с drag/resize;
- touch targets не меньше практичного размера;
- edge autoscroll работает, когда карточка в руках.

### 9. Год

[schedule-flow-year.png](schedule-flow-year.png)

Что реализовать:

- режим `Год` показывает 12 месяцев;
- для каждого месяца видна нагрузка/количество занятий и состояния вроде конфликтов;
- активный месяц выделен;
- клик по месяцу переводит в режим `Месяц`;
- это обзорный экран, не экран редактирования занятий.

### 10. Месяц

[schedule-flow-month.png](schedule-flow-month.png)

Что реализовать:

- режим `Месяц` - крупная календарная сетка, не ужатый список;
- ячейки дней показывают плотность занятий, пробные, конфликты;
- выбранный день имеет side summary;
- клик по дню переводит в режим `День`;
- данные брать через существующий `MagicCrmService.getScheduleMonthSummary`.

## UX rules from owner approval

1. Цветовая палитра текущего dark/gold redesign нравится владельцу. Не ломай ее.
2. Не делай серый однотонный фон вместо полноценной сетки.
3. Колонки аудиторий должны быть уже, столбец времени шире.
4. Полотно может быть больше экрана и должно скроллиться по X и Y.
5. Горизонтально нельзя выделять диапазон для создания занятия.
6. Горизонтальный drag существующего занятия разрешен только как смена комнаты/аудитории.
7. При переносе существующего занятия не показывать dashed outline targets.
8. Dashed selection допустим для создания нового диапазона на пустой сетке.
9. Resize handles показывать только после hover/focus на занятии.
10. Все инструкции вынести в легенду/панель, а не писать поверх каждой ячейки.
11. Старые данные должны оставаться видимыми во время загрузки/refetch, если это возможно.
12. Ошибки, конфликты и pending states должны быть явно видимы.

## Likely implementation files

Начни с этих файлов и не делай blind rewrite:

- `lib/features/admin/presentation/widgets/schedule_widget.dart`
- `lib/features/admin/presentation/widgets/create_lesson_dialog.dart`
- `lib/features/admin/presentation/providers/schedule_navigation_provider.dart`
- `lib/core/services/magic_crm_service.dart`
- `lib/core/widgets/skeletons.dart`
- `test/features/admin/schedule_day_view_test.dart`
- `test/features/s8_desktop_ux_states_test.dart`
- `test/core/services/magic_crm_service_test.dart`

Кодовые якоря:

- `MagicCrmService.getScheduleMatrix`
- `MagicCrmService.getScheduleMonthSummary`
- `MagicCrmService.createLesson`
- `MagicCrmService.updateLesson`
- `MagicCrmService.deleteLesson`
- `_scheduleConflicts`
- current day/month schedule state in `ScheduleWidget`

## API constraints

Не меняй API contracts:

- `GET /crm/lessons`
- `GET /crm/schedule/matrix`
- `GET /crm/schedule/month-summary`
- `POST /crm/lessons`
- `PATCH /crm/lessons/:id`
- `DELETE /crm/lessons/:id`
- attendance endpoints if currently surfaced

Regression checks from migration plan:

- booking still emits same compatible `POST /crm/lessons` body;
- conflict types remain server-derived via `schedule/matrix`;
- pair-dedup logic remains backend-owned;
- teacher role restrictions are not bypassed in frontend;
- per-branch time rendering is preserved;
- reschedule still uses existing `PATCH /crm/lessons/:id` path.

## Step-by-step implementation plan

1. Read context files and inspect current `ScheduleWidget`.
2. Take screenshots or notes of current UI before editing.
3. Capture `server/` diff baseline as described above.
4. Map current schedule state: selected mode, date, branch, room, teacher toggle, loading/error/empty states.
5. Introduce or cleanly refactor a schedule view model for modes:
   - `year`
   - `month`
   - `day`
6. Implement `Год` view:
   - 12 month cards;
   - selected/current month state;
   - counts/conflict indicators from available summary data or existing loaded data;
   - month click -> `Месяц`.
7. Implement `Месяц` view:
   - full calendar grid;
   - selected day side summary;
   - day click -> `День`;
   - use `getScheduleMonthSummary`.
8. Rebuild `День` view canvas:
   - sticky/wide time column;
   - narrower room columns;
   - horizontal and vertical scroll;
   - stable grid dimensions;
   - no instructional text inside cells.
9. Implement empty-cell interactions:
   - click/tap = 1 hour create;
   - vertical drag = multi-hour create;
   - horizontal range selection blocked/cancelled.
10. Wire create form:
   - pass selected time span and room;
   - show conflicts;
   - save through existing service.
11. Implement existing lesson drag:
   - source lesson highlighted;
   - dragged card follows pointer;
   - no dashed targets;
   - vertical move changes time;
   - horizontal move changes room.
12. Implement hover/focus resize:
   - top and bottom resize handles;
   - visible only on hover/focus;
   - release commits via update flow.
13. Implement drag edge autoscroll:
   - left/right/top/bottom edge zones;
   - desktop mouse and touch support;
   - no gesture conflict with normal scroll.
14. Add optimistic UI with rollback:
   - pending state during save;
   - success/undo feedback;
   - rollback on API error.
15. Preserve loading/empty/error transparency from S8:
   - no blank schedule;
   - retry remains visible;
   - headers remain visible.
16. Add tests for:
   - mode switching year/month/day;
   - month day click opens day;
   - click empty cell opens 1h create;
   - vertical drag computes duration;
   - horizontal selection for create is not accepted;
   - lesson horizontal move changes room;
   - lesson vertical move changes time;
   - resize handles hidden until hover/focus.
17. Run verification and rebuild artifacts.

## Required verification

Run at minimum:

```powershell
flutter analyze
flutter test test/features/admin/schedule_day_view_test.dart
flutter test test/features/s8_desktop_ux_states_test.dart
flutter test test/core/services/magic_crm_service_test.dart
flutter test
```

Also verify server baseline:

```powershell
git diff -- server
```

If baseline was not empty before your work, compare before/after patch files and state that no new server changes were introduced.

## Visual QA required

After implementation, run the app and visually check as manager/admin:

1. `Год` view.
2. `Месяц` view.
3. `День` static grid.
4. Click empty cell -> 1 hour create.
5. Vertical drag empty cells -> multi-hour create.
6. Horizontal drag empty cells does not create a range.
7. Existing lesson vertical drag -> time change.
8. Existing lesson horizontal drag -> room change.
9. Hover lesson -> resize handles appear.
10. Resize top/bottom edge -> duration/start changes.
11. Drag near canvas edge -> autoscroll.
12. Mobile narrow viewport/adaptive preview.

Capture screenshots or short video evidence if possible.

## Required rebuilds

After tests pass, rebuild desktop and Android artifacts.

Windows release:

```powershell
flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Then recreate/update the distribution folder and zip under:

```text
C:\Projects\MagicMusicCRM\dist\
```

Android APK:

```powershell
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

If release process requires AAB:

```powershell
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.phantom-net.ru/api
```

Record final artifact paths and SHA-256 hashes.

## Final response required from developer agent

Return:

- files changed;
- exact schedule UX implemented;
- visual evidence paths;
- tests run and results;
- Windows artifact path and SHA-256;
- Android APK/AAB path and SHA-256;
- statement that `server/` was not changed relative to baseline;
- any remaining limitation or backend/data blocker.
