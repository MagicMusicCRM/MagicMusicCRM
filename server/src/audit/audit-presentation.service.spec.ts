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
        beforeRef: { direction: 'Вокал' },
        afterRef: { direction: 'Фортепиано' },
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
