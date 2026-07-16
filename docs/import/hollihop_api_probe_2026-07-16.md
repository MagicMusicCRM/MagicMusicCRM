# HolliHop API — что он отдаёт на самом деле (проверено 16.07.2026)

Разведка живого API ключом заказчика (`HOLLIHOP_AUTH_KEY` из `server/.env` главной
папки). Контракт: `{HOLLIHOP_BASE_URL}/Api/V2/{Method}?authkey=…`.

Это **шаг 0** из §6 чек-листа `SPEC-CHECKLIST-2806.md` («инвентаризация источника»).
Значения не выгружались и не сохранялись — только имена методов, полей и счётчики.

## Итог одной строкой

**Трёх вещей, ради которых заказчик просил пересобрать импортёр — комментариев,
задач с историей и поурочной оплаты педагогам — в этом API нет.** Не «плохо
реализовано» и не «отсеялось матчингом»: соответствующих методов и полей не
существует. Проверено прямыми вызовами.

## Методы, которые отвечают (10)

| Метод | Ответ | Ключевые поля |
|---|---|---|
| `GetOffices` | 2 | Id, Name, Address, TimeZone, Phone, NoClassrooms, Location |
| `GetDisciplines` | `{Disciplines: [4]}` | массив строк |
| `GetLevels` | 3 | Name, Disciplines[] |
| `GetLeadStatuses` | `{Statuses: […]}` | — |
| `GetTeachers` | 2+ | Id, FirstName, LastName, MiddleName, Birthday, EMail, Mobile, Phone, Status, StatusId, Fired, Corporative, Created, **Disciplines[]**, **Levels[]**, **Maturities[]**, **Offices[]** |
| `GetStudents` | 3105 | Id, **ClientId**, FirstName, LastName, MiddleName, Gender, Mobile, Phone, Status, StatusId, Created, Updated, AddressDate, VisitDateTime, Maturity, **Disciplines[]**, **LearningTypes[]**, **OfficesAndCompanies[]**, **Assignees[]** |
| `GetLeads` | — | Id, FirstName, LastName, MiddleName, Mobile, Created, Updated, AddressDate, **OfficesAndCompanies[]**, **Assignees[]** |
| `GetEdUnits` | 2335 | Id, Name, Type, Discipline, Level, Maturity, LearningType, Corporative, **Assignee{Id,FullName}**, **ScheduleItems[]**, StudentsCount, StudyUnitsInRange, Vacancies, OfficeOrCompany* |
| `GetEdUnitStudents` | — | EdUnitId, **StudentClientId**, StudentName, StudentMobile, StudentPhone, Status, BeginDate/Time, EndDate/Time, Weekdays, **StudyMinutes**, **StudyUnits**, EdUnit* |
| `GetPayments` | — | Id, **ClientId**, ClientName, Date, PaidDate, **Value**, ValueCurrency, ValueQuantity, PaymentMethodId/Name, State, Type, OfficeOrCompany* |

## Методы, которых НЕТ (HTTP 404)

Все до единого, включая **все 15, на которые ссылаются наши же доки**:

`GetComments`, `GetCommunications`, `GetEdUnitLessons`, `GetHistory`,
`GetInvoices`, `GetLessons`, `GetSchedule`, `GetStudentLogs`,
`GetStudentServices`, `GetSubscriptions`, `GetSystemLogs`, `GetTasks`,
`GetActions`, `GetUsers`, `GetStudentClients`, `GetClients`,
`GetStudentClientComments`, `GetLeadComments`, `GetCategories`,
`GetEdUnitStudentsPayments`.

⚠️ **`docs/import/hollihop_field_map.md`, `hollihop_source_inventory.md`,
`hollihop_gap_report.md` и `hollihop_importer_v2.md` описывают несуществующий
API.** Именно отсюда в чек-лист попал неверный диагноз «импортёр не привёз
задачи/комментарии» — привезти их было неоткуда.

## Что это значит для требований заказчика (§6)

| Требование | Вердикт |
|---|---|
| **Комментарии** | ❌ метода нет. 16656 комментариев на проде пришли из **ручной выгрузки файлами**, а не из API |
| **Задачи с историей по датам/времени** | ❌ `GetTasks` → 404. 514 задач на проде — тоже из файловой выгрузки. Истории изменений нет и в ней: ответственный лежит **внутри текста описания** («поставил ФИО — дата»), поэтому у всех 514 задач `assigned_to = NULL` |
| **Поурочная оплата педагогам** | ❌ в `EdUnits` нет ни одного поля `Price/Pay/Rate/Cost/Salary` (проверено регуляркой по сырому JSON). `GetPayments` — это платежи **клиентов**, не выплаты педагогам |
| **Привязка педагогов к занятиям** | ⚠️ частично. Прежний диагноз («schedule fields contain teacher data») **неверен**: `ScheduleItems` — это `BeginDate, BeginTime, EndDate, EndTime, Weekdays, ClassroomId, ClassroomName, Id`, педагога там **нет**. Педагог есть только на уровне учебной единицы: `EdUnit.Assignee {Id, FullName}` — один на всю группу, не по занятиям |

## Технические особенности, которые обязан учесть любой импортёр

1. **`take` работает не везде.** `GetStudents?take=1` → 1 запись. `GetEdUnits?take=2` → **2335 записей** (параметр игнорируется), внутри 15098 `ScheduleItems`. Пагинацию нельзя считать единообразной — по `EdUnits` приходит всё разом, и это надо переваривать потоково.
2. **Ответ завёрнут в объект, не массив**: `{Disciplines: […]}`, `{Statuses: […]}`, `{EdUnits: […]}`. Разворачивать по имени метода.
3. **Внешний ключ есть**: у учеников `Id` + `ClientId`, у платежей и `EdUnitStudents` — `ClientId`. То есть upsert по внешнему id возможен (в отличие от прежнего матчинга по телефону, который и терял записи).

## Что можно сделать, а что нельзя

**Можно** (данные в API есть): upsert учеников/лидов/педагогов/учебных единиц/
платежей по внешнему id, привязка педагога к группе через `Assignee.Id`,
расписание серий через `ScheduleItems`, уровни/дисциплины/филиалы.

**Нельзя из API** (нужны свежие выгрузки файлами из интерфейса HolliHop либо
ключ с другими правами): комментарии, задачи, история изменений, поурочная
оплата педагогам.

## Состояние старого импортёра

Он **не потерян** — его сознательно вывели из эксплуатации, когда миграция
завершилась: коммит `7f2a3fd7` «chore: remove retired migration tooling»
(14.07.2026), с формулировкой «HolliHop import is complete and reconciled, so
the one-off cutover tooling is dead weight». Исходники восстанавливаются из
истории:

```
git show 7f2a3fd7^:server/src/migration/hollihop-import.ts
git show 7f2a3fd7^:server/src/migration/import-hollihop-exports.ts
```

Так что тезис чек-листа «кода импортёра в репозитории НЕТ, перед починкой нужно
найти его исходники» — **неверен**: код есть в git, и он делал ровно то, что
позволяет API.
