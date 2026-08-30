import { Injectable } from '@nestjs/common';
import {
  AuditPresentationChange,
  AuditPresentationEvent,
  AuditPresentationInput,
} from './audit-presentation.types';

const SENSITIVE_KEY =
  /password|token|secret|authorization|credential|otp|hash|session|refresh|cookie|privatekey/i;
const REDACTION_MARKERS = new Set(['[REDACTED]', '[PRIVATE]', '[PII]', '[EMAIL]']);

const ENTITY_LABELS: Record<string, string> = {
  'access:user': 'Доступ пользователя',
  account_deletion_request: 'Запрос на удаление аккаунта',
  student: 'Ученик',
  'crm:student': 'Ученик',
  client: 'Клиент',
  lead: 'Лид',
  'crm:lead': 'Лид',
  teacher: 'Преподаватель',
  staff: 'Сотрудник',
  lesson: 'Занятие',
  group: 'Группа',
  branch: 'Филиал',
  branch_discipline: 'Направление филиала',
  payment: 'Платёж',
  subscription: 'Абонемент',
  subscription_package: 'Тариф абонемента',
  task: 'Задача',
  shared_task: 'Задача',
  comment: 'Комментарий',
  'crm:comment': 'Комментарий',
  client_internal_note: 'Общая заметка клиента',
  client_custom_field: 'Дополнительное поле клиента',
  client_pipeline_revision: 'Версия воронки клиентов',
  client_status_list: 'Список статусов клиентов',
  client_payment_record: 'Платёж клиента',
  account_adjustment: 'Корректировка счёта',
  crm_configuration_revision: 'Версия настроек CRM',
  discipline: 'Направление',
  expense: 'Расход',
  family: 'Семья',
  family_member: 'Член семьи',
  inbound_lead_ingestion: 'Импорт входящего лида',
  lead_source: 'Источник лида',
  lesson_batch: 'Серия занятий',
  lesson_list: 'Список занятий',
  legal_consent: 'Юридическое согласие',
  loss_reason: 'Причина отказа',
  message: 'Сообщение',
  chat: 'Чат',
  channel: 'Канал',
  email_outbox: 'Исходящее письмо',
  file: 'Файл',
  notification: 'Уведомление',
  notification_delivery: 'Доставка уведомления',
  notification_device: 'Устройство уведомлений',
  notification_preference: 'Настройка уведомлений',
  phone_review_queue: 'Проверка телефона',
  profile: 'Профиль',
  refresh_session: 'Сеанс обновления',
  report: 'Отчёт',
  room: 'Кабинет',
  schedule_plan: 'План занятий',
  schedule_series: 'Серия расписания',
  school_finance_month: 'Финансы школы за месяц',
  setting: 'Настройка',
  homework: 'Домашнее задание',
  user: 'Пользователь',
};

const FIELD_LABELS: Record<string, string> = {
  direction: 'Направление',
  email: 'Электронная почта',
  phone: 'Телефон',
  name: 'Имя',
  status: 'Статус',
  firstName: 'Имя',
  lastName: 'Фамилия',
  displayName: 'Отображаемое имя',
  marketingConsent: 'Маркетинговое согласие',
  sharedWithTeacher: 'Доступ преподавателя',
};

const ACTION_TITLES: Record<string, string> = {
  'crm.account_transfer_created': 'Перевод между счетами создан',
  'crm.branch_archived': 'Филиал архивирован',
  'crm.branch_created': 'Филиал создан',
  'crm.branch_hours_replaced': 'Часы работы филиала изменены',
  'crm.branch_restored': 'Филиал восстановлен',
  'crm.branch_updated': 'Филиал изменён',
  'crm.client_archived': 'Клиент архивирован',
  'crm.client_custom_field_archived': 'Дополнительное поле клиента архивировано',
  'crm.client_custom_field_created': 'Дополнительное поле клиента создано',
  'crm.client_custom_field_updated': 'Дополнительное поле клиента изменено',
  'crm.client_pipeline_published': 'Воронка клиентов опубликована',
  'crm.client_user_linked': 'Пользователь привязан к клиенту',
  'crm.configuration_published': 'Настройки CRM опубликованы',
  'crm.duplicate_candidate_decided': 'Дубликат клиента обработан',
  'crm.expense_created': 'Расход создан',
  'crm.expense_deleted': 'Расход удалён',
  'crm.expense_updated': 'Расход изменён',
  'crm.family_member_added': 'Член семьи добавлен',
  'crm.family_member_removed': 'Член семьи удалён',
  'crm.family_primary_payer_set': 'Основной плательщик семьи назначен',
  'crm.group_archived': 'Группа архивирована',
  'crm.group_created': 'Группа создана',
  'crm.group_restored': 'Группа восстановлена',
  'crm.group_student_added': 'Ученик добавлен в группу',
  'crm.group_student_removed': 'Ученик удалён из группы',
  'crm.group_updated': 'Группа изменена',
  'crm.homework_assigned': 'Домашнее задание назначено',
  'crm.homework_attachment_added': 'Вложение к домашнему заданию добавлено',
  'crm.homework_submitted': 'Домашнее задание сдано',
  'crm.homework_updated': 'Домашнее задание изменено',
  'crm.inbound_lead_ingested': 'Входящий лид принят',
  'crm.lead_created': 'Лид создан',
  'crm.lead_source_archived': 'Источник лида архивирован',
  'crm.lead_source_created': 'Источник лида создан',
  'crm.lead_source_updated': 'Источник лида изменён',
  'crm.lead_student_linked': 'Лид связан с учеником',
  'crm.lead_updated': 'Лид изменён',
  'crm.student_created': 'Ученик создан',
  'crm.student_archived': 'Ученик архивирован',
  'crm.student_restored': 'Ученик восстановлен',
  'crm.student_invite_sent': 'Приглашение ученику отправлено',
  'crm.staff_access_managed': 'Доступ сотрудника изменён',
  'crm.staff_created': 'Сотрудник создан',
  'crm.staff_credentials_viewed': 'Данные для входа сотрудника просмотрены',
  'crm.staff_offboarded': 'Сотрудник архивирован',
  'crm.staff_restored': 'Сотрудник восстановлен',
  'crm.staff_updated': 'Сотрудник изменён',
  'crm.lesson_rescheduled': 'Занятие перенесено',
  'crm.lesson_cancelled': 'Занятие отменено',
  'crm.lesson_completed': 'Занятие завершено',
  'crm.lesson_created': 'Занятие создано',
  'crm.lesson_deleted': 'Занятие удалено',
  'crm.lesson_updated': 'Занятие изменено',
  'crm.lesson_settlement_corrected': 'Проведение занятия скорректировано',
  'crm.lesson_settlement_plan_updated': 'План проведения занятия изменён',
  'crm.lesson_settlement_review_required': 'Занятие отправлено на проверку',
  'crm.lessons_teacher_rate_bulk_set': 'Ставки преподавателя для занятий изменены',
  'crm.lead_converted': 'Лид конвертирован в ученика',
  'crm.subscription_purchased': 'Абонемент приобретён',
  'crm.subscription_issued': 'Абонемент выдан',
  'crm.subscription_replaced': 'Абонемент заменён',
  'crm.subscription_cancelled': 'Абонемент отменён',
  'crm.payment_created': 'Платёж создан',
  'crm.payment_record_created': 'Платёж создан',
  'crm.payment_record_transitioned': 'Статус платежа изменён',
  'crm.installment_payment_due': 'Наступил срок платежа',
  'crm.payment_reversed': 'Платёж отменён',
  'crm.payment_adjustment_recorded': 'Корректировка платежа внесена',
  'crm.payment_adjustment_reversed': 'Корректировка платежа отменена',
  'crm.payment_corrected': 'Платёж скорректирован',
  'crm.lesson_settled': 'Занятие проведено',
  'crm.lesson_settlement_completed': 'Занятие проведено',
  'crm.lessons_bulk_transitioned': 'Статус занятий изменён',
  'crm.schedule_plan_ended': 'План занятий завершён',
  'crm.schedule_plan_created': 'План занятий создан',
  'crm.schedule_plan_updated': 'План занятий изменён',
  'crm.schedule_series_created': 'Серия расписания создана',
  'crm.schedule_series_stopped': 'Серия расписания завершена',
  'crm.schedule_series_updated': 'Серия расписания изменена',
  'crm.client_internal_note_changed': 'Общая заметка изменена',
  'crm.comment_created': 'Комментарий добавлен',
  'crm.comment_teacher_sharing_changed': 'Видимость комментария изменена',
  'workflow.shared_task_created': 'Задача создана',
  'workflow.shared_task_updated': 'Задача изменена',
  'workflow.shared_task_closed': 'Задача закрыта',
  'crm.client_blacklisted': 'Клиент добавлен в чёрный список',
  'crm.client_unblacklisted': 'Клиент убран из чёрного списка',
  'crm.lead_status_changed': 'Статус лида изменён',
  'crm.lead_owner_changed': 'Ответственный по лиду изменён',
  'crm.lead_status_and_owner_changed': 'Статус и ответственный по лиду изменены',
  'crm.phone_review_resolved': 'Проверка телефона завершена',
  'crm.room_archived': 'Кабинет архивирован',
  'crm.room_created': 'Кабинет создан',
  'crm.room_restored': 'Кабинет восстановлен',
  'crm.room_updated': 'Кабинет изменён',
  'crm.subscription_package_archived': 'Тариф абонемента архивирован',
  'crm.subscription_package_created': 'Тариф абонемента создан',
  'crm.subscription_package_restored': 'Тариф абонемента восстановлен',
  'crm.subscription_package_updated': 'Тариф абонемента изменён',
  'crm.teacher_access_managed': 'Доступ преподавателя изменён',
  'crm.teacher_availability_replaced': 'Доступность преподавателя изменена',
  'crm.teacher_branches_replaced': 'Филиалы преподавателя изменены',
  'crm.teacher_created': 'Преподаватель создан',
  'crm.teacher_credentials_viewed': 'Данные для входа преподавателя просмотрены',
  'crm.teacher_offboarded': 'Преподаватель архивирован',
  'crm.teacher_payout_created': 'Выплата преподавателю создана',
  'crm.teacher_payout_deleted': 'Выплата преподавателю удалена',
  'crm.teacher_payout_updated': 'Выплата преподавателю изменена',
  'crm.teacher_rate_deleted': 'Ставка преподавателя удалена',
  'crm.teacher_rate_set': 'Ставка преподавателя назначена',
  'crm.teacher_rate_updated': 'Ставка преподавателя изменена',
  'crm.teacher_restored': 'Преподаватель восстановлен',
  'crm.teacher_updated': 'Преподаватель изменён',
  'crm.reference_discipline_archived': 'Направление архивировано',
  'crm.reference_discipline_renamed': 'Направление переименовано',
  'crm.reference_discipline_restored': 'Направление восстановлено',
  'crm.reference_loss_reason_archived': 'Причина отказа архивирована',
  'crm.reference_loss_reason_renamed': 'Причина отказа переименована',
  'crm.reference_loss_reason_restored': 'Причина отказа восстановлена',
  'crm.reference_branch_discipline_renamed': 'Направление филиала переименовано',
  'crm.reference_branch_discipline_restored': 'Направление филиала восстановлено',
  'crm.reference_branch_discipline_unassigned': 'Направление отвязано от филиала',
  'workflow.shared_task_legacy_status': 'Статус задачи перенесён',
};

const ROUTE_TYPES: Record<string, string> = {
  student: 'student',
  client: 'client',
  lead: 'lead',
  teacher: 'teacher',
  lesson: 'lesson',
  group: 'group',
  branch: 'branch',
  payment: 'payment',
  subscription: 'subscription',
  task: 'task',
  shared_task: 'task',
  comment: 'comment',
};

const ACTION_SUFFIXES: Record<string, string> = {
  created: 'создано',
  updated: 'изменено',
  deleted: 'удалено',
  archived: 'архивировано',
  restored: 'восстановлено',
  rescheduled: 'перенесено',
  cancelled: 'отменено',
  canceled: 'отменено',
  completed: 'завершено',
};

const GENERIC_ACTION_TITLES: Record<string, string> = {
  created: 'Запись создана',
  updated: 'Данные изменены',
  deleted: 'Запись удалена',
  archived: 'Запись архивирована',
  restored: 'Запись восстановлена',
  rescheduled: 'Запись перенесена',
  cancelled: 'Запись отменена',
  canceled: 'Запись отменена',
  completed: 'Запись завершена',
};

const ENTITY_POSSESSIVE_LABELS: Record<string, string> = {
  student: 'ученика',
  client: 'клиента',
  lead: 'лида',
  teacher: 'преподавателя',
  lesson: 'занятия',
  group: 'группы',
  branch: 'филиала',
  payment: 'платежа',
  subscription: 'абонемента',
  task: 'задачи',
};

const STUDENT_FIELD_UPDATE_TITLES: Record<string, string> = {
  direction: 'Направление изменено',
  email: 'Электронная почта изменена',
  name: 'Имя ученика изменено',
  phone: 'Телефон ученика изменён',
};

const FIELD_UPDATE_VERBS: Record<string, string> = {
  email: 'изменена',
  name: 'изменено',
  phone: 'изменён',
  marketingConsent: 'изменено',
};

@Injectable()
export class AuditPresentationService {
  present(input: AuditPresentationInput): AuditPresentationEvent {
    const changes = this.extractChanges(
      input.metadata,
      input.beforeRef,
      input.afterRef,
    );

    return {
      id: input.id,
      actionKey: input.actionKey,
      title: this.titleFor(input.actionKey, changes),
      summary: this.summaryFor(input),
      reason: this.reasonFor(input),
      actor: {
        id: input.actor.id,
        name: this.safeValue(input.actor.name) ?? 'Неизвестный пользователь',
        role: this.safeValue(input.actor.role),
      },
      target: {
        type: input.target.type,
        id: input.target.id,
        label: ENTITY_LABELS[input.target.type] ?? this.humanizeIdentifier(input.target.type),
        displayName: this.safeValue(input.target.displayName),
        routeType: ROUTE_TYPES[input.target.type] ?? null,
      },
      changes,
      occurredAt: input.occurredAt,
    };
  }

  isBusinessAction(actionKey: string): boolean {
    return !/^(auth|session|security|system|health)\./i.test(actionKey);
  }

  private summaryFor(input: AuditPresentationInput): string | null {
    return this.safeValue(input.reasonText) ?? this.commentSharingSummary(input);
  }

  private reasonFor(input: AuditPresentationInput): string | null {
    const metadataReason = this.metadataReason(input.metadata);
    const directReason = this.safeBusinessReason(input.reason);

    if (input.actionKey === 'crm.comment_teacher_sharing_changed') {
      return metadataReason
        ?? directReason
        ?? this.commentSharingReason(input);
    }

    return directReason ?? metadataReason;
  }

  private metadataReason(metadata: Record<string, unknown> | null): string | null {
    return metadata && this.isRecord(metadata)
      ? this.safeBusinessReason(metadata.reason)
      : null;
  }

  private safeBusinessReason(value: unknown): string | null {
    const safe = this.safeValue(value);
    if (!safe) {
      return null;
    }

    const trimmed = safe.trim();
    if (
      !trimmed
      || /^[a-z0-9]+(?:[_:./-][a-z0-9]+)*$/i.test(trimmed)
      || /^(?:manual|automatic|system|migration|import|unknown|default)\b/i.test(trimmed)
      || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)
    ) {
      return null;
    }

    return trimmed;
  }

  private commentSharingSummary(input: AuditPresentationInput): string | null {
    if (input.actionKey !== 'crm.comment_teacher_sharing_changed') {
      return null;
    }

    const sharedWithTeacher = input.afterRef?.sharedWithTeacher;
    if (sharedWithTeacher === true || sharedWithTeacher === 'true') {
      return 'Опубликован преподавателю';
    }
    if (sharedWithTeacher === false || sharedWithTeacher === 'false') {
      return 'Скрыт от преподавателя';
    }
    return null;
  }

  private commentSharingReason(input: AuditPresentationInput): string | null {
    const summary = this.commentSharingSummary(input);
    if (summary === 'Опубликован преподавателю') {
      return 'Комментарий опубликован преподавателю';
    }
    if (summary === 'Скрыт от преподавателя') {
      return 'Комментарий скрыт от преподавателя';
    }
    return null;
  }

  private extractChanges(
    metadata: Record<string, unknown> | null,
    beforeRef: Record<string, unknown> | null,
    afterRef: Record<string, unknown> | null,
  ): AuditPresentationChange[] {
    const metadataChanges = this.extractMetadataChanges(metadata);
    const metadataKeys = new Set(metadataChanges.map((change) => change.key));
    const before = beforeRef ?? {};
    const after = afterRef ?? {};
    const keys = new Set([...Object.keys(before), ...Object.keys(after)]);

    return [...metadataChanges, ...[...keys].flatMap((key) => {
      if (metadataKeys.has(key)) {
        return [];
      }
      if (this.isTechnicalOrSensitiveKey(key)) {
        return [];
      }

      const beforeValue = this.safeValue(before[key]);
      const afterValue = this.safeValue(after[key]);
      if (beforeValue === afterValue) {
        return [];
      }

      return [{
        key,
        label: FIELD_LABELS[key] ?? this.humanizeIdentifier(key),
        before: beforeValue,
        after: afterValue,
      }];
    })];
  }

  private extractMetadataChanges(
    metadata: Record<string, unknown> | null,
  ): AuditPresentationChange[] {
    const rawChanges = metadata?.changes;
    if (!Array.isArray(rawChanges)) {
      return [];
    }

    return rawChanges.flatMap((rawChange) => {
      if (!this.isRecord(rawChange)) {
        return [];
      }

      const key = this.metadataChangeKey(rawChange);
      if (!key || this.isTechnicalOrSensitiveKey(key)) {
        return [];
      }

      const beforeKey = "from" in rawChange ? "from" : "before";
      const afterKey = "to" in rawChange ? "to" : "after";
      if (!(beforeKey in rawChange) || !(afterKey in rawChange)) {
        return [];
      }

      return [{
        key,
        label: FIELD_LABELS[key] ?? this.humanizeIdentifier(key),
        before: this.safeValue(rawChange[beforeKey]),
        after: this.safeValue(rawChange[afterKey]),
      }];
    });
  }

  private metadataChangeKey(change: Record<string, unknown>): string | null {
    const key = typeof change.field === "string" ? change.field : change.key;
    return typeof key === "string" && key.trim() ? key : null;
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }

  private titleFor(actionKey: string, changes: AuditPresentationChange[]): string {
    if (actionKey === 'crm.student_updated' && changes.length === 1) {
      return STUDENT_FIELD_UPDATE_TITLES[changes[0].key] ?? 'Данные ученика изменены';
    }

    return ACTION_TITLES[actionKey] ?? this.humanizeAction(actionKey);
  }

  private humanizeAction(actionKey: string): string {
    const segments = actionKey.split('.').filter(Boolean);
    const action = segments.pop() ?? actionKey;
    const suffix = Object.keys(ACTION_SUFFIXES).find((candidate) =>
      action.endsWith(`_${candidate}`),
    );

    if (suffix) {
      const subject = action.slice(0, -(suffix.length + 1));
      const localizedSubject = this.localizeActionSubject(subject);
      if (localizedSubject) {
        return `${localizedSubject.label} ${this.actionSuffixFor(
          suffix,
          localizedSubject.fieldKey,
        )}`;
      }

      return GENERIC_ACTION_TITLES[suffix] ?? 'Действие выполнено';
    }

    return 'Действие выполнено';
  }

  private localizeActionSubject(
    subject: string,
  ): { label: string; fieldKey: string | null } | null {
    const [entityType, ...fieldParts] = subject.split('_').filter(Boolean);
    const possessiveEntity = ENTITY_POSSESSIVE_LABELS[entityType];
    if (!possessiveEntity) {
      return null;
    }

    const fieldKey = this.toCamelCase(fieldParts);
    const fieldLabel = FIELD_LABELS[fieldKey];
    if (!fieldLabel) {
      return { label: `Данные ${possessiveEntity}`, fieldKey: null };
    }

    return { label: `${fieldLabel} ${possessiveEntity}`, fieldKey };
  }

  private actionSuffixFor(suffix: string, fieldKey: string | null): string {
    if (suffix === 'updated') {
      return fieldKey ? FIELD_UPDATE_VERBS[fieldKey] ?? 'изменено' : 'изменены';
    }

    return ACTION_SUFFIXES[suffix] ?? 'изменено';
  }

  private humanizeIdentifier(value: string): string {
    const words = value
      .replace(/([a-zа-я])([A-ZА-Я])/g, '$1 $2')
      .split(/[._\-\s]+/)
      .filter(Boolean)
      .map((word) => word.toLowerCase());
    const text = words.join(' ');

    return text ? `${text[0].toUpperCase()}${text.slice(1)}` : 'Неизвестно';
  }

  private toCamelCase(parts: string[]): string {
    return parts
      .map((part, index) =>
        index === 0 ? part : `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`,
      )
      .join('');
  }

  private isTechnicalOrSensitiveKey(key: string): boolean {
    return key.toLowerCase() === 'version' || SENSITIVE_KEY.test(key);
  }

  private safeValue(value: unknown): string | null {
    if (value === null || value === undefined || this.isRedactionMarker(value)) {
      return null;
    }

    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }

    return null;
  }

  private isRedactionMarker(value: unknown): value is string {
    return typeof value === 'string' && REDACTION_MARKERS.has(value.trim().toUpperCase());
  }
}
