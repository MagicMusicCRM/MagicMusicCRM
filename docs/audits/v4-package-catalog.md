# V4 Subscription Package catalog — T5.2.1

**Дата:** 2026-07-29

**Требование:** REQ-SUB-001

**Результат:** PASS

## Что реализовано

- Каталог вынесен из legacy `SubscriptionsService` в отдельные
  `PackageCatalogService` и `PackageCatalogRepository`.
- API сохраняет совместимые `price`/`lessonsTotal` и аддитивно возвращает
  canonical `basePriceMinor`, `currencyCode`, `unitCount`, `active`,
  `version`, `updatedAt` и `archivedAt`.
- `GET /crm/subscription-packages` возвращает только активные пакеты для
  Admin/Manager/Director/system_admin. Client и Teacher получают `403`;
  Teacher hard-deny нельзя снять персональным capability override.
- `includeArchived=true`, create, versioned update, archive и restore доступны
  только Director/system_admin. Generic create/update больше не меняют
  archive-state.
- Mutation, aggregate version, before/after audit, idempotency result и
  `commerce.package.changed` outbox фиксируются одной Platform Integrity
  transaction. Migration `0090` синхронизирует legacy package versions с
  `app.aggregate_versions` и сохраняет immutable
  `subscription_package_versions` для точного ответа позднего retry.
  UPDATE/DELETE истории закрыты trigger-ом и runtime grants; rollback
  fail-closed, если уже существует более ранняя version/replay evidence.
- Archive остаётся soft lifecycle transition: `is_active=false`,
  `deleted_at` и новая version. Restore возвращает тот же ID; ссылки уже
  выданных абонементов не разрываются.
- Legacy student/Lead issue paths теперь создают базовый immutable commercial
  snapshot (`discount=none`) из одной package version. Изменение каталога
  влияет только на следующую выдачу; историческая проекция читает
  display name/final price из snapshot, а не из live package.
- Flutter management projection разделена от active issuing projection.
  Manager видит read-only active list; Director/system_admin —
  create/edit/archive/restore. Архивирование явно обратимо, stale `409`
  блокирует повторную запись до явной загрузки свежей версии, а обе cache-
  проекции инвалидируются вместе. На время archive/restore блокируется вся
  строка, включая открытие редактора.
- Package selector дополнительно отбрасывает inactive/archived строки даже
  при смешанном stale cache. Цена передаётся в minor units без floating-point
  контракта.

Полный discount/installment/payment workflow остаётся следующим
`T5.2.2`; процентная оплата преподавателя не добавлялась.

## Доказанные инварианты

- Same idempotency key + same payload возвращает один результат; другой
  payload с тем же key получает `409`. Retry старой команды после появления
  следующей version возвращает именно исходную version, а не текущее состояние.
- Два concurrent writer с одной expected version дают одного победителя.
- `subscription_packages.version` всегда совпадает с
  `aggregate_versions.version`.
- Успешная catalog mutation создаёт ровно один audit и один minimal outbox;
  stale/denied mutation не оставляет частичных фактов.
- Выдача до update сохраняет package version 1 и исходный snapshot
  byte-identical; выдача после update получает version 2.
- Архивирование использованного package сохраняет FK и оба issued snapshots;
  новая выдача архивного package запрещена.

## Верификация

- exact PostgreSQL catalog + legacy issue regression —
  **2/2 suites, 15/15 tests PASS**;
- package catalog PostgreSQL suite — **6/6 tests PASS**;
- Flutter catalog/selector widget suite — **7/7 tests PASS**;
- Flutter RBAC matrix — **18/18 tests PASS**;
- Actor Matrix — **255 routes × 6 actors = 1530/1530 decisions PASS**
  (`1236 allow`, `294 deny`);
- access coverage — **255/255 private routes**, missing scopes/unexplained
  allows = 0;
- migration `0090` down→up — **PASS**;
- backend full Jest/PostgreSQL — **131/131 suites, 1083/1083 tests PASS**;
- Flutter full regression — **420/420 tests PASS**;
- backend typecheck/build и Flutter analyze — **PASS**;
- v4 inventory — **267 routes, 600 DTO fields, 5 tracked schema
  inventories, unowned=0, PASS**.
