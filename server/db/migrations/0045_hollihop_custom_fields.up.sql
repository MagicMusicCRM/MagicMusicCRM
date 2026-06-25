with defaults(value) as (
  values (
    '[
      {"entity":"students","key":"hollihopId","label":"ID в HolliHop","type":"text","required":false,"hint":"Идентификатор ученика в HolliHop после миграции"},
      {"entity":"students","key":"middleName","label":"Отчество","type":"text","required":false},
      {"entity":"students","key":"gender","label":"Пол","type":"select","required":false,"options":["Не указан","Женский","Мужской"]},
      {"entity":"students","key":"birthday","label":"Дата рождения","type":"date","required":false},
      {"entity":"students","key":"discipline","label":"Направление","type":"select","required":false,"options":["Вокал","Фортепиано","Гитара","Барабаны"]},
      {"entity":"students","key":"level","label":"Уровень","type":"select","required":false,"options":["Начинающий","Средний","Продвинутый"]},
      {"entity":"students","key":"category","label":"Категория обучения","type":"text","required":false},
      {"entity":"students","key":"lessonType","label":"Тип обучения","type":"select","required":false,"options":["Индивидуально","Группа","Пробное","Корпоративное"]},
      {"entity":"students","key":"source","label":"Источник","type":"select","required":false,"options":["Сайт","Рекомендация","Соцсети","HolliHop","Другое"]},
      {"entity":"students","key":"requestType","label":"Тип обращения","type":"text","required":false},
      {"entity":"students","key":"learningGoal","label":"Цель обучения","type":"text","required":false},
      {"entity":"students","key":"responsible","label":"Ответственный","type":"text","required":false},
      {"entity":"students","key":"preferredSchedule","label":"Желаемое расписание","type":"text","required":false},
      {"entity":"students","key":"workplace","label":"Место работы/учёбы","type":"text","required":false},
      {"entity":"students","key":"position","label":"Должность/класс","type":"text","required":false},
      {"entity":"students","key":"contactPersonName","label":"Контактное лицо","type":"text","required":false},
      {"entity":"students","key":"contactPersonRelation","label":"Кем приходится","type":"text","required":false},
      {"entity":"students","key":"contactPersonPhone","label":"Телефон контактного лица","type":"phone","required":false},
      {"entity":"students","key":"contactPersonEmail","label":"Email контактного лица","type":"email","required":false},
      {"entity":"students","key":"contractStatus","label":"Статус договора","type":"select","required":false,"options":["Нет","Готовится","Подписан","Архив"]},
      {"entity":"students","key":"cabinetStatus","label":"Личный кабинет","type":"select","required":false,"options":["Не приглашён","Приглашён","Активен","Заблокирован"]},
      {"entity":"students","key":"blacklisted","label":"Чёрный список","type":"boolean","required":false},
      {"entity":"students","key":"noEmail","label":"Нет email","type":"boolean","required":false},
      {"entity":"students","key":"individualPrice","label":"Индивидуальная цена","type":"number","required":false},
      {"entity":"students","key":"applicationData","label":"Данные заявки","type":"text","required":false},
      {"entity":"leads","key":"hollihopId","label":"ID в HolliHop","type":"text","required":false,"hint":"Идентификатор лида в HolliHop после миграции"},
      {"entity":"leads","key":"middleName","label":"Отчество","type":"text","required":false},
      {"entity":"leads","key":"gender","label":"Пол","type":"select","required":false,"options":["Не указан","Женский","Мужской"]},
      {"entity":"leads","key":"birthday","label":"Дата рождения","type":"date","required":false},
      {"entity":"leads","key":"source","label":"Источник заявки","type":"select","required":false,"options":["Сайт","Рекомендация","Соцсети","HolliHop","Другое"]},
      {"entity":"leads","key":"adSource","label":"Рекламный источник","type":"text","required":false},
      {"entity":"leads","key":"requestType","label":"Тип обращения","type":"text","required":false},
      {"entity":"leads","key":"learningGoal","label":"Цель обучения","type":"text","required":false},
      {"entity":"leads","key":"discipline","label":"Интересующее направление","type":"select","required":false,"options":["Вокал","Фортепиано","Гитара","Барабаны"]},
      {"entity":"leads","key":"level","label":"Уровень","type":"select","required":false,"options":["Начинающий","Средний","Продвинутый"]},
      {"entity":"leads","key":"category","label":"Категория обучения","type":"text","required":false},
      {"entity":"leads","key":"lessonType","label":"Тип обучения","type":"select","required":false,"options":["Индивидуально","Группа","Пробное","Корпоративное"]},
      {"entity":"leads","key":"responsible","label":"Ответственный","type":"text","required":false},
      {"entity":"leads","key":"appealAt","label":"Дата обращения","type":"date","required":false},
      {"entity":"leads","key":"visitAt","label":"Дата визита","type":"date","required":false},
      {"entity":"leads","key":"preferredSchedule","label":"Желаемое расписание","type":"text","required":false},
      {"entity":"leads","key":"attachedToStudent","label":"Связан с учеником","type":"boolean","required":false},
      {"entity":"leads","key":"contactPersonName","label":"Контактное лицо","type":"text","required":false},
      {"entity":"leads","key":"contactPersonRelation","label":"Кем приходится","type":"text","required":false},
      {"entity":"leads","key":"contactPersonPhone","label":"Телефон контактного лица","type":"phone","required":false},
      {"entity":"leads","key":"contactPersonEmail","label":"Email контактного лица","type":"email","required":false},
      {"entity":"leads","key":"address","label":"Адрес","type":"text","required":false},
      {"entity":"leads","key":"applicationData","label":"Данные заявки","type":"text","required":false},
      {"entity":"teachers","key":"hollihopId","label":"ID в HolliHop","type":"text","required":false,"hint":"Идентификатор преподавателя в HolliHop после миграции"},
      {"entity":"teachers","key":"middleName","label":"Отчество","type":"text","required":false},
      {"entity":"teachers","key":"birthday","label":"Дата рождения","type":"date","required":false},
      {"entity":"teachers","key":"workStatus","label":"Статус работы","type":"select","required":false,"options":["Нет","Отпуск","Работает"]},
      {"entity":"teachers","key":"discipline","label":"Основное направление","type":"select","required":false,"options":["Вокал","Фортепиано","Гитара","Барабаны"]},
      {"entity":"teachers","key":"levels","label":"Уровни","type":"text","required":false},
      {"entity":"teachers","key":"categories","label":"Категории","type":"text","required":false},
      {"entity":"teachers","key":"branches","label":"Филиалы","type":"text","required":false},
      {"entity":"teachers","key":"rating","label":"Рейтинг","type":"number","required":false},
      {"entity":"teachers","key":"description","label":"Описание","type":"text","required":false},
      {"entity":"teachers","key":"additionalParams","label":"Дополнительные параметры","type":"text","required":false}
    ]'::jsonb
  )
),
current_setting as (
  select coalesce(
    (select value from app.system_settings where key = 'crm_custom_fields'),
    '[]'::jsonb
  ) as value
),
merged as (
  select jsonb_agg(item order by ord) as value
  from (
    select existing.item, existing.ord
    from current_setting,
      jsonb_array_elements(current_setting.value) with ordinality as existing(item, ord)
    union all
    select default_field.item, default_field.ord + 10000
    from defaults,
      jsonb_array_elements(defaults.value) with ordinality as default_field(item, ord)
    where not exists (
      select 1
      from current_setting,
        jsonb_array_elements(current_setting.value) as existing(item)
      where existing.item->>'entity' = default_field.item->>'entity'
        and existing.item->>'key' = default_field.item->>'key'
    )
  ) all_fields
)
insert into app.system_settings (key, value, updated_by)
select 'crm_custom_fields', coalesce(value, '[]'::jsonb), null
from merged
on conflict (key) do update
set value = excluded.value,
  updated_at = now();
