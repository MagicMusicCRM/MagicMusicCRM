# Release candidate `1.5.7+187`

Дата: `2026-08-13`

Результат: **PASS**

## Зафиксированный кандидат

- Runtime revision:
  `0e7411e60a105a9912ab6f30789cb29a86496e32`.
- Server image: `magicmusiccrm-server:1.5.7-187-0e7411e6`,
  `sha256:831ea160e7a8d763bdb19e8eb5259d51bea7426fab1f9135b812b195036cdd86`.
- OCI version/revision/user: `1.5.7+187`, полный runtime revision, `magiccrm`.
- Migration head: `0135_requeue_organization_outbox`.

## Закрытые дефекты

- Сохранение карточек Staff/Teacher больше не падает из-за неполного SQL
  `GROUP BY` lifecycle-полей.
- Создание и редактирование Staff/Teacher поддерживает роль доступа и несколько
  филиалов; backend сохраняет actor hierarchy и resource scope.
- Unified CRM field visibility совместима с publish-validator, который всё ещё
  принимает wire scopes `lead`/`student`.
- Desktop workspace держит вкладки mounted и не теряет вложенный маршрут,
  фильтры и незавершённый ввод при переключении.
- Platform outbox понимает organization lifecycle events для branch, room,
  group и person. Миграция `0135` возвращает только delivery metadata ранее
  dead-lettered событий, не изменяя сам append-only event fact.

## Gates

- Flutter analyze: PASS; полный suite `796/796`.
- Backend: `180/180` suites, `1424/1424` tests; typecheck/build PASS.
- Production-like runtime: migrations, fail-closed production flags,
  live/ready, V4/V4 и reconciliation `issues=[]` PASS.
- Exact image: healthy и ожидаемый degraded readiness `503` PASS.
- Trivy: `0` High/Critical; image secrets `0`.
- Gitleaks для runtime diff: утечек нет.
- Windows portable и Setup: version/install/launch/uninstall PASS.
- Android 15/API 35: update `184 -> 187`, cold launch и resumed MainActivity
  PASS; crash buffer, `AndroidRuntime`, `E/flutter` и `FlutterError` пусты.
- APK v2: один signer; certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB signature PASS; certificate valid until `2053-10-15`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 531 179` | `694372882A2A4BCDEC8871504A104502D7EF4DAB2508910B0DBDC7576663BEA7` |
| Windows Setup | `15 378 824` | `0800CB46BED0BD6B5B1D7ED51BA1D935BB70A84E581C69E5176C04FCEC112E2C` |
| Android APK | `86 246 797` | `05F6D5C6B2260B16BA0E699CE16C2A0E3CF566ACD0DD9F6D29D47933603554F6` |
| Android AAB | `60 605 899` | `E05F7B8BAFB7079DD8CE8209CC6E43E72FDA0440F7EDEF9DA44EFED14885374B` |
| Server tar | `82 768 384` | `608F330C8C1F074572CACCEC2367C11512F9BA4B091D92E5784FB1CBA3666CC7` |

Evidence относится только к revision и артефактам выше; последующие изменения
требуют нового gate.
