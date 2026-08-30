import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import * as ts from 'typescript';
import { AuditPresentationInput } from './audit-presentation.types';
import { AuditPresentationService } from './audit-presentation.service';

const PRODUCT_ACTION_TITLES: Record<string, string> = {
  'crm.account_transfer_created': 'Перевод между счетами создан',
  'crm.branch_archived': 'Филиал архивирован',
  'crm.branch_created': 'Филиал создан',
  'crm.branch_hours_replaced': 'Часы работы филиала изменены',
  'crm.branch_restored': 'Филиал восстановлен',
  'crm.branch_updated': 'Филиал изменён',
  'crm.client_archived': 'Клиент архивирован',
  'crm.client_blacklisted': 'Клиент добавлен в чёрный список',
  'crm.client_custom_field_archived': 'Дополнительное поле клиента архивировано',
  'crm.client_custom_field_created': 'Дополнительное поле клиента создано',
  'crm.client_custom_field_updated': 'Дополнительное поле клиента изменено',
  'crm.client_internal_note_changed': 'Общая заметка изменена',
  'crm.client_pipeline_published': 'Воронка клиентов опубликована',
  'crm.client_unblacklisted': 'Клиент убран из чёрного списка',
  'crm.client_user_linked': 'Пользователь привязан к клиенту',
  'crm.comment_created': 'Комментарий добавлен',
  'crm.comment_teacher_sharing_changed': 'Видимость комментария изменена',
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
  'crm.installment_payment_due': 'Наступил срок платежа',
  'crm.lead_converted': 'Лид конвертирован в ученика',
  'crm.lead_created': 'Лид создан',
  'crm.lead_owner_changed': 'Ответственный по лиду изменён',
  'crm.lead_source_archived': 'Источник лида архивирован',
  'crm.lead_source_created': 'Источник лида создан',
  'crm.lead_source_updated': 'Источник лида изменён',
  'crm.lead_status_and_owner_changed': 'Статус и ответственный по лиду изменены',
  'crm.lead_status_changed': 'Статус лида изменён',
  'crm.lead_student_linked': 'Лид связан с учеником',
  'crm.lead_updated': 'Лид изменён',
  'crm.lesson_cancelled': 'Занятие отменено',
  'crm.lesson_completed': 'Занятие завершено',
  'crm.lesson_created': 'Занятие создано',
  'crm.lesson_deleted': 'Занятие удалено',
  'crm.lesson_rescheduled': 'Занятие перенесено',
  'crm.lesson_settled': 'Занятие проведено',
  'crm.lesson_settlement_completed': 'Занятие проведено',
  'crm.lesson_settlement_corrected': 'Проведение занятия скорректировано',
  'crm.lesson_settlement_plan_updated': 'План проведения занятия изменён',
  'crm.lesson_settlement_review_required': 'Занятие отправлено на проверку',
  'crm.lesson_updated': 'Занятие изменено',
  'crm.lessons_bulk_transitioned': 'Статус занятий изменён',
  'crm.lessons_teacher_rate_bulk_set': 'Ставки преподавателя для занятий изменены',
  'crm.payment_adjustment_recorded': 'Корректировка платежа внесена',
  'crm.payment_adjustment_reversed': 'Корректировка платежа отменена',
  'crm.payment_corrected': 'Платёж скорректирован',
  'crm.payment_created': 'Платёж создан',
  'crm.payment_record_created': 'Платёж создан',
  'crm.payment_record_transitioned': 'Статус платежа изменён',
  'crm.payment_reversed': 'Платёж отменён',
  'crm.phone_review_resolved': 'Проверка телефона завершена',
  'crm.room_archived': 'Кабинет архивирован',
  'crm.room_created': 'Кабинет создан',
  'crm.room_restored': 'Кабинет восстановлен',
  'crm.room_updated': 'Кабинет изменён',
  'crm.schedule_plan_created': 'План занятий создан',
  'crm.schedule_plan_ended': 'План занятий завершён',
  'crm.schedule_plan_updated': 'План занятий изменён',
  'crm.schedule_series_created': 'Серия расписания создана',
  'crm.schedule_series_stopped': 'Серия расписания завершена',
  'crm.schedule_series_updated': 'Серия расписания изменена',
  'crm.staff_access_managed': 'Доступ сотрудника изменён',
  'crm.staff_created': 'Сотрудник создан',
  'crm.staff_credentials_viewed': 'Данные для входа сотрудника просмотрены',
  'crm.staff_offboarded': 'Сотрудник архивирован',
  'crm.staff_restored': 'Сотрудник восстановлен',
  'crm.staff_updated': 'Сотрудник изменён',
  'crm.student_archived': 'Ученик архивирован',
  'crm.student_created': 'Ученик создан',
  'crm.student_invite_sent': 'Приглашение ученику отправлено',
  'crm.student_restored': 'Ученик восстановлен',
  'crm.student_updated': 'Данные ученика изменены',
  'crm.subscription_cancelled': 'Абонемент отменён',
  'crm.subscription_issued': 'Абонемент выдан',
  'crm.subscription_package_archived': 'Тариф абонемента архивирован',
  'crm.subscription_package_created': 'Тариф абонемента создан',
  'crm.subscription_package_restored': 'Тариф абонемента восстановлен',
  'crm.subscription_package_updated': 'Тариф абонемента изменён',
  'crm.subscription_purchased': 'Абонемент приобретён',
  'crm.subscription_replaced': 'Абонемент заменён',
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
  'workflow.shared_task_closed': 'Задача закрыта',
  'workflow.shared_task_created': 'Задача создана',
  'workflow.shared_task_legacy_status': 'Статус задачи перенесён',
  'workflow.shared_task_updated': 'Задача изменена',
};

const REFERENCE_ACTION_TITLES: Record<string, string> = {
  'crm.reference_discipline_archived': 'Направление архивировано',
  'crm.reference_discipline_renamed': 'Направление переименовано',
  'crm.reference_discipline_restored': 'Направление восстановлено',
  'crm.reference_loss_reason_archived': 'Причина отказа архивирована',
  'crm.reference_loss_reason_renamed': 'Причина отказа переименована',
  'crm.reference_loss_reason_restored': 'Причина отказа восстановлена',
  'crm.reference_branch_discipline_renamed': 'Направление филиала переименовано',
  'crm.reference_branch_discipline_restored': 'Направление филиала восстановлено',
  'crm.reference_branch_discipline_unassigned': 'Направление отвязано от филиала',
};

const PRODUCT_ENTITY_LABELS: Record<string, string> = {
  account_adjustment: 'Корректировка счёта',
  'access:user': 'Доступ пользователя',
  account_deletion_request: 'Запрос на удаление аккаунта',
  branch: 'Филиал',
  branch_discipline: 'Направление филиала',
  client: 'Клиент',
  client_custom_field: 'Дополнительное поле клиента',
  client_internal_note: 'Общая заметка клиента',
  client_payment_record: 'Платёж клиента',
  client_pipeline_revision: 'Версия воронки клиентов',
  client_status_list: 'Список статусов клиентов',
  comment: 'Комментарий',
  'crm:comment': 'Комментарий',
  'crm:lead': 'Лид',
  'crm:student': 'Ученик',
  crm_configuration_revision: 'Версия настроек CRM',
  discipline: 'Направление',
  expense: 'Расход',
  email_outbox: 'Исходящее письмо',
  file: 'Файл',
  family: 'Семья',
  family_member: 'Член семьи',
  group: 'Группа',
  homework: 'Домашнее задание',
  inbound_lead_ingestion: 'Импорт входящего лида',
  lead: 'Лид',
  lead_source: 'Источник лида',
  lesson: 'Занятие',
  lesson_batch: 'Серия занятий',
  lesson_list: 'Список занятий',
  legal_consent: 'Юридическое согласие',
  loss_reason: 'Причина отказа',
  payment: 'Платёж',
  message: 'Сообщение',
  chat: 'Чат',
  channel: 'Канал',
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
  shared_task: 'Задача',
  staff: 'Сотрудник',
  student: 'Ученик',
  subscription: 'Абонемент',
  subscription_package: 'Тариф абонемента',
  task: 'Задача',
  teacher: 'Преподаватель',
  user: 'Пользователь',
};

const DYNAMIC_PRODUCT_ACTIONS = Object.keys(REFERENCE_ACTION_TITLES).concat([
  'crm.staff_access_managed',
  'crm.staff_credentials_viewed',
  'crm.staff_offboarded',
  'crm.staff_restored',
  'crm.teacher_access_managed',
  'crm.teacher_credentials_viewed',
  'crm.teacher_offboarded',
  'crm.teacher_payout_deleted',
  'crm.teacher_rate_deleted',
  'crm.teacher_restored',
]);

function productionTypescriptFiles(directory: string): string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return productionTypescriptFiles(path);
    return entry.name.endsWith('.ts')
      && !entry.name.endsWith('.spec.ts')
      && !entry.name.endsWith('.test.ts')
      ? [path]
      : [];
  });
}

function literalsInside(node: ts.Node): string[] {
  const values: string[] = [];
  const visit = (child: ts.Node) => {
    if (ts.isStringLiteralLike(child)) values.push(child.text);
    ts.forEachChild(child, visit);
  };
  visit(node);
  return values;
}

function productionAuditContract() {
  const actions = new Set<string>();
  const entityTypes = new Set<string>();
  const dynamicActionTemplates = new Set<string>();
  const sourceRoot = join(__dirname, '..');

  for (const path of productionTypescriptFiles(sourceRoot)) {
    const source = ts.createSourceFile(
      path,
      readFileSync(path, 'utf8'),
      ts.ScriptTarget.Latest,
      true,
    );
    const visit = (node: ts.Node) => {
      if (ts.isPropertyAssignment(node)) {
        const name = node.name.getText(source).replace(/['"]/g, '');
        if (name === 'action') {
          for (const value of literalsInside(node.initializer)) {
            if (/^(crm|workflow)\.[a-z0-9_]+$/.test(value)) actions.add(value);
          }
          const sourceText = node.initializer.getText(source);
          if (/`(?:crm|workflow)\.[^`]*\$\{/.test(sourceText)) {
            dynamicActionTemplates.add(sourceText.replace(/\s+/g, ''));
          }
        }
        if (name === 'entityType') {
          for (const value of literalsInside(node.initializer)) {
            if (/^[a-z][a-z0-9_:]*$/.test(value)) entityTypes.add(value);
          }
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(source);
  }

  return { actions, entityTypes, dynamicActionTemplates };
}

describe('Audit presentation production coverage', () => {
  const service = new AuditPresentationService();
  const input: AuditPresentationInput = {
    id: 'event-coverage',
    actionKey: 'crm.student_created',
    actor: { id: 'actor-1', name: 'Администратор', role: 'admin' },
    target: { type: 'student', id: 'student-1', displayName: 'Мария' },
    metadata: null,
    beforeRef: null,
    afterRef: null,
    reason: null,
    reasonText: null,
    occurredAt: new Date('2026-08-31T00:00:00.000Z'),
  };

  it('gives every literal CRM/workflow producer action a concrete central Russian title', () => {
    const { actions, dynamicActionTemplates } = productionAuditContract();
    expect([...actions].filter((action) => !(action in PRODUCT_ACTION_TITLES))).toEqual([]);
    expect([...dynamicActionTemplates].sort()).toEqual([
      '`crm.${personType}_access_managed`',
      '`crm.${personType}_credentials_viewed`',
      '`crm.${personType}_offboarded`',
      '`crm.${personType}_restored`',
      '`crm.reference_${entityType}_${action}`',
      '`crm.teacher_${kind}_deleted`',
    ]);

    for (const [actionKey, title] of Object.entries({
      ...PRODUCT_ACTION_TITLES,
      ...REFERENCE_ACTION_TITLES,
    })) {
      expect(service.present({ ...input, actionKey }).title).toBe(title);
    }
    expect(DYNAMIC_PRODUCT_ACTIONS.every((action) =>
      action in PRODUCT_ACTION_TITLES || action in REFERENCE_ACTION_TITLES,
    )).toBe(true);
  });

  it('gives every known product target type a central Russian label', () => {
    const { entityTypes } = productionAuditContract();
    expect([...entityTypes].filter((type) => !(type in PRODUCT_ENTITY_LABELS))).toEqual([]);

    for (const [type, label] of Object.entries(PRODUCT_ENTITY_LABELS)) {
      const target = service.present({
        ...input,
        target: { type, id: 'target-1', displayName: null },
      }).target;
      expect(target.label).toBe(label);
      expect(target.label).not.toMatch(/[_:]/);
    }
  });
});
