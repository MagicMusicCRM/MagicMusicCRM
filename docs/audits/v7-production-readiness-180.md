# MagicMusicCRM v7 — production readiness candidate 1.5.1+180

- Дата: `2026-08-10`
- Commit: `964f79cae8dc03e448efb4d9fb9f1e8f0642456d`
- Ветка: `codex/v7-production-readiness`
**Основа:** `origin/main` at `7ff286347ad969a9faf729b8a2c549df79fb91d3`

## Решение

- **Технический release candidate:** `PASS`.
- **Production rollout:** `NOT PERFORMED`; production не изменялся.
- **Итоговая сдача заказчику:** `NOT YET APPROVED`, потому что owner production
  mega-UAT остаётся `7 PASS / 32 PARTIAL / 61 PENDING` и `INT-S6` открыт.

Технические gates доказывают, что кандидат можно передавать на controlled
rollout и продолжение owner UAT. Они не являются подписью владельца и не
подменяют UI/API/DB evidence обязательных production-сценариев.

## Реализованный scope

- единая финансовая projection semantics для карточек, dashboard и analytics;
- атомарный post-completion reschedule с reversal/exclusion и новым scheduled
  successor;
- canonical conflict engine без bypass для one-time/recurring операций и
  редактируемый конфликтный Plan без partial lesson commit;
- корректные payment/task labels и all-day overdue semantics;
- необязательная вместимость аудитории и cursor auto-pagination;
- архивирование клиента через canonical завершение планов и отмену будущих
  занятий с сохранением immutable истории;
- production fail-closed для access/schedule v4 и parity zero;
- расписание с dropdown-фильтрами, адаптивным видом «По преподавателям», тремя
  фонами `Забронировано`/`Завершено`/`Конфликт` и отдельным badge `Пробное`.

## Автоматические gates

| Контур | Результат |
|---|---|
| Backend full Jest | `157/157` suites, `1256/1256` tests, PASS |
| Backend build | PASS |
| Flutter full test | `666/666`, PASS |
| Flutter analyze | `No issues found`, PASS |
| Diff integrity | `git diff --check`, PASS |
| Fresh PostgreSQL | `0001..0118`, latest `0118_lesson_participant_exclusions`, PASS |
| Rollback/reapply | `0118..0116 down`, затем `0116..0118 up`, PASS |
| Production-like runtime | invalid flags fail startup; v4/parity-zero live+ready, PASS |
| V7 reconciliation | `0 issues`, PASS |
| Workspace device E2E | Windows `3/3`, Android `3/3`, revision `964f79c`, PASS |

Production-like gate использовал только выделенную временную БД
`magiccrm_v7_prodlike_gate` и удалил её после проверки. Production API/DB не
мутировали.

## Security gates

| Проверка | Результат |
|---|---|
| Repository security preflight | runtime env/source maps PASS; npm audit PASS |
| Gitleaks staged candidate diff | `0` findings |
| Semgrep OWASP Top 10 | 91 rules, 2066 tracked files, `0` findings |
| Trivy filesystem vuln+secret | `0` High/Critical vulnerabilities, `0` secrets |
| Trivy pinned Node runtime | `0` High/Critical OS vulnerabilities |
| Trivy Dockerfile config | `0` High/Critical misconfigurations |
| npm audit | `0` vulnerabilities |

Semgrep выдал один non-blocking partial-parse warning на многострочную
RUN-конструкцию существующего `server/Dockerfile`; этот файл независимо полностью
проверен Trivy config. History-aware Gitleaks на 781 commits повторно показывает
167 legacy findings в 12 старых commits, преимущественно в удалённом Android
bugreport и legacy HolliHop artifacts. Это ранее явно принятый владельцем
historical risk из `v7-final-candidate.md`; новых находок staged diff нет. Риск
не добавлен в allowlist и исчезает только после согласованной ротации/rewrite.

## Release artifacts

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.1-180-windows-x64.zip` | 19,314,097 | `A0217B9AD30D8AB11FA9E5A091569794A27C0B1F4B2346B04521B46AFB64DA2D` |
| `MagicMusicCRM-1.5.1-180.apk` | 84,688,801 | `39A1424804DB0177D12F212D04E6C1E3C1C0F7FF36AD12708F8F3DA1ABBB50B3` |
| `MagicMusicCRM-1.5.1-180.aab` | 59,988,827 | `7A9FB287871CCCEF74AE1ABC72F125AE37FBD1A96E897D0A434637D503A0C3A3` |
| `magic_music_crm.exe` внутри Windows bundle | 757,760 | `ED3A4CB86C3182D0B9F3D8FDE9184356BCB75F5951E860A862F9D7634E3F4BD1` |

Локальный каталог: `dist/1.5.1+180/`. Windows EXE сообщает
`FileVersion/ProductVersion=1.5.1+180`; hidden launch smoke оставался рабочим
после 10 секунд. APK сообщает `versionName=1.5.1`, `versionCode=180`,
`minSdk=24`, `targetSdk=36`; APK Signature Scheme v2 — PASS, signer SHA-256
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
AAB JAR signature — PASS; upload certificate self-signed и без timestamp, что
соответствует существующему upload-key workflow.

Windows Inno Setup отсутствует в локальной среде, поэтому создан полный portable
ZIP, а не неподтверждённый installer EXE. `windows_installer.iss` обновлён до
`1.5.1+180` и может быть собран в доверенном packaging environment.

## Device smoke

- Windows Release `+180`: launch PASS, process remained alive, затем штатно
  остановлен тестом.
- Android 15/API 35 emulator: signed Release APK установлен, приложение
  запущено, versionCode `180`; `FATAL EXCEPTION`, app-specific ANR и `E/flutter`
  не найдены.
- Revision-bound functional evidence: Windows `3/3`, Android `3/3`, context
  loss `0`, silent overwrite `0`, cross-account leak `0`.

## Открытые условия перед окончательной сдачей

1. Получить явную команду владельца на production backup/rollout; локальная
   подготовка не даёт права менять production.
2. После rollout повторить affected UAT rows
   `060/065/073-076/084-086/090-095/103/134/135/145` с UI/API/DB evidence.
3. Завершить оставшиеся строки 100-сценарной матрицы, финальный reconciliation,
   DOCX и owner approval; только после этого закрывать `T7.1.2` и `INT-S6`.
4. Для выпуска installer EXE выполнить `windows_installer.iss` в доверенной
   Inno Setup среде и добавить его hash в production image ledger.

## Rollback

- приложение: вернуть предыдущие Windows/APK/AAB artifacts;
- runtime: `LESSON_COMPLETION_WORKER_ENABLED=false` останавливает новые claims;
- schema: additive `0118→0116 down` проверен на чистой БД, но production rollback
  разрешён только после backup и проверки guard/immutable evidence;
- любые уже созданные финансовые или lesson facts исправляются только штатными
  reversal/exclusion командами, без ручного удаления production history.
