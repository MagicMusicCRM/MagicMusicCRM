# Исправления тестовой инфраструктуры — проверено 10 сентября 2026

**Полные свежие проверки прошли: Flutter 1765 PASS; сервер 315 suites / 4115 PASS, 0 skipped; harness 7 PASS.**

## Что теперь работает

1. `npm --prefix server run test:full` воспроизводит изоляцию из release runner без файлов из `dist/release218`: чистый мигрированный шаблон, существующий backfill и отдельная БД на каждый suite.
2. Полный gate отклоняет skipped/pending/todo, неполный набор, изменение исходников во время запуска и ошибку очистки. Настоящий Jest с намеренными skip/only проверен отдельными harness fixtures: его код 0 больше не превращается в PASS gate.
3. Адрес тестового PostgreSQL отделён от application env. URL с внешним host, другой служебной БД или query override отклоняется. Очистка ограничена уникальной identity запуска. Отдельной SQL-проверкой подтверждено: базы трёх выполненных изолированных запусков отсутствуют.
4. Tooltip guard проверяет собственный аргумент конкретной кнопки через Dart AST. Именованные, const/new и prefixed конструкторы проверяются; чужая подпись, комментарий, строка, пустое/null значение не дают ложный PASS. Статические style factories не считаются кнопками.
5. API contract scripts используют тот же runner; explicit offline выборка блокирует `pg.Pool`/`pg.Client`. Руководство описывает реальные границы unit, fake UI, embedded SQL, PostgreSQL и real device journeys. Summary показывает случаи по файлам, включая концентрацию в preview codec.

## Свежие результаты

| Проверка | Результат |
| --- | --- |
| `npm --prefix server run test:full -- --coverage` | 7 harness PASS; 315 серверных suites / 4115 PASS; 0 skipped; exit 0; Jest 819 секунд |
| `flutter test --no-pub --coverage --coverage-path outputs/test-audit-2026-09-10/flutter-current.lcov --reporter expanded` | 1765 PASS; exit 0; 330 секунд |
| API contracts `-Offline` / expense contracts с PostgreSQL | 20 / 13 серверных PASS, соответствующие Flutter wire-проверки прошли |
| TypeScript typecheck / Dart analyze изменённых тестов | PASS / No issues found |
| Проверка diff, пробелов, очистки БД и индекса | PASS; временных БД проверенных запусков 0; RepoWise index-only завершён |

Серверный source SHA-256 полного прогона: `654c4468d3f1cc7327e84dd0329f654bf4090b255375a5f86d2ffd54dd169330`.
После прогона повторно подтверждено совпадение с серверными входными файлами на тот момент.
При подготовке коммита fingerprint научен учитывать необязательный `server/scripts`
только при наличии, а policy fixtures переведены на уже отслеживаемые Git тесты.
После этих правок: harness 7 PASS; offline `crm.policy.spec.ts` 36 PASS, 0 skipped
(run `9e01db8845f6aff6`). Полный набор после этих двух правок повторно не запускался.
Полные результаты выше относятся к проверенной рабочей копии, включая изменения,
существовавшие до аудита, а не к отдельному коммиту инфраструктуры на чистом HEAD.
Границы сохранения описаны в [save-scope.md](save-scope.md).
В проверенных исходниках приложения и финансовой логике изменений этой задачей нет.
Production/deploy не выполнялись. Существующие незакоммиченные изменения сохранены.

## Coverage и границы результата

Flutter LCOV содержит 431 файл: 39985 покрытых строк из 51414 учтённых.
Данные ветвей не собирались; их отсутствие не означает нулевое покрытие ветвей.
Серверный LCOV содержит 561 файл: 23416/28076 строк и 16792/26980 ветвей.
Это статистика данных конкретных запусков, не оценка качества всех assertions
и не подтверждение всех пользовательских сценариев. Автоматические golden
сравнения изображений в рамках этой задачи не добавлялись.

Регрессии tooltip сначала упали на старом алгоритме: 11 ошибок в 16 случаях.
После AST-исправления и отдельной проверки static factory все 19 тестов
guard + production inventory + semantics прошли. Полный Flutter-набор тоже прошёл.
Диагностические тесты skip/only находятся только в `server/test-tools/fixtures`,
вне обычного Jest inventory `server/src`; они проверяют механизм отказа gate.

Режим watch, обходивший изоляцию, заменён документированным повторным запуском
выбранных файлов. Новый runner не поддерживает watch и произвольные Jest flags;
штатные варианты перечислены в руководстве. Для unit/wire выборки без локальной
БД требуется явный `--no-database --runTestsByPath ...`.

## Где смотреть

- [Руководство по запуску и матрица критичных инвариантов](</C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/engineering/TESTING.md>).
- [Итог полного серверного gate](</C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server/coverage/test-runs/c1dc91bea4d45d10/summary.json>).
- [Серверный HTML coverage](</C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server/coverage/test-runs/c1dc91bea4d45d10/coverage/lcov-report/index.html>).
- [Свежий Flutter LCOV](</C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/outputs/test-audit-2026-09-10/flutter-current.lcov>).
- [Подтверждение очистки тестовых БД](</C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/outputs/test-audit-2026-09-10/cleanup-verified.json>).
