# V7 — Admin task board gate

**Дата:** 2026-08-08  
**Задача:** T7.1.1  
**Результат:** PASS

## Реализованный контракт

- Admin видит одну каноническую вкладку `Задачи` и ту же доску, что Manager/Director.
- Начальные фильтры Admin: `Мои задачи` + `Сегодня`; статус по умолчанию — открытые.
- Фильтры срока, области, статуса, приоритета, поиска и календаря можно изменить.
- Сервер разрешает Admin читать и атомарно закрывать доступные задачи, но сохраняет
  hard-deny для `workflow.task.write`: create/edit остаются Manager+.
- Visibility добавляет Admin общую доску назначенного филиала и не расширяет её
  до чужих филиалов или общешкольных управленческих данных.

## Проверки

| Gate | Результат |
|---|---|
| Flutter targeted | 21/21 PASS |
| Flutter full | 649/649 PASS |
| Flutter analyze | PASS, 0 issues |
| Backend RBAC targeted | 101/101 PASS |
| SharedTask PostgreSQL | 9/9 PASS |
| Actor Matrix + payload leak | 9/9 PASS |
| Backend full | 156/156 suites, 1244/1244 tests PASS |
| Backend typecheck/build | PASS |
| Migration `0114` | local `up → down → up` PASS |
| Inventories | routes=22, reachable=260, workspaceProduction=2, finance=256, lessonWrites=7, unowned=0 |

PostgreSQL test отдельно подтвердил обе границы: Admin видит задачу своего
филиала, назначенную другому сотруднику, и не получает её в режиме `Мои задачи`.

## Release 1.5.1+159

| Артефакт | SHA-256 | Проверка |
|---|---|---|
| Windows EXE | `EE5D60D3398143E740FDAEC06B24AF84BB177990CA0F17F4EFE6C5D3C4648EE9` | FileVersion/ProductVersion `1.5.1+159` |
| Android APK | `14C8E77ED874DB1CC3CAB8CC21765669AA354CAD74AA48E6F280FA430087C593` | versionCode `159`, versionName `1.5.1`, v2 signature PASS |

Android signer SHA-256:
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.

Production deployment и живой Admin screenshot относятся к T7.1.2 и не
подменяются локальной проверкой.
