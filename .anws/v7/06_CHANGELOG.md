# Журнал изменений — .anws v7

> Новые функции и крупные решения фиксируются через `/genesis`; локальные
> уточнения активной версии — через `/change`.

## Формат записей

- **[ADD]** Новая часть версии
- **[CHANGE]** Уточнение принятого требования
- **[FIX]** Исправление документации
- **[REMOVE]** Удаление устаревшей части

---

## 2026-08-07 — Инициализация

- **[CHANGE]** Владелец подтвердил PRD v7 и разрешил полное проектирование,
  реализацию и проверку версии.
- **[ADD]** Создана `.anws/v7` на базе принятой v6.
- **[ADD]** В область версии включены покупка и отмена абонемента, payer wallet,
  настраиваемые типы списаний/оплаты преподавателя, переносы, постоянные
  расписания и Client Card actions/note.
- **[CHANGE]** Отмена абонемента исключает исходную продажу и сторно из обычной
  статистики, сохраняя обе операции в защищённом техническом аудите.
- **[CHANGE]** Автоматическая связь типа списания с оплатой преподавателю
  отклонена владельцем: директор настраивает оба каталога, а сотрудник выбирает
  оба значения вручную для каждого занятия.
- **[CHANGE]** Последующее уточнение владельца: автоматический *выбор* по-прежнему
  запрещён, но сотрудник обязан выбрать оба значения до назначения занятия;
  после его окончания worker применяет зафиксированное решение атомарно.
- **[ADD]** Неуспешное автопроведение создаёт `Требует проверки` без частичных
  фактов; pre-start edit меняет reservation, post-terminal correction создаёт
  append-only reversal/replacement одной транзакцией.
- **[ADD]** Постоянное расписание получает repeatable rows и authoritative
  per-date constraints preview с видимыми teacher/client/room/branch причинами.
- **[CHANGE]** Внутренние переходы выполняются по entity text: desktop всегда
  открывает новую workspace tab, compact — канонический route stack. Client Card
  остаётся long canvas на desktop и использует тематические tabs на телефонах.
- **[CHANGE]** Финальный номер версии зафиксирован как `1.5.1`, но устанавливается
  только после green full regression и реальных Windows/Android проверок.
- **[CHANGE]** Покупка абонемента блокируется целиком при недостатке средств на
  выбранном личном счёте; отрицательный баланс пока не разрешён.
- **[CHANGE]** При рассрочке вся итоговая стоимость резервируется сразу как
  коммерческое обязательство, не как уже существующие деньги личного счёта;
  все часы выдаются сразу, а подтверждённые платежи закрывают обязательство
  частями.
- **[ADD]** Введён единый lifecycle оплаты: `Не оплачен` (долг), `Проведен,
  ожидает подтверждения` (требует проверки сотрудником) и `Оплачен`
  (подтверждённый денежный факт). Основание полного резерва и влияние pending
  на доступный баланс вынесены в явное уточнение.
- **[CHANGE]** Владелец принял все рекомендованные правила: рассрочка резервирует
  полную стоимость как обязательство, pending не увеличивает доступный баланс,
  paid неизменяем и исправляется сторно, а типы/расписания используют предложенные
  lifecycle и preview.
- **[CHANGE]** Администратор наравне с Управляющим и Директором может оформлять
  возврат, выбирать чужой личный счёт и удалять оплату. Каждое действие требует
  причины; удаление является сторно, исключает пару из обычной статистики и
  остаётся видимым этим трём ролям в техническом журнале.
- **[ADD]** ADR-007 сохраняет существующий Flutter/NestJS/PostgreSQL runtime:
  v7 использует текущие транзакции, idempotency, audit/outbox и capabilities без
  нового сервиса, event-store или зависимости.
- **[ADD]** Architecture Overview выделяет `SYS-COMMERCE-INTEGRITY` как одного
  владельца wallet/subscription/payment/settlement/accrual и соединяет его с
  Schedule одним финансовым port в общей PostgreSQL-транзакции.
- **[ADD]** ADR-008 фиксирует append-only payment lifecycle/reversal/exclusion;
  ADR-009 — единый атомарный перенос; ADR-010 — узкие client-finance capabilities
  Admin/Manager/Director и staff-visible reasons без school-finance expansion.
- **[ADD]** Детальный дизайн v7 покрывает Commerce Integrity, Schedule,
  Client Card и Access/Audit: additive data shape, API/lifecycle, adaptive UI,
  concurrency, report predicates и executable gates.
- **[FIX]** Challenge исправил refund cap для one-time wallet purchase, защитил
  commerce segments mixed config publish и заменил auto financial completion на
  `settlement_pending`. Обязательный finance-query inventory оставлен gate.
- **[ADD]** Blueprint разбивает v7 на 24 implementation tasks и 6 INT milestones
  по шести волнам: data, commerce, lesson integrity, plans, Client Card и release.
- **[FIX]** Task review разделил две перегруженные P0-задачи; итоговый план
  покрывает 11/11 требований и 11/11 stories, открытых Critical/High нет.
- **[ADD]** Owner refinement реализовал entity-text navigation, client-focused
  Month/Week/Day, multi-row recurring plans и обязательный planned settlement.
- **[ADD]** Миграции `0111..0113` добавили versioned plan/revisions, automatic
  completion worker и append-only correction с effective reporting views.
- **[FIX]** Full regression устранил residue correction tests, совместимость
  старого migration rollback с effective views и time-dependent reversal test.
- **[CHANGE]** После full/device/security gates выпущен final candidate
  `1.5.1+157`; исторический HolliHop credential принят владельцем как явный
  риск без добавления секрета в текущий candidate.

## 2026-08-08 — Owner production mega-UAT

- **[CHANGE]** Владелец выбрал непосредственный production-прогон с UAT-
  префиксом и принял сохранение append-only тестового следа в технической истории.
- **[CHANGE]** Администратор получает общую branch-scoped доску задач с правом
  чтения/закрытия без create/edit; стартовые фильтры `Мои задачи` и `Сегодня`
  включены, остальные фильтры доступны вручную.
- **[CHANGE]** Client/Teacher принимаются через Android emulator; Admin/Manager/
  Director — через Windows Release.
- **[ADD]** Тестовый филиал: `Оборонная 30`, Europe/Moscow, Пн–Сб 09:00–21:00,
  воскресенье закрыто.
- **[ADD]** В S6 добавлены T7.1.1, T7.1.2 и INT-S6 с полным runbook UI/API/DB
  evidence и stop-критериями финансовой/ролевой целостности.
- **[CHANGE]** Production-аудит конструкторов добавил T7.1.3: Teacher/Staff/Group
  требуют обязательные филиальные связи и canonical filtered references; Staff
  business-role отделена от последующих access-role изменений пользователя.
- **[CHANGE]** Владелец уточнил Staff create: обязательные email и пароль сразу
  создают активный аккаунт приложения; user/profile/staff/branch/link записываются
  атомарно, выбранная роль задаёт начальный доступ, пароль хранится только как
  hash существующего PasswordService.
- **[CHANGE]** Тот же account-first контракт применён к Teacher: обязательные
  email/пароль создают роль `teacher`, профиль, CRM-сущность, филиальные и
  дисциплинарные связи одной операцией; запись сразу видна в «Пользователях».
- **[ADD]** Для старых Teacher/Staff без доступа добавлена атомарная выдача
  email/пароля с повышением технического профиля либо созданием недостающей
  identity; повторная выдача второго аккаунта запрещена.
- **[CHANGE]** Аудитории управляются внутри карточки филиала; standalone-раздел
  удаляется. Legacy inline-варианты custom fields удаляются в пользу единого
  раздела «Варианты для полей».
