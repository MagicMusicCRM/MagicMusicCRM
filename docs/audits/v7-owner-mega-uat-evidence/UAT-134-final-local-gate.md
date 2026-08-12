# UAT-134 — финальный локальный regression gate

Статус: **PARTIAL**. После закрытия всех технических `PENDING` и последних
локальных UAT-003/041/045 разрывов выполнен полный gate текущего checkout;
Docker, production и release artifacts не изменялись.

## Предыдущая найденная регрессия

Первый backend-прогон остановился на `4` тестах при `1393 PASS`:

- типизированные дополнительные поля добавили четвёртый запрос в bounded
  ClientCard read model;
- две Lead-заглушки не учитывали новый typed custom-field read и расширенный
  audit metadata.

Корневая причина ClientCard исправлена: typed value map теперь агрегируется
внутри существующего composition SQL, поэтому Manager/Teacher карточка снова
укладывается ровно в три запроса. Lead fixtures и ожидание audit metadata
приведены к действующему production-контракту. Точечный повтор:
`3/3 suites`, `41/41 tests`.

## Регрессия, найденная текущим gate

Первый полный Flutter-прогон дал `785 PASS / 1 FAIL`. После объединения API
ответственных `MagicCrmService.listResponsibleStaff` канонически возвращал
поле `name`, а picker в ClientCard продолжал читать удалённое `displayName`.
Из-за этого реальные сотрудники превращались в `Без имени`, а поиск по ФИО не
находил вариант.

Потребитель переведён на единый контракт `name`; JSON fixture также явно
возвращает `Map<String, dynamic>`, как production Dio response. Точечный файл
карточки после исправления: `11/11 PASS`.

## Финальный результат

- Flutter: `786/786 PASS`;
- backend: `175/175 suites`, `1401/1401 tests`;
- `flutter analyze`: `0 issues`;
- backend `typecheck`: `PASS`;
- backend `build`: `PASS`.
- `git diff --check`: `PASS` (только информационные CRLF warnings).

Оба финальных полных процесса и все статические команды завершились с кодом
`0`.

## Что осталось до PASS

Текущий локальный gate не заменяет clean-schema migration/runtime/security
gate нового release image, Windows/Android smoke и owner production-UAT. До
выпуска нужно выполнить эти проверки на точном артефакте и приложить hashes.
