# T8.1.3 — Read-Only Data Preflight Evidence

Проверка выполнена 2026-07-25 на изолированном PostgreSQL 16.4 с полной
актуальной схемой миграций `0001`–`0074` и обезличенным production-shaped
fixture. Fixture содержит будущие пересечения занятий, неполные ресурсы и
teacher-branch mapping, выданный абонемент без immutable snapshot,
расхождение materialized balance, неоднозначные task/entity и user/CRM
mapping.

## Результат

- Команда: `npm --prefix server run v4:preflight -- --check-read-only`.
- Запусков внешнего CLI: `2`.
- Проверок в каждом запуске: `15`.
- Findings в каждом запуске: `19` (`18` blocker, `1` warning).
- Digest обоих запусков:
  `ad5b694d8de542f2e9e30d553935c85e66acfb4d8012dd54eda88ee48be7cadf`.
- SHA-256 полного `pg_dump --data-only --column-inserts` до запусков:
  `3b736596b80a4e5bc875159acc1f88363d8bca87d64e171c933c3781cd9595a5`.
- SHA-256 того же dump после запусков:
  `3b736596b80a4e5bc875159acc1f88363d8bca87d64e171c933c3781cd9595a5`.
- PostgreSQL подтвердил `transaction_read_only=on`.
- Контрольный no-row `UPDATE` отклонён с SQLSTATE `25006`.

Counts и IDs стабильны, а данные БД до и после двух запусков
байт-в-байт эквивалентны в логическом dump. Значит, preflight restartable и
не выполняет скрытых записей.

## Артефакты

- `docs/audits/v4-data-preflight.json` — полный машинный отчёт с ID.
- `docs/audits/v4-data-preflight.md` — краткий человекочитаемый отчёт.
- `server/src/platform/v4-preflight.ts` — read-only CLI.

Артефакты намеренно не содержат имён, телефонов, email, денежных сумм,
connection strings и других секретов или прямых персональных данных.
