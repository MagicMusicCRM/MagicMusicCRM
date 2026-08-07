# MagicMusicCRM v7 — Final Candidate 1.5.1

**Дата:** 2026-08-07

**Версия:** `1.5.1+157`

**Решение:** APPROVED WITH OWNER-ACCEPTED HISTORY RISK

## Полная приёмка

| Gate | Результат |
|---|---|
| Backend | typecheck/build PASS; Jest 155/155 suites, 1237/1237 tests |
| Flutter | analyze PASS; 644/644 tests |
| PostgreSQL | migrations `0111..0113` down/up PASS; fault/concurrency/replay PASS |
| Access | Actor Matrix + payload leak 9/9 |
| Drift | два read-only preflight: 19 checks, findings=0, одинаковый digest `267c1cce…10090`; два reconcile: 17 invariants, unexplained=0; v7 issues=0 |
| Coverage | finance=255, lessonWrites=7, routes=22, reachable=261, workspaceProduction=2, unowned=0 |
| Security | current candidate Gitleaks 2278 files: 0; Semgrep 91 rules/2011 files: 0; npm audit: 0; Trivy filesystem/Dockerfile/runtime: 0 High/Critical |
| Windows | три owner-refinement stories PASS; пять production accounts + relogin PASS; release launch PASS |
| Android 15 | три owner-refinement stories PASS; пять production accounts + relogin PASS; signed release install/launch PASS; fatal errors=0 |

## Release artifacts

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| `build/windows/x64/runner/Release/magic_music_crm.exe` | 757760 | `6d3a505358815cb625929e88dd857f25d3e03bea0c795a56c0788810c64801e3` |
| `build/app/outputs/flutter-apk/app-release.apk` | 84606473 | `9caf3fe8c6c00d408e84a6a7231e2cc0c3da7f0dcfdc4a07175fe31838d13ff7` |
| `build/app/outputs/bundle/release/app-release.aab` | 59975962 | `80b80d0468584678ec50613399edb00c6f98f05da2d6198bfa9e1d1e3963bd5b` |

Windows binary сообщает `ProductVersion/FileVersion=1.5.1+157`. APK manifest сообщает `versionName=1.5.1`, `versionCode=157`, `minSdk=24`, `targetSdk=36`; APK Signature Scheme v2 проверена, сертификат release signer SHA-256 — `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`. AAB JAR signature проверена штатным `jarsigner -verify`; upload certificate самоподписан, как ожидается для Android upload key.

## Owner-accepted risk

History-aware scan остаётся историческим исключением: отозванность старого HolliHop credential не подтверждена, а его значение присутствует в старых Git commits. В текущих tracked/untracked candidate-файлах утечек нет. Владелец 2026-08-07 явно разрешил продолжить выпуск без history rewrite/ротации; секрет и его hash в artifacts не записываются. Предыдущий блокирующий отчёт сохранён в `docs/audits/v7-t6-regression-security-blocked.md`.

## Rollback

- Приложение: вернуть предыдущий подписанный APK/AAB/Windows bundle; database schema остаётся additive.
- База: `0113→0111 down` разрешён только при отсутствии immutable plan/correction evidence; guard намеренно блокирует разрушительный rollback.
- Worker: `LESSON_COMPLETION_WORKER_ENABLED=false` останавливает новые автоматические claims, не меняя уже проведённые факты.

**Итог:** функциональный, data-integrity, RBAC, device и release gates зелёные; `1.5.1+157` является окончательным кандидатом v7 с одним явно принятым владельцем историческим security-риском.
