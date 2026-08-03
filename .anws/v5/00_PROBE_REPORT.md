# 🔎 Probe Report — Runtime Access Gate

**Дата:** 2026-08-03  
**Режим:** targeted production probe

## Диагноз

- Windows-клиент после входа запрашивает `GET /api/access/me` через `CapabilityShellGate`.
- Старый production image `magicmusiccrm-v3-api` отвечал `404 Cannot GET /api/access/me`, поэтому клиент закономерно показывал «Не удалось проверить доступ».
- Аккаунт `magic5@gmail.com` исправен: active `director`, `accessVersion=1`, активный capability registry `20/20`.

## Исправление и проверка

- Production API переключён на проверенный image `magicmusiccrm-v4-canary:5165b62`; предыдущий image сохранён как `magicmusiccrm-v3-api:rollback-access-gate-20260803`.
- Схема production DB уже была мигрирована до `0093`; v4 flags сохранены в `shadow`, completion worker выключен.
- После переключения: `/api/health` → `200`, `/api/access/me` без токена → ожидаемый `401` вместо `404`, контейнер healthy, startup errors отсутствуют.

## Ограничение картографии

Существующая `.nexus-map` устарела и не покрывает актуальный server/runtime flow. Deep-refresh был остановлен по таймауту; вывод сделан по прямой трассировке Flutter → API controller/service → production logs/DB.
