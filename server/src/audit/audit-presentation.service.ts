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
  student: 'Ученик',
  client: 'Клиент',
  lead: 'Лид',
  teacher: 'Преподаватель',
  lesson: 'Занятие',
  group: 'Группа',
  branch: 'Филиал',
  payment: 'Платёж',
  subscription: 'Абонемент',
  task: 'Задача',
};

const FIELD_LABELS: Record<string, string> = {
  email: 'Электронная почта',
  phone: 'Телефон',
  name: 'Имя',
  status: 'Статус',
  firstName: 'Имя',
  lastName: 'Фамилия',
  displayName: 'Отображаемое имя',
  marketingConsent: 'Маркетинговое согласие',
};

const ACTION_TITLES: Record<string, string> = {
  'crm.student_created': 'Ученик создан',
  'crm.student_archived': 'Ученик архивирован',
  'crm.student_restored': 'Ученик восстановлен',
  'crm.lesson_rescheduled': 'Занятие перенесено',
  'crm.lesson_cancelled': 'Занятие отменено',
  'crm.lesson_completed': 'Занятие завершено',
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
    const changes = this.extractChanges(input.beforeRef, input.afterRef);

    return {
      id: input.id,
      actionKey: input.actionKey,
      title: this.titleFor(input.actionKey, changes),
      summary: this.safeValue(input.reasonText),
      reason: this.safeValue(input.reason),
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
        routeType: ROUTE_TYPES[input.target.type] ?? (input.target.type || null),
      },
      changes,
      occurredAt: input.occurredAt,
    };
  }

  isBusinessAction(actionKey: string): boolean {
    return !/^(auth|session|security|system|health)\./i.test(actionKey);
  }

  private extractChanges(
    beforeRef: Record<string, unknown> | null,
    afterRef: Record<string, unknown> | null,
  ): AuditPresentationChange[] {
    const before = beforeRef ?? {};
    const after = afterRef ?? {};
    const keys = new Set([...Object.keys(before), ...Object.keys(after)]);

    return [...keys].flatMap((key) => {
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
    });
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
