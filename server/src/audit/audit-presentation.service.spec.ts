import { AuditPresentationInput } from './audit-presentation.types';
import { AuditPresentationService } from './audit-presentation.service';

describe('AuditPresentationService', () => {
  const service = new AuditPresentationService();

  const emailChange: AuditPresentationInput = {
    id: 'event-1',
    actionKey: 'crm.student_updated',
    actor: { id: 'user-1', name: 'Наталия Назарова', role: 'director' },
    target: {
      type: 'student',
      id: 'student-1',
      displayName: 'Мария Баранова',
    },
    metadata: {},
    beforeRef: { email: 'old@example.com', version: 11 },
    afterRef: { email: 'new@example.com', version: 12 },
    reason: null,
    reasonText: null,
    occurredAt: new Date('2026-08-30T17:21:00.000Z'),
  };

  it('presents a known email change with Russian labels and no technical version', () => {
    expect(service.present(emailChange)).toMatchObject({
      title: 'Электронная почта изменена',
      target: {
        type: 'student',
        id: 'student-1',
        label: 'Ученик',
        displayName: 'Мария Баранова',
        routeType: 'student',
      },
      changes: [
        {
          key: 'email',
          label: 'Электронная почта',
          before: 'old@example.com',
          after: 'new@example.com',
        },
      ],
    });
    expect(JSON.stringify(service.present(emailChange))).not.toContain('version');
  });

  it('presents a student direction change with the shared Russian title and label', () => {
    expect(
      service.present({
        ...emailChange,
        metadata: {
          changes: [{ field: 'direction', from: 'Вокал', to: 'Фортепиано' }],
        },
        beforeRef: null,
        afterRef: null,
      }),
    ).toMatchObject({
      title: 'Направление изменено',
      changes: [
        {
          key: 'direction',
          label: 'Направление',
          before: 'Вокал',
          after: 'Фортепиано',
        },
      ],
    });
  });

  it.each([
    ['custom_data.level', null, 'Без опыта', 'Уровень', null, 'Без опыта'],
    ['custom_data.discipline', null, 'DRUMS', 'Направление', null, 'DRUMS'],
    [
      'custom_data.disciplines',
      '[]',
      '["DRUMS"]',
      'Направления',
      null,
      'DRUMS',
    ],
    [
      'custom_data.disciplines',
      '["DRUMS",null,""]',
      '["PIANO",{"internal":"value"}]',
      'Направления',
      null,
      null,
    ],
  ])(
    'presents custom field %s in Russian without JSON list syntax',
    (field, from, to, label, before, after) => {
      const presented = service.present({
        ...emailChange,
        metadata: { changes: [{ field, from, to }] },
        beforeRef: null,
        afterRef: null,
      });

      expect(presented.changes).toEqual([
        { key: field, label, before, after },
      ]);
      expect(presented.changes[0].label).not.toMatch(/custom[._ ]data/i);
    },
  );

  it('uses a Russian neutral label for an unknown custom field', () => {
    const presented = service.present({
      ...emailChange,
      metadata: {
        changes: [
          {
            field: 'custom_data.favoriteColor',
            from: 'Синий',
            to: 'Зелёный',
          },
        ],
      },
      beforeRef: null,
      afterRef: null,
    });

    expect(presented.changes).toEqual([
      {
        key: 'custom_data.favoriteColor',
        label: 'Дополнительное поле',
        before: 'Синий',
        after: 'Зелёный',
      },
    ]);
    expect(JSON.stringify(presented)).not.toMatch(/Custom data|Favorite color/);
  });

  it.each([
    ['first_name', 'Анна', 'Мария', 'Имя', 'Анна', 'Мария'],
    ['last_name', 'Иванова', 'Петрова', 'Фамилия', 'Иванова', 'Петрова'],
    ['notes', 'До', 'После', 'Заметки', 'До', 'После'],
    [
      'assigned_to',
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
      'Ответственный',
      null,
      null,
    ],
    [
      'custom_data.birthday',
      '2000-02-01',
      '2001-03-02',
      'Дата рождения',
      '01.02.2000',
      '02.03.2001',
    ],
    [
      'custom_data.category',
      'Дети',
      'Взрослые',
      'Категория обучения',
      'Дети',
      'Взрослые',
    ],
    [
      'custom_data.levels',
      'Начальный',
      'Средний',
      'Уровни обучения',
      'Начальный',
      'Средний',
    ],
    [
      'custom_data.favoriteColor',
      'Синий',
      'Зелёный',
      'Дополнительное поле',
      'Синий',
      'Зелёный',
    ],
  ])(
    'routes field %s through the shared presentation policy',
    (field, from, to, label, before, after) => {
      expect(service.present({
        ...emailChange,
        beforeRef: { [field]: from },
        afterRef: { [field]: to },
      }).changes).toEqual([{ key: field, label, before, after }]);
    },
  );

  it('suppresses a technical closedBy reference through the shared presentation policy', () => {
    const uuid = '11111111-1111-4111-8111-111111111111';
    const closedByInput: AuditPresentationInput = {
      ...emailChange,
      beforeRef: { closedBy: null },
      afterRef: { closedBy: uuid },
    };

    expect(service.present(closedByInput).changes).toEqual([]);
    expect(JSON.stringify(service.present(closedByInput))).not.toContain(uuid);
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
    'fingerprint:device-session-42',
  ])('suppresses unsafe unknown ref value %s without a Latin label', (value) => {
    const input: AuditPresentationInput = {
      ...emailChange,
      metadata: {},
      beforeRef: { owner: null },
      afterRef: { owner: value },
    };

    const presented = service.present(input);
    expect(presented.changes).toEqual([{
      key: 'owner',
      label: 'Дополнительное поле',
      before: null,
      after: null,
    }]);
    expect(JSON.stringify(presented)).not.toContain(value);
    expect(JSON.stringify(presented)).not.toContain('"label":"Owner"');
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
    'fingerprint:device-session-42',
  ])('suppresses unsafe unknown metadata value %s without a Latin label', (value) => {
    const input: AuditPresentationInput = {
      ...emailChange,
      metadata: { changes: [{ field: 'owner', from: null, to: value }] },
      beforeRef: null,
      afterRef: null,
    };

    const presented = service.present(input);
    expect(presented.changes).toEqual([{
      key: 'owner',
      label: 'Дополнительное поле',
      before: null,
      after: null,
    }]);
    expect(JSON.stringify(presented)).not.toContain(value);
    expect(JSON.stringify(presented)).not.toContain('"label":"Owner"');
  });

  it('preserves director-defined values through the shared presentation policy', () => {
    const directorValueInput: AuditPresentationInput = {
      ...emailChange,
      beforeRef: { 'custom_data.discipline': null },
      afterRef: { 'custom_data.discipline': 'DRUMS' },
    };

    expect(service.present(directorValueInput).changes[0].after).toBe('DRUMS');
  });

  it('uses safe metadata changes before refs, deduplicates fields, and keeps valueless facts', () => {
    const presented = service.present({
      ...emailChange,
      metadata: {
        changes: [
          { field: 'direction', from: 'Вокал', to: 'Фортепиано' },
          { field: 'email', from: null, to: null },
          { key: 'phone', before: '+79990000000', after: '+79991111111' },
          { field: 'refreshToken', from: 'old-token', to: 'new-token' },
          { field: 'status', from: 'Новый', to: '[REDACTED]' },
        ],
      },
      beforeRef: { direction: 'Референс до', name: 'Мария', email: 'old@example.com' },
      afterRef: { direction: 'Референс после', name: 'Марина', email: 'new@example.com' },
    });

    expect(presented.changes).toEqual([
      { key: 'direction', label: 'Направление', before: 'Вокал', after: 'Фортепиано' },
      { key: 'email', label: 'Электронная почта', before: null, after: null },
      { key: 'phone', label: 'Телефон', before: '+79990000000', after: '+79991111111' },
      { key: 'status', label: 'Статус', before: 'Новый', after: null },
      { key: 'name', label: 'Имя', before: 'Мария', after: 'Марина' },
    ]);
    expect(JSON.stringify(presented)).not.toMatch(/refreshToken|old-token|new-token|\[REDACTED\]/);
  });

  it('uses a valueless metadata email fact to retain the specific title', () => {
    expect(
      service.present({
        ...emailChange,
        metadata: { changes: [{ field: 'email', from: null, to: null }] },
        beforeRef: null,
        afterRef: null,
      }),
    ).toMatchObject({
      title: 'Электронная почта изменена',
      changes: [
        { key: 'email', label: 'Электронная почта', before: null, after: null },
      ],
    });
  });

  it.each([
    [
      'crm.student_marketing_consent_updated',
      'Маркетинговое согласие ученика изменено',
    ],
    ['crm.lesson_rescheduled', 'Занятие перенесено'],
  ])('makes unknown action key %s readable', (actionKey, title) => {
    expect(
      service.present({
        ...emailChange,
        actionKey,
        beforeRef: null,
        afterRef: null,
      }).title,
    ).toBe(title);
  });

  it.each([
    ['crm.lead_converted', 'Лид конвертирован в ученика'],
    ['crm.subscription_purchased', 'Абонемент приобретён'],
    ['crm.subscription_issued', 'Абонемент выдан'],
    ['crm.subscription_replaced', 'Абонемент заменён'],
    ['crm.subscription_cancelled', 'Абонемент отменён'],
    ['crm.payment_created', 'Платёж создан'],
    ['crm.payment_record_transitioned', 'Статус платежа изменён'],
    ['crm.installment_payment_due', 'Наступил срок платежа'],
    ['crm.payment_reversed', 'Платёж отменён'],
    ['crm.payment_adjustment_recorded', 'Корректировка платежа внесена'],
    ['crm.payment_adjustment_reversed', 'Корректировка платежа отменена'],
    ['crm.lesson_rescheduled', 'Занятие перенесено'],
    ['crm.lesson_cancelled', 'Занятие отменено'],
    ['crm.lesson_settled', 'Занятие проведено'],
    ['crm.lessons_bulk_transitioned', 'Статус занятий изменён'],
    ['crm.schedule_plan_ended', 'План занятий завершён'],
    ['crm.schedule_plan_row_removed', 'Строка расписания удалена'],
    ['crm.client_internal_note_changed', 'Общая заметка изменена'],
    ['crm.comment_created', 'Комментарий добавлен'],
    ['crm.comment_teacher_sharing_changed', 'Видимость комментария изменена'],
    ['workflow.shared_task_created', 'Задача создана'],
    ['workflow.shared_task_updated', 'Задача изменена'],
    ['workflow.shared_task_closed', 'Задача закрыта'],
    ['crm.client_blacklisted', 'Клиент добавлен в чёрный список'],
    ['crm.client_unblacklisted', 'Клиент убран из чёрного списка'],
    ['crm.lead_status_changed', 'Статус лида изменён'],
    ['crm.lead_owner_changed', 'Ответственный по лиду изменён'],
    ['crm.lead_status_and_owner_changed', 'Статус и ответственный по лиду изменены'],
  ])('presents common operational action %s as %s', (actionKey, title) => {
    expect(
      service.present({
        ...emailChange,
        actionKey,
        beforeRef: null,
        afterRef: null,
      }).title,
    ).toBe(title);
  });

  it.each([
    ['comment', 'Комментарий', 'comment'],
    ['client_internal_note', 'Общая заметка клиента', null],
    ['shared_task', 'Задача', 'task'],
    ['task', 'Задача', 'task'],
    ['client_payment_record', 'Платёж клиента', null],
    ['account_adjustment', 'Корректировка счёта', null],
    ['lesson_batch', 'Серия занятий', null],
    ['schedule_plan', 'План занятий', null],
    ['homework', 'Домашнее задание', null],
    ['unrecognized_target', 'Unrecognized target', null],
  ])('labels target type %s without exposing unsupported navigation', (type, label, routeType) => {
    expect(
      service.present({
        ...emailChange,
        target: { type, id: 'target-1', displayName: null },
      }).target,
    ).toMatchObject({ type, id: 'target-1', label, routeType });
  });

  it('uses a safe metadata reason and derives comment-sharing text from the safe after ref', () => {
    expect(
      service.present({
        ...emailChange,
        actionKey: 'crm.client_blacklisted',
        metadata: { reason: 'Повторяющийся спам' },
        reason: null,
        reasonText: null,
        beforeRef: null,
        afterRef: null,
      }),
    ).toMatchObject({ reason: 'Повторяющийся спам', summary: null });

    expect(
      service.present({
        ...emailChange,
        actionKey: 'crm.comment_teacher_sharing_changed',
        target: { type: 'comment', id: 'comment-1', displayName: null },
        metadata: { reason: '[REDACTED]' },
        reason: 'crm.comment.teacher-sharing',
        reasonText: null,
        beforeRef: { sharedWithTeacher: false },
        afterRef: { sharedWithTeacher: true },
      }),
    ).toMatchObject({
      reason: 'Комментарий опубликован преподавателю',
      summary: 'Опубликован преподавателю',
      changes: [
        {
          key: 'sharedWithTeacher',
          label: 'Доступ преподавателя',
          before: 'Нет',
          after: 'Да',
        },
      ],
    });
  });

  it('suppresses identifier and technical reference keys before formatting safe changes', () => {
    const presented = service.present({
      ...emailChange,
      actionKey: 'crm.comment_teacher_sharing_changed',
      beforeRef: {
        lessonId: '11111111-1111-4111-8111-111111111111',
        bodyLength: 20,
        'private.key': 'old-private-key',
        sharedWithTeacher: false,
      },
      afterRef: {
        lessonId: '22222222-2222-4222-8222-222222222222',
        bodyLength: 24,
        'private.key': 'new-private-key',
        sharedWithTeacher: true,
      },
    });

    expect(presented.changes).toEqual([
      {
        key: 'sharedWithTeacher',
        label: 'Доступ преподавателя',
        before: 'Нет',
        after: 'Да',
      },
    ]);
    expect(JSON.stringify(presented)).not.toMatch(
      /lessonId|bodyLength|private\.key|private-key|11111111|22222222/,
    );
  });

  it('never exposes internal note contents or length as changes', () => {
    const presented = service.present({
      ...emailChange,
      actionKey: 'crm.client_internal_note_changed',
      target: { type: 'client_internal_note', id: 'note-1', displayName: null },
      beforeRef: { body: 'Секретная заметка до', bodyLength: 20, version: 3 },
      afterRef: { body: 'Секретная заметка после', bodyLength: 24, version: 4 },
    });

    expect(presented.changes).toEqual([]);
    expect(JSON.stringify(presented)).not.toMatch(/Секретная заметка|bodyLength|version/);
  });

  it.each([
    ['task.created', 'Задача создана'],
    ['catalog.record_review_requested', 'Изменение: Record review requested'],
  ])('uses a concrete readable title for business action %s', (actionKey, title) => {
    expect(service.present({
      ...emailChange,
      actionKey,
      beforeRef: null,
      afterRef: null,
    }).title).toBe(title);
  });

  it.each([
    'TEACHER_PAYOUT',
    'payment_record_create',
    'manual',
    'crm.student_updated',
    'student',
    '550e8400-e29b-41d4-a716-446655440000',
  ])('does not expose technical reason %s as business prose', (reason) => {
    expect(service.present({ ...emailChange, reason }).reason).toBeNull();
  });

  it.each([
    'Клиент попросил перенести занятие',
    'Ошибка в платеже',
    'Customer requested a refund',
    'Manual correction requested by client',
    'Import failed because the client requested a retry',
    'System changed after owner approval',
  ])('keeps safe human business reason %s', (reason) => {
    expect(service.present({ ...emailChange, reason }).reason).toBe(reason);
  });

  it('uses the generic student title only when no single field specialization applies', () => {
    expect(service.present({
      ...emailChange,
      beforeRef: null,
      afterRef: null,
    }).title).toBe('Данные ученика изменены');
    expect(service.present({
      ...emailChange,
      beforeRef: { email: 'old@example.com', phone: '+79990000000' },
      afterRef: { email: 'new@example.com', phone: '+79991111111' },
    }).title).toBe('Данные ученика изменены');
  });

  it('labels the role package target in Russian', () => {
    expect(service.present({
      ...emailChange,
      target: { type: 'access:role-package', id: 'director', displayName: null },
    }).target.label).toBe('Пакет прав роли');
  });

  it('extracts only labeled safe changes and omits secret metadata', () => {
    const presented = service.present({
      ...emailChange,
      metadata: { refreshToken: 'token-value', note: '[REDACTED]' },
      beforeRef: {
        email: 'old@example.com',
        refreshToken: 'old-token',
        version: 11,
        status: 'lead',
      },
      afterRef: {
        email: 'new@example.com',
        refreshToken: 'new-token',
        version: 12,
        status: '[REDACTED]',
      },
    });

    expect(presented.changes).toEqual([
      {
        key: 'email',
        label: 'Электронная почта',
        before: 'old@example.com',
        after: 'new@example.com',
      },
      {
        key: 'status',
        label: 'Статус',
        before: 'lead',
        after: null,
      },
    ]);
    expect(JSON.stringify(presented)).not.toContain('refreshToken');
    expect(JSON.stringify(presented)).not.toContain('[REDACTED]');
    expect(JSON.stringify(presented)).not.toContain('version');
  });

  it.each(['[REDACTED]', '[PRIVATE]', '[PII]', '[EMAIL]'])(
    'converts sanitizer marker %s to null in every visible value',
    (marker) => {
      const presented = service.present({
        ...emailChange,
        reason: marker,
        reasonText: marker,
        beforeRef: { status: 'lead' },
        afterRef: { status: marker },
      });

      expect(presented).toMatchObject({
        reason: null,
        summary: null,
        changes: [
          {
            key: 'status',
            label: 'Статус',
            before: 'lead',
            after: null,
          },
        ],
      });
      expect(JSON.stringify(presented)).not.toContain(marker);
    },
  );

  it.each([
    ['name', 'Мария', 'Марина', 'Имя ученика изменено'],
    ['phone', '+79990000000', '+79991111111', 'Телефон ученика изменён'],
  ])(
    'uses a grammatically correct title when student %s changes',
    (key, before, after, title) => {
      expect(
        service.present({
          ...emailChange,
          beforeRef: { [key]: before },
          afterRef: { [key]: after },
        }).title,
      ).toBe(title);
    },
  );

  it('recognizes audit-only auth events as non-business actions', () => {
    expect(service.isBusinessAction('auth.session_rotated')).toBe(false);
    expect(service.isBusinessAction('session.rotated')).toBe(false);
    expect(service.isBusinessAction('crm.student_updated')).toBe(true);
  });
});
