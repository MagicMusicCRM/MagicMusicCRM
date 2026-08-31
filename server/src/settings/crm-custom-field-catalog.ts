import { CrmCustomFieldDefinitionDto } from "./dto/update-crm-custom-fields.dto";

export type CrmCustomFieldDefinition = Required<
  Pick<CrmCustomFieldDefinitionDto, "entity" | "key" | "label" | "type">
> &
  Pick<CrmCustomFieldDefinitionDto, "hint" | "options"> & {
    required: boolean;
  };

const REJECTED_CRM_CUSTOM_FIELD_KEYS = new Set([
  "workplace",
  "position",
  "individualPrice",
]);

const HOLLIHOP_SOURCE_OPTIONS = [
  "* брат нашего ученика",
  "* вотсап",
  "* вотсап/и др. соц сети",
  "* для брони",
  "* Заявка с сайта",
  "* Звонок",
  "* Звонок на мобильный 0387",
  "* от Наташи (МК)",
  "* Папа нашего ученика",
  "* папа нашей ученицы",
  "* продал холодильник",
  "* Родственник ученика",
  "* сайт заявка",
  "* Сразу в: Watsapp/Telegram/Instagram",
  "* через Завена, личный визит",
  "* Sokol.KIDS",
  "АВИТО",
  "Заявка с сайта MagicMusic",
  "Заявка с сайта SOKOL",
  "Заявка с сайта Sokol.KIDS",
  "Звонок на мобильный 0387 СОКОЛ",
  "Звонок на мобильный СПОРТИВНАЯ",
  "Звонок на IP-трубку",
  "Мимо проходили.",
  "не известно(старый период)",
  "от Наташи",
  "Родственник/друг ученика",
  "Сразу в: Watsapp/Telegram/Instagram + Коммент:Куда!",
  "ЯК",
];
const HOLLIHOP_DISCIPLINE_OPTIONS = ["Барабаны", "Вокал", "Гитара", "Фортепиано"];
const HOLLIHOP_LEVEL_OPTIONS = ["Без опыта", "Начальный", "Средний"];
const HOLLIHOP_CATEGORY_OPTIONS = ["Взрослые", "Дети"];
const HOLLIHOP_LEARNING_TYPE_OPTIONS = ["И.", "Общий", "С.", "Сертификат"];
const HOLLIHOP_CONTACT_RELATION_OPTIONS = [
  "бабушка",
  "даритель",
  "жена",
  "мама",
  "мать",
  "муж",
  "папа",
  "подруга",
  "сестра",
  "другое",
];

const LEGACY_DEFAULT_CRM_CUSTOM_FIELDS: CrmCustomFieldDefinition[] = [
  {
    entity: "students",
    key: "hollihopId",
    label: "ID в HolliHop",
    type: "text",
    required: false,
    hint: "Идентификатор ученика в HolliHop после миграции",
  },
  {
    entity: "students",
    key: "middleName",
    label: "Отчество",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "gender",
    label: "Пол",
    type: "select",
    required: false,
    options: ["Не указан", "Женский", "Мужской"],
  },
  {
    entity: "students",
    key: "birthday",
    label: "Дата рождения",
    type: "date",
    required: false,
  },
  {
    entity: "students",
    key: "discipline",
    label: "Направление",
    type: "select",
    required: false,
    options: HOLLIHOP_DISCIPLINE_OPTIONS,
  },
  {
    entity: "students",
    key: "level",
    label: "Уровень",
    type: "select",
    required: false,
    options: HOLLIHOP_LEVEL_OPTIONS,
  },
  {
    entity: "students",
    key: "category",
    label: "Категория обучения",
    type: "select",
    required: false,
    options: HOLLIHOP_CATEGORY_OPTIONS,
  },
  {
    entity: "students",
    key: "lessonType",
    label: "Тип обучения",
    type: "select",
    required: false,
    options: HOLLIHOP_LEARNING_TYPE_OPTIONS,
  },
  {
    entity: "students",
    key: "source",
    label: "Источник",
    type: "select",
    required: false,
    options: HOLLIHOP_SOURCE_OPTIONS,
  },
  {
    entity: "students",
    key: "requestType",
    label: "Тип обращения",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "learningGoal",
    label: "Цель обучения",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "responsible",
    label: "Ответственный",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "preferredSchedule",
    label: "Желаемое расписание",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "workplace",
    label: "Место работы/учёбы",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "position",
    label: "Должность/класс",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "contactPersonName",
    label: "Контактное лицо",
    type: "text",
    required: false,
  },
  {
    entity: "students",
    key: "contactPersonRelation",
    label: "Кем приходится",
    type: "select",
    required: false,
    options: HOLLIHOP_CONTACT_RELATION_OPTIONS,
  },
  {
    entity: "students",
    key: "contactPersonPhone",
    label: "Телефон контактного лица",
    type: "phone",
    required: false,
  },
  {
    entity: "students",
    key: "contactPersonEmail",
    label: "Email контактного лица",
    type: "email",
    required: false,
  },
  {
    entity: "students",
    key: "contractStatus",
    label: "Статус договора",
    type: "select",
    required: false,
    options: ["Нет", "Готовится", "Подписан", "Архив"],
  },
  {
    entity: "students",
    key: "cabinetStatus",
    label: "Личный кабинет",
    type: "select",
    required: false,
    options: ["Не приглашён", "Приглашён", "Активен", "Заблокирован"],
  },
  // «Чёрный список» больше не кастом-поле. ✔ Решение владельца 17.07 сделало
  // его баном: у него есть автор, причина и последствие (запрет на чаты), а
  // ставится он отдельным эндпоинтом. Миграция 0064 перенесла галочку в
  // колонку `students.blacklisted` и убрала ключ из custom_data — иначе
  // осталось бы два источника правды, и тот, в который пишут, был бы не тем,
  // который читают.
  {
    entity: "students",
    key: "noEmail",
    label: "Нет email",
    type: "boolean",
    required: false,
  },
  {
    entity: "students",
    key: "individualPrice",
    label: "Индивидуальная цена",
    type: "number",
    required: false,
  },
  {
    entity: "students",
    key: "applicationData",
    label: "Данные заявки",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "hollihopId",
    label: "ID в HolliHop",
    type: "text",
    required: false,
    hint: "Идентификатор лида в HolliHop после миграции",
  },
  {
    entity: "leads",
    key: "middleName",
    label: "Отчество",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "gender",
    label: "Пол",
    type: "select",
    required: false,
    options: ["Не указан", "Женский", "Мужской"],
  },
  {
    entity: "leads",
    key: "birthday",
    label: "Дата рождения",
    type: "date",
    required: false,
  },
  {
    // ✔ Решение владельца 17.07: возраст можно вписать руками. Если стоит дата
    // рождения, он считается из неё и сам меняется с годами — тогда это поле
    // не читается (`resolveAge`, приоритет объяснён в age.ts).
    entity: "leads",
    key: "age",
    label: "Возраст",
    type: "number",
    required: false,
    hint: "Если заполнена дата рождения, возраст считается по ней автоматически",
  },
  {
    entity: "students",
    key: "age",
    label: "Возраст",
    type: "number",
    required: false,
    hint: "Если заполнена дата рождения, возраст считается по ней автоматически",
  },
  {
    entity: "leads",
    key: "source",
    label: "Источник заявки",
    type: "select",
    required: false,
    options: HOLLIHOP_SOURCE_OPTIONS,
  },
  {
    entity: "leads",
    key: "adSource",
    label: "Рекламный источник",
    type: "select",
    required: false,
    options: HOLLIHOP_SOURCE_OPTIONS,
  },
  {
    entity: "leads",
    key: "requestType",
    label: "Тип обращения",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "learningGoal",
    label: "Цель обучения",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "discipline",
    label: "Интересующее направление",
    type: "select",
    required: false,
    options: HOLLIHOP_DISCIPLINE_OPTIONS,
  },
  {
    entity: "leads",
    key: "level",
    label: "Уровень",
    type: "select",
    required: false,
    options: HOLLIHOP_LEVEL_OPTIONS,
  },
  {
    entity: "leads",
    key: "category",
    label: "Категория обучения",
    type: "select",
    required: false,
    options: HOLLIHOP_CATEGORY_OPTIONS,
  },
  {
    entity: "leads",
    key: "lessonType",
    label: "Тип обучения",
    type: "select",
    required: false,
    options: HOLLIHOP_LEARNING_TYPE_OPTIONS,
  },
  {
    entity: "leads",
    key: "responsible",
    label: "Ответственный",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "appealAt",
    label: "Дата обращения",
    type: "date",
    required: false,
  },
  {
    // ✔ Решение владельца 16.07: дата обращения нужна и у ученика — иначе при
    // конвертации лида её некуда положить и она теряется.
    // Пустое значение не означает «неизвестно»: CrmPolicy/appeal-date.ts
    // разрешает её как HolliHop `addressDate` → дата появления записи здесь.
    entity: "students",
    key: "appealAt",
    label: "Дата обращения",
    type: "date",
    required: false,
  },
  {
    entity: "leads",
    key: "visitAt",
    label: "Дата визита",
    type: "date",
    required: false,
  },
  {
    entity: "leads",
    key: "preferredSchedule",
    label: "Желаемое расписание",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "attachedToStudent",
    label: "Связан с учеником",
    type: "boolean",
    required: false,
  },
  {
    entity: "leads",
    key: "contactPersonName",
    label: "Контактное лицо",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "contactPersonRelation",
    label: "Кем приходится",
    type: "select",
    required: false,
    options: HOLLIHOP_CONTACT_RELATION_OPTIONS,
  },
  {
    entity: "leads",
    key: "contactPersonPhone",
    label: "Телефон контактного лица",
    type: "phone",
    required: false,
  },
  {
    entity: "leads",
    key: "contactPersonEmail",
    label: "Email контактного лица",
    type: "email",
    required: false,
  },
  {
    entity: "leads",
    key: "address",
    label: "Адрес",
    type: "text",
    required: false,
  },
  {
    entity: "leads",
    key: "applicationData",
    label: "Данные заявки",
    type: "text",
    required: false,
  },
  {
    entity: "teachers",
    key: "hollihopId",
    label: "ID в HolliHop",
    type: "text",
    required: false,
    hint: "Идентификатор преподавателя в HolliHop после миграции",
  },
  {
    entity: "teachers",
    key: "middleName",
    label: "Отчество",
    type: "text",
    required: false,
  },
  {
    entity: "teachers",
    key: "birthday",
    label: "Дата рождения",
    type: "date",
    required: false,
  },
  {
    entity: "teachers",
    key: "workStatus",
    label: "Статус работы",
    type: "select",
    required: false,
    options: ["Нет", "Отпуск", "Работает"],
  },
  {
    entity: "teachers",
    key: "discipline",
    label: "Основное направление",
    type: "select",
    required: false,
    options: HOLLIHOP_DISCIPLINE_OPTIONS,
  },
  {
    entity: "teachers",
    key: "levels",
    // Free text before: every teacher spelled the same level differently, so
    // filtering by it could not work. The option list is the same one students
    // and leads already pick from.
    label: "Уровни обучения",
    type: "select",
    required: false,
    options: HOLLIHOP_LEVEL_OPTIONS,
  },
  {
    entity: "teachers",
    key: "categories",
    label: "Категории",
    type: "select",
    required: false,
    options: HOLLIHOP_CATEGORY_OPTIONS,
  },
  {
    entity: "teachers",
    key: "branches",
    label: "Филиалы",
    type: "text",
    required: false,
  },
  {
    entity: "teachers",
    key: "rating",
    label: "Рейтинг",
    type: "number",
    required: false,
  },
  {
    entity: "teachers",
    key: "description",
    label: "Описание",
    type: "text",
    required: false,
  },
  {
    entity: "teachers",
    key: "additionalParams",
    label: "Дополнительные параметры",
    type: "text",
    required: false,
  },
];

export const DEFAULT_CRM_CUSTOM_FIELDS: CrmCustomFieldDefinition[] = [
  ...LEGACY_DEFAULT_CRM_CUSTOM_FIELDS.filter(
    (field) =>
      !REJECTED_CRM_CUSTOM_FIELD_KEYS.has(field.key) &&
      !(
        field.key === "source" &&
        (field.entity === "students" || field.entity === "leads")
      ),
  ),
  {
    entity: "students",
    key: "adSource",
    label: "Рекламный источник",
    type: "select",
    required: false,
    options: HOLLIHOP_SOURCE_OPTIONS,
  },
];

export function findDefaultCrmField(
  key: string,
  entity?: CrmCustomFieldDefinition["entity"],
): CrmCustomFieldDefinition | null {
  return DEFAULT_CRM_CUSTOM_FIELDS.find(
    (field) => field.key === key && (!entity || field.entity === entity),
  ) ?? null;
}
