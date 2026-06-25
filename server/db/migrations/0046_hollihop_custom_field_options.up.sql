with option_patches(entity, key, field_type, options) as (
  values
    ('students', 'source', 'select', '["* брат нашего ученика","* вотсап","* вотсап/и др. соц сети","* для брони","* Заявка с сайта","* Звонок","* Звонок на мобильный 0387","* от Наташи (МК)","* Папа нашего ученика","* папа нашей ученицы","* продал холодильник","* Родственник ученика","* сайт заявка","* Сразу в: Watsapp/Telegram/Instagram","* через Завена, личный визит","* Sokol.KIDS","АВИТО","Заявка с сайта MagicMusic","Заявка с сайта SOKOL","Заявка с сайта Sokol.KIDS","Звонок на мобильный 0387 СОКОЛ","Звонок на мобильный СПОРТИВНАЯ","Звонок на IP-трубку","Мимо проходили.","не известно(старый период)","от Наташи","Родственник/друг ученика","Сразу в: Watsapp/Telegram/Instagram + Коммент:Куда!","ЯК"]'::jsonb),
    ('students', 'discipline', 'select', '["Барабаны","Вокал","Гитара","Фортепиано"]'::jsonb),
    ('students', 'level', 'select', '["Без опыта","Начальный","Средний"]'::jsonb),
    ('students', 'category', 'select', '["Взрослые","Дети"]'::jsonb),
    ('students', 'lessonType', 'select', '["И.","Общий","С.","Сертификат"]'::jsonb),
    ('students', 'contactPersonRelation', 'select', '["бабушка","даритель","жена","мама","мать","муж","папа","подруга","сестра","другое"]'::jsonb),
    ('leads', 'source', 'select', '["* брат нашего ученика","* вотсап","* вотсап/и др. соц сети","* для брони","* Заявка с сайта","* Звонок","* Звонок на мобильный 0387","* от Наташи (МК)","* Папа нашего ученика","* папа нашей ученицы","* продал холодильник","* Родственник ученика","* сайт заявка","* Сразу в: Watsapp/Telegram/Instagram","* через Завена, личный визит","* Sokol.KIDS","АВИТО","Заявка с сайта MagicMusic","Заявка с сайта SOKOL","Заявка с сайта Sokol.KIDS","Звонок на мобильный 0387 СОКОЛ","Звонок на мобильный СПОРТИВНАЯ","Звонок на IP-трубку","Мимо проходили.","не известно(старый период)","от Наташи","Родственник/друг ученика","Сразу в: Watsapp/Telegram/Instagram + Коммент:Куда!","ЯК"]'::jsonb),
    ('leads', 'adSource', 'select', '["* брат нашего ученика","* вотсап","* вотсап/и др. соц сети","* для брони","* Заявка с сайта","* Звонок","* Звонок на мобильный 0387","* от Наташи (МК)","* Папа нашего ученика","* папа нашей ученицы","* продал холодильник","* Родственник ученика","* сайт заявка","* Сразу в: Watsapp/Telegram/Instagram","* через Завена, личный визит","* Sokol.KIDS","АВИТО","Заявка с сайта MagicMusic","Заявка с сайта SOKOL","Заявка с сайта Sokol.KIDS","Звонок на мобильный 0387 СОКОЛ","Звонок на мобильный СПОРТИВНАЯ","Звонок на IP-трубку","Мимо проходили.","не известно(старый период)","от Наташи","Родственник/друг ученика","Сразу в: Watsapp/Telegram/Instagram + Коммент:Куда!","ЯК"]'::jsonb),
    ('leads', 'discipline', 'select', '["Барабаны","Вокал","Гитара","Фортепиано"]'::jsonb),
    ('leads', 'level', 'select', '["Без опыта","Начальный","Средний"]'::jsonb),
    ('leads', 'category', 'select', '["Взрослые","Дети"]'::jsonb),
    ('leads', 'lessonType', 'select', '["И.","Общий","С.","Сертификат"]'::jsonb),
    ('leads', 'contactPersonRelation', 'select', '["бабушка","даритель","жена","мама","мать","муж","папа","подруга","сестра","другое"]'::jsonb),
    ('teachers', 'discipline', 'select', '["Барабаны","Вокал","Гитара","Фортепиано"]'::jsonb)
),
current_setting as (
  select coalesce(
    (select value from app.system_settings where key = 'crm_custom_fields'),
    '[]'::jsonb
  ) as value
),
updated as (
  select jsonb_agg(
    case
      when p.entity is null then field.item
      else field.item || jsonb_build_object('type', p.field_type, 'options', p.options)
    end
    order by field.ord
  ) as value
  from current_setting,
    jsonb_array_elements(current_setting.value) with ordinality as field(item, ord)
  left join option_patches p
    on p.entity = field.item->>'entity'
   and p.key = field.item->>'key'
)
insert into app.system_settings (key, value, updated_by)
select 'crm_custom_fields', coalesce(value, '[]'::jsonb), null
from updated
on conflict (key) do update
set value = excluded.value,
  updated_at = now();
