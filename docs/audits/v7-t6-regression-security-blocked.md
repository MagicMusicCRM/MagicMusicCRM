# v7 T6.1.1 — Regression/Security Gate (BLOCKED)

**Дата:** 2026-08-07  
**Ветка:** `codex/client-card-desktop-canvas`  
**Решение:** `BLOCKED` — выпуск и повышение версии запрещены до ротации HolliHop credential и очистки Git history.

## Что прошло

| Контур | Результат |
|---|---|
| Backend | typecheck/build PASS; full Jest 155/155 suites, 1227/1227 tests |
| Access | Actor Matrix + payload leak 2/2 suites, 9/9 tests |
| Flutter | `flutter analyze` PASS; 642/642 tests |
| Fresh DB | migrations `0001→0110`, latest `0110 down→up`, v4/v7 backfill/reconcile PASS |
| Drift | два preflight с одинаковым digest, findings=0; два reconcile/shadow pass, unexplained=0 |
| Inventories ×2 | backend routes=312, DTO fields=780; UI routes=22, reachable=260; finance=251, lesson writes=7; unknown/unowned=0 |
| Current secrets | tracked candidate Gitleaks directory scan: 0 findings |
| SAST | Semgrep OWASP Top 10: 91 rules, 1998 tracked files, 0 findings |
| Dependencies | npm audit: 0 vulnerabilities; Trivy filesystem: 0 High/Critical |
| Runtime | pinned Node `24.19.0-alpine` digest; Trivy OS scan: 0 High/Critical; Dockerfile config scan PASS |
| Repository gate | 10 PASS, 1 WARN, 0 FAIL; единственный WARN — локальный Docker daemon недоступен, компенсирован прямым Trivy image scan |

Fresh database target: `magiccrm_v7_final_gate`. Проверки не меняли production database.

## Device evidence, выполненный до release build

- Production API, Windows: пять `magic1..5@gmail.com`, restart/logout/account switch — 2/2 PASS.
- Production API, Android 15 API 35: те же пять аккаунтов и relogin — 2/2 PASS.
- V7 Client Workspace: Windows 3/3, Android 3/3.
- Recurring plans: Windows 1/1, Android 1/1.
- Найденный Android RenderFlex overflow при закрытии payment sheet во время IME-анимации исправлен в общем пути закрытия; повторный device run зелёный.

Эти прогоны являются диагностическим evidence. `T6.1.2` не закрывается, потому что по dependency graph она начинается только после зелёной `T6.1.1`.

## Блокирующая находка

History-aware Gitleaks gate остаётся красным. Скан 735 коммитов обнаруживает старые артефакты и ложноположительные client identifiers, но среди них есть реальный HolliHop credential:

- 23 находки в 3 коммитах и 23 удалённых/архивных файлах содержат один и тот же секрет;
- секрет byte-identical локально настроенному `HOLLIHOP_AUTH_KEY`;
- значение секрета и его hash намеренно не записаны в этот документ или tracked artifacts.

Удаления файлов в текущем дереве недостаточно: секрет остаётся доступен через Git history. Allowlist для него запрещён.

## Что требуется для продолжения

1. Владелец ротирует HolliHop API key у провайдера и отзывает старое значение.
2. Новый ключ передаётся только через production/local secret environment вне Git.
3. Владелец явно разрешает coordinated Git history rewrite и force-push; перед операцией все участники предупреждаются о необходимости fresh clone/rebase.
4. После rewrite повторяются history-aware Gitleaks, полный regression/security gate, Windows/Android release build, signature/install/launch, hashes и final smoke.

## Зафиксированные hardening-изменения

- `js-yaml`/`uuid` dependency overrides закрывают npm advisories.
- Runtime image закреплён по проверенному digest; runtime не содержит npm/npx.
- Release gate использует repository `.gitleaks.toml`, исключает только локальные ignored `.env` из Trivy filesystem scan и отдельно проверяет их tracked/unignored статус.
- Firebase allowlist требует одновременно точный `AIza…` формат и точный client-config path; остальные типы секретов в этих файлах не освобождены.
- Локальный dashboard token удалён из onboarding.
- PostgreSQL fixture cleanup учитывает v7 aggregate/transition tables.

## Release state

- `T6.1.1`: OPEN / BLOCKED.
- `T6.1.2`, `T6.1.3`, `INT-S5`: OPEN по зависимости.
- Версия остаётся `1.2.3+156`.
- Финальные Windows/APK/AAB artifacts и release hashes не формировались.
- Решение `APPROVED` не выдавалось.
