import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  ActorContext,
  isAdminRole,
} from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  CRM_CUSTOM_FIELD_ENTITIES,
  CRM_CUSTOM_FIELD_TYPES,
  CrmCustomFieldDefinitionDto,
} from "./dto/update-crm-custom-fields.dto";

interface SettingRow {
  key: string;
  value_text: string | null;
  updated_at: Date | string;
}

interface JsonSettingRow {
  key: string;
  value: unknown;
  updated_at: Date | string;
}

type CrmCustomFieldDefinition = Required<
  Pick<CrmCustomFieldDefinitionDto, "entity" | "key" | "label" | "type">
> &
  Pick<CrmCustomFieldDefinitionDto, "hint" | "options"> & {
    required: boolean;
  };

const ADMIN_CHAT_AVATAR_KEY = "admin_chat_avatar_url";
const CRM_CUSTOM_FIELDS_KEY = "crm_custom_fields";

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

const DEFAULT_CRM_CUSTOM_FIELDS: CrmCustomFieldDefinition[] = [
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
  {
    entity: "students",
    key: "blacklisted",
    label: "Чёрный список",
    type: "boolean",
    required: false,
  },
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

@Injectable()
export class SettingsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeBus,
  ) {}

  async getAdminChatAvatar(_actor: ActorContext) {
    const result = await this.database.query<SettingRow>(
      `
        select key, value #>> '{}' as value_text, updated_at
        from app.system_settings
        where key = $1
        limit 1
      `,
      [ADMIN_CHAT_AVATAR_KEY],
    );
    const row = result.rows[0];
    return {
      key: ADMIN_CHAT_AVATAR_KEY,
      value: row?.value_text ?? null,
      updatedAt: row?.updated_at ?? null,
    };
  }

  async updateAdminChatAvatar(actor: ActorContext, url?: string | null) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может менять глобальные настройки.",
      );
    }
    const normalized = this.normalizeAdminAvatarUrl(url);
    const result = await this.database.query<SettingRow>(
      `
        insert into app.system_settings (key, value, updated_by)
        values ($1, $2::jsonb, $3)
        on conflict (key) do update
        set value = excluded.value,
          updated_by = excluded.updated_by,
          updated_at = now()
        returning key, value #>> '{}' as value_text, updated_at
      `,
      [
        ADMIN_CHAT_AVATAR_KEY,
        normalized === null ? "null" : JSON.stringify(normalized),
        actor.userId,
      ],
    );
    const row = result.rows[0];
    await this.audit.record({
      actor,
      action: "settings.admin_chat_avatar_updated",
      entityType: "setting",
      entityId: ADMIN_CHAT_AVATAR_KEY,
      metadata: { cleared: normalized === null },
    });
    // Shared UI element visible to every role — broadcast so open messengers
    // refetch the avatar without a manual refresh.
    this.realtime.emitSettingChanged(ADMIN_CHAT_AVATAR_KEY);
    return {
      key: ADMIN_CHAT_AVATAR_KEY,
      value: row?.value_text ?? null,
      updatedAt: row?.updated_at ?? null,
    };
  }

  async getCrmCustomFields(_actor: ActorContext) {
    const result = await this.database.query<JsonSettingRow>(
      `
        select key, value, updated_at
        from app.system_settings
        where key = $1
        limit 1
      `,
      [CRM_CUSTOM_FIELDS_KEY],
    );
    const row = result.rows[0];
    return {
      key: CRM_CUSTOM_FIELDS_KEY,
      fields: this.normalizeCustomFields(
        Array.isArray(row?.value) ? row.value : DEFAULT_CRM_CUSTOM_FIELDS,
      ),
      updatedAt: row?.updated_at ?? null,
    };
  }

  async updateCrmCustomFields(
    actor: ActorContext,
    fields: CrmCustomFieldDefinitionDto[],
  ) {
    if (!isAdminRole(actor.role)) {
      throw new ForbiddenException(
        "Только администратор может менять глобальные настройки.",
      );
    }
    const normalized = this.normalizeCustomFields(fields);
    const result = await this.database.query<JsonSettingRow>(
      `
        insert into app.system_settings (key, value, updated_by)
        values ($1, $2::jsonb, $3)
        on conflict (key) do update
        set value = excluded.value,
          updated_by = excluded.updated_by,
          updated_at = now()
        returning key, value, updated_at
      `,
      [CRM_CUSTOM_FIELDS_KEY, JSON.stringify(normalized), actor.userId],
    );
    const row = result.rows[0];
    await this.audit.record({
      actor,
      action: "settings.crm_custom_fields_updated",
      entityType: "setting",
      entityId: CRM_CUSTOM_FIELDS_KEY,
      metadata: { fieldCount: normalized.length },
    });
    // CRM custom fields affect staff CRM forms — scope the hint to the crm room.
    this.realtime.emitCrmChanged({
      entity: "setting",
      action: "updated",
      id: CRM_CUSTOM_FIELDS_KEY,
    });
    return {
      key: CRM_CUSTOM_FIELDS_KEY,
      fields: this.normalizeCustomFields(row?.value),
      updatedAt: row?.updated_at ?? null,
    };
  }

  private normalizeAdminAvatarUrl(url?: string | null): string | null {
    const value = url?.trim();
    if (!value) return null;
    if (value.startsWith("storage://avatars/")) return value;
    try {
      const parsed = new URL(value);
      if (parsed.protocol === "https:") return value;
    } catch {
      // Fall through to the public validation error.
    }
    throw new BadRequestException("Некорректная ссылка на аватар.");
  }

  private normalizeCustomFields(value: unknown): CrmCustomFieldDefinition[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException("Некорректная схема дополнительных полей.");
    }

    const seen = new Set<string>();
    return value.map((field) => {
      if (!field || typeof field !== "object" || Array.isArray(field)) {
        throw new BadRequestException(
          "Некорректная схема дополнительных полей.",
        );
      }
      const raw = field as Record<string, unknown>;
      const entity = this.normalizeEnumValue(
        raw.entity,
        CRM_CUSTOM_FIELD_ENTITIES,
        "Некорректная сущность дополнительного поля.",
      );
      const type = this.normalizeEnumValue(
        raw.type,
        CRM_CUSTOM_FIELD_TYPES,
        "Некорректный тип дополнительного поля.",
      );
      const key = this.normalizeFieldKey(raw.key);
      const label = this.normalizeText(
        raw.label,
        80,
        "Название дополнительного поля обязательно.",
      );
      const duplicateKey = `${entity}:${key}`;
      if (seen.has(duplicateKey)) {
        throw new BadRequestException(
          "Ключ дополнительного поля должен быть уникальным внутри сущности.",
        );
      }
      seen.add(duplicateKey);

      const normalized: CrmCustomFieldDefinition = {
        entity,
        key,
        label,
        type,
        required: raw.required === true,
      };
      const hint = this.normalizeOptionalText(raw.hint, 160);
      if (hint) normalized.hint = hint;
      if (type === "select") {
        normalized.options = this.normalizeOptions(raw.options);
      }
      return normalized;
    });
  }

  private normalizeFieldKey(value: unknown): string {
    const key = this.normalizeText(
      value,
      64,
      "Ключ дополнительного поля обязателен.",
    );
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(key)) {
      throw new BadRequestException(
        "Ключ поля должен начинаться с латинской буквы и содержать только латиницу, цифры и подчёркивание.",
      );
    }
    return key;
  }

  private normalizeText(
    value: unknown,
    maxLength: number,
    errorMessage: string,
  ): string {
    if (typeof value !== "string") {
      throw new BadRequestException(errorMessage);
    }
    const text = value.trim();
    if (!text || text.length > maxLength) {
      throw new BadRequestException(errorMessage);
    }
    return text;
  }

  private normalizeOptionalText(
    value: unknown,
    maxLength: number,
  ): string | undefined {
    if (value === undefined || value === null) return undefined;
    if (typeof value !== "string") {
      throw new BadRequestException(
        "Некорректная подсказка дополнительного поля.",
      );
    }
    const text = value.trim();
    if (!text) return undefined;
    if (text.length > maxLength) {
      throw new BadRequestException(
        "Подсказка дополнительного поля слишком длинная.",
      );
    }
    return text;
  }

  private normalizeOptions(value: unknown): string[] {
    if (!Array.isArray(value)) {
      throw new BadRequestException(
        "Для поля со списком нужны варианты выбора.",
      );
    }
    const options = [
      ...new Set(
        value.map((item) =>
          this.normalizeText(
            item,
            80,
            "Вариант выбора дополнительного поля обязателен.",
          ),
        ),
      ),
    ];
    if (options.length === 0) {
      throw new BadRequestException(
        "Для поля со списком нужен хотя бы один вариант выбора.",
      );
    }
    return options;
  }

  private normalizeEnumValue<T extends readonly string[]>(
    value: unknown,
    allowed: T,
    errorMessage: string,
  ): T[number] {
    if (typeof value !== "string" || !allowed.includes(value)) {
      throw new BadRequestException(errorMessage);
    }
    return value as T[number];
  }
}
