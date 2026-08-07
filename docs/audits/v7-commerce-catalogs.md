# v7 — T3.1.1 Configurable settlement and teacher-pay catalogs

**Дата:** 2026-08-07  
**Статус:** PASS

## Реализовано

- Unified CRM Configuration snapshot расширен без нового config-сервиса и без новой зависимости.
- Начальный каталог списаний содержит 7 типов: занятие, частично оплачиваемое занятие, бесплатное занятие, оплачиваемый/частично оплачиваемый/неоплачиваемый пропуск и занятие со штрафом.
- Независимый каталог оплаты преподавателю содержит 5 правил: none, standard, percent, fixed, hourly. Связующей матрицы между каталогами нет.
- Settlement validation ограничивает долю 0–200%, проверяет безопасный color token, optional fixed penalty, contexts `settle/reschedule/cancel`, стабильные уникальные ключи и хотя бы один active тип.
- Teacher rule validation проверяет mode-specific default value; percent ограничен 0–20000 basis points, денежные значения хранятся строкой minor units.
- Опубликованный тип нельзя удалить/переименовать: stable key сохраняется, для прекращения использования применяется `active=false`. Изменение label/color/rules не переписывает старую revision.
- School default и sparse branch override хранятся в тех же immutable revisions; impact считает изменения каталогов и предупреждает о применении только к будущим решениям.
- Любое изменение защищённых сегментов повторно требует `config.commerce.manage`; проверка выполняется и на draft/preview, и под shared access locks внутри publish transaction.
- Manager может публиковать разрешённый филиальный business setting, когда каталоги byte-equivalent; mixed publish отклоняется до revision/audit/realtime writes. Director/system_admin могут publish и rollback school/branch catalog.
- Migration `0109_v7_commerce_catalogs` losslessly добавляет seed во все historical effective snapshots и drafts. Down разрешён только при неизменённых seed-каталогах; настроенная revision/draft блокирует потерю данных.

## Проверки

| Gate | Результат |
|---|---:|
| Configuration PostgreSQL | 1/1 suite, 6/6 tests |
| Seed 7 settlement + 5 compensation | PASS |
| School publish / immutable rollback | PASS |
| Director branch override / rollback | PASS |
| Manager ordinary publish | PASS |
| Manager protected mixed publish | denied, writes = 0 |
| Validation / stable-key archive contract | PASS |
| Migration `0109` down → up / destructive-down guard | PASS / PASS |
| Actor Matrix + payload leak | 2/2 suites, 9/9 tests |
| Full backend | 152/152 suites, 1191/1191 tests |
| Typecheck / build | PASS / PASS |
| v7 reconcile / signed v4 reconcile | issues = 0 / drift = 0 |
| v7 inventory | finance = 243, lesson writes = 13, unowned = 0 |

## Вывод

Критерии T3.1.1 выполнены. Каталоги являются частью единственной versioned конфигурации, допускают school/branch lifecycle и не позволяют Manager изменить финансовые правила через смешанный snapshot.
