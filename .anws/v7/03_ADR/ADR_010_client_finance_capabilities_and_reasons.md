# ADR-010 — Client-finance capabilities и видимые причины

## Статус

Accepted

## Дата

2026-08-07

## Контекст

Admin, Manager и Director должны оформлять возвраты, покупать с чужого счёта и
сторнировать оплаты. Это не должно открыть Admin/Manager общешкольные финансы.
Причины рискованных действий должны быть видимы коллегам этих ролей.

## Факторы влияния

- существующий capability registry/resource scope является источником истины;
- права карточки клиента отделены от school-finance;
- payer и recipient могут быть разными клиентами;
- Teacher/Client не должны видеть internal reasons или технические суммы.

## Варианты

### A. Разрешить только Director

- Плюс: минимальные права.
- Минус: не соответствует операционному процессу владельца.

### B. Дать трём ролям узкие client-finance capabilities

- Плюсы: соответствует процессу и сохраняет school-finance boundary.
- Минус: Actor Matrix должна проверять больше комбинаций двух client scopes.

### C. Дать Admin/Manager полный finance role

- Плюс: меньше capability keys.
- Минус: нарушает подтверждённую иерархию и раскрывает школьные отчёты.

## Решение

Выбран B. Admin/Manager/Director получают отдельные capability keys для purchase,
cross-account payer, refund и payment reversal в доступном client scope. Для
cross-account command backend проверяет recipient и payer независимо; недоступный
client возвращает safe 404. Только Director/system_admin публикуют каталоги.

Каждая рискованная команда требует непустую человекочитаемую причину. Audit
хранит action, actor, occurredAt и before/after references. Technical history
проецирует это Admin/Manager/Director; Teacher/Client не получают запись или
скрытые поля даже при прямом API/deep-link запросе.

## Последствия

### Положительные

- операционные сотрудники выполняют работу без расширения школьных финансов;
- решения объяснимы между сменами;
- смена роли немедленно отнимает commit capability.

### Отрицательные

- UI и backend должны fail-closed на отсутствующий/устаревший capability snapshot;
- search другого плательщика ограничивается resource scope до сериализации.

### Дальнейшие действия

- добавить registry/routes/payload matrix для новых commands;
- вывести одну bounded technical history в Client Card;
- проверить пять реальных аккаунтов и отсутствие forbidden requests.

## Influence scope

- `SYS-ACCESS-SCOPE`
- `SYS-COMMERCE-INTEGRITY`
- `SYS-CRM-WORKSPACE`
- `SYS-OPERATIONS`
- `SYS-PLATFORM-QUALITY`

