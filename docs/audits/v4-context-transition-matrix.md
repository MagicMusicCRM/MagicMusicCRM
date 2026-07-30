# T1.3.1 — Матрица связанных переходов

Дата: 2026-07-30

## Результат

- Реестр PRD §8 содержит 53 типизированных перехода из 13 source-контекстов.
- Schedule, карточки Client/Lead, Lesson/Series, Subscription, Payment,
  Tasks, Reports, Users, Chat и Audit используют общий `EntityLink`.
- Каждый target проходит capability policy до открытия; неизвестные и
  запрещённые ссылки завершаются безопасно.
- Переход хранит filters/date/scroll/column исходного экрана и не меняет
  actor projection.
- Ad-hoc переходы из расписания карточек, задач и журнала активности заменены
  единым navigator; dashboard принимает типизированную ссылку из route query.

## Проверка

- Matrix: 53/53 перехода × 6 ролей, unknown targets = 0.
- Targeted Flutter tests: 24/24 passed.
- Targeted Flutter analyze: clean.
- `git diff --check`: clean.
