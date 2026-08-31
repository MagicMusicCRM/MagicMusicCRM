import {
  createSafeAuditChange,
  presentAuditFieldChange,
} from './audit-field-presentation.policy';

describe('audit field presentation policy', () => {
  it.each(['DRUMS', 'GUITAR', 'PIANO', 'VOCAL', 'Авторское направление №1'])(
    'preserves director value %s exactly',
    (value) => {
      expect(presentAuditFieldChange({
        field: 'custom_data.discipline',
        from: null,
        to: value,
      })).toMatchObject({ label: 'Направление', before: null, after: value });
    },
  );

  it('preserves a previously unseen configured value and mixed case', () => {
    const value = 'Neo Soul DrUmS';
    expect(presentAuditFieldChange({
      field: 'custom_data.discipline',
      from: null,
      to: value,
    })?.after).toBe(value);
  });

  it.each([
    ['custom_data.birthday', '2000-02-01', '01.02.2000'],
    ['custom_data.visitDateTime', '2026-08-31T17:21:00+03:00', '31.08.2026 17:21'],
    ['custom_data.noEmail', true, 'Да'],
    ['custom_data.disciplines', '["DRUMS","Авторское"]', 'DRUMS, Авторское'],
  ])('formats %s structurally without translating content', (field, value, expected) => {
    expect(presentAuditFieldChange({ field, from: null, to: value })?.after)
      .toBe(expected);
  });

  it.each(['closedBy', 'transitionFingerprint', 'sessionId', 'payload_hash'])(
    'suppresses technical field %s',
    (field) => {
      expect(presentAuditFieldChange({ field, from: null, to: 'secret-id' }))
        .toBeNull();
    },
  );

  it.each([
    'amountMinor',
    'archiveEffectiveDate',
    'archivedAt',
    'closedAt',
    'currencyCode',
    'entityType',
    'field',
    'kind',
    'walletBalanceMinor',
  ])('suppresses classified technical field %s despite a values hint', (field) => {
    const input = {
      field,
      from: '2026-08-30T12:00:00.000Z',
      to: '2026-08-31T12:00:00.000Z',
      label: 'Время архивации',
      valueType: 'datetime' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toBeNull();
    expect(presentAuditFieldChange(input)).toBeNull();
  });

  it.each([
    ['accountEnabled', 'Доступ к приложению'],
    ['branchAssignments', 'Филиалы'],
    ['capacity', 'Вместимость'],
    ['financialDecision', 'Финансовое решение'],
    ['items', 'Состав'],
    ['lifecycle', 'Статус'],
    ['lifecycleState', 'Статус'],
    ['personType', 'Тип персоны'],
    ['state', 'Статус'],
    ['value', 'Значение'],
  ])('presents classified business field %s without raw values', (field, label) => {
    expect(createSafeAuditChange({ field, from: 'До', to: 'После' })).toEqual({
      field,
      from: null,
      to: null,
      label,
      valueType: 'text',
      displayMode: 'changed_only',
    });
    expect(presentAuditFieldChange({ field, from: 'До', to: 'После' })).toEqual({
      key: field,
      label,
      before: null,
      after: null,
    });
  });

  it('summarizes contact people without raw PII or JSON', () => {
    const change = presentAuditFieldChange({
      field: 'custom_data.contactPersons',
      from: '[]',
      to: '[{"name":"Анна","phone":"+79991234567"}]',
    });

    expect(change).toMatchObject({
      label: 'Контактные лица',
      before: 'Контактных лиц: 0',
      after: 'Контактных лиц: 1',
    });
    expect(JSON.stringify(change)).not.toContain('+79991234567');
  });

  it('uses a valid stored snapshot before catalog lookup', () => {
    const input = {
      field: 'custom_data.directorField',
      from: 'До',
      to: 'После',
      label: 'Поле директора',
      valueType: 'text' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toEqual(input);
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'custom_data.directorField',
      label: 'Поле директора',
      before: 'До',
      after: 'После',
    });
  });

  it('shows a producer-supplied reference display name only with a values snapshot', () => {
    const input = {
      field: 'assigned_to',
      from: null,
      to: 'Наталия Назарова',
      label: 'Ответственный',
      valueType: 'reference' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toEqual(input);
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'assigned_to',
      label: 'Ответственный',
      before: null,
      after: 'Наталия Назарова',
    });
  });

  it.each([
    '{"name":"Анна","phone":"+79991234567"}',
    '[{"internal":"value"}]',
    '{bad json',
  ])('fails closed for JSON-like unknown custom value %s', (value) => {
    const input = {
      field: 'custom_data.directorField',
      from: null,
      to: value,
    };

    expect(createSafeAuditChange(input)).toEqual({
      field: 'custom_data.directorField',
      from: null,
      to: null,
      label: 'Дополнительное поле',
      valueType: 'text',
      displayMode: 'changed_only',
    });
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'custom_data.directorField',
      label: 'Дополнительное поле',
      before: null,
      after: null,
    });
  });

  it('keeps contact-list count safety when stored hints claim text values', () => {
    const input = {
      field: 'custom_data.contactPersons',
      from: '[]',
      to: '[{"name":"Анна","phone":"+79991234567"}]',
      label: 'Контактные лица',
      valueType: 'text' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toMatchObject({
      from: 0,
      to: 1,
      valueType: 'contact_list',
      displayMode: 'count',
    });
    expect(presentAuditFieldChange(input)).toMatchObject({
      before: 'Контактных лиц: 0',
      after: 'Контактных лиц: 1',
    });
  });

  it('ignores a partial reference display snapshot', () => {
    const input = {
      field: 'assigned_to',
      from: null,
      to: 'Наталия Назарова',
      displayMode: 'values' as const,
    };

    expect(presentAuditFieldChange(input)).toEqual({
      key: 'assigned_to',
      label: 'Ответственный',
      before: null,
      after: null,
    });
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
  ])('does not treat unsafe reference value %s as a display name', (value) => {
    const input = {
      field: 'assigned_to',
      from: null,
      to: value,
      label: 'Ответственный',
      valueType: 'reference' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toMatchObject({
      from: null,
      to: null,
      displayMode: 'changed_only',
    });
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'assigned_to',
      label: 'Ответственный',
      before: null,
      after: null,
    });
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
    'fingerprint:device-session-42',
  ])('suppresses unsafe unknown text value %s before storage', (value) => {
    const input = { field: 'owner', from: null, to: value };

    expect(createSafeAuditChange(input)).toEqual({
      field: 'owner',
      from: null,
      to: null,
      label: 'Дополнительное поле',
      valueType: 'text',
      displayMode: 'changed_only',
    });
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
    'fingerprint:device-session-42',
  ])('suppresses unsafe unknown text value %s during presentation', (value) => {
    const input = { field: 'owner', from: null, to: value };

    expect(presentAuditFieldChange(input)).toEqual({
      key: 'owner',
      label: 'Дополнительное поле',
      before: null,
      after: null,
    });
    expect(JSON.stringify(presentAuditFieldChange(input))).not.toContain(value);
  });

  it.each([
    '550e8400-e29b-41d4-a716-446655440000',
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sessionId-550e8400-e29b-41d4-a716-446655440000',
  ])('keeps known reference safety despite a malicious text snapshot %s', (value) => {
    const input = {
      field: 'assigned_to',
      from: null,
      to: value,
      label: 'Ответственный',
      valueType: 'text' as const,
      displayMode: 'values' as const,
    };

    expect(createSafeAuditChange(input)).toMatchObject({
      from: null,
      to: null,
      valueType: 'reference',
      displayMode: 'changed_only',
    });
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'assigned_to',
      label: 'Ответственный',
      before: null,
      after: null,
    });
  });

  it('preserves JSON-looking primitive list items exactly', () => {
    const input = {
      field: 'custom_data.disciplines',
      from: null,
      to: ['{director-defined value}', '[director-defined value]', 'PIANO'],
    };

    expect(createSafeAuditChange(input)).toMatchObject({
      to: ['{director-defined value}', '[director-defined value]', 'PIANO'],
      valueType: 'list',
      displayMode: 'values',
    });
    expect(presentAuditFieldChange(input)).toEqual({
      key: 'custom_data.disciplines',
      label: 'Направления',
      before: null,
      after: '{director-defined value}, [director-defined value], PIANO',
    });
  });

  it.each([
    '2026-08-31T17:21:99+03:00',
    '2026-08-31T17:21:00+99:99',
  ])('preserves invalid ISO date-time %s without localized formatting', (value) => {
    expect(presentAuditFieldChange({
      field: 'custom_data.visitDateTime',
      from: null,
      to: value,
    })?.after).toBe(value);
  });

  it('fails closed for malformed structured values', () => {
    expect(presentAuditFieldChange({
      field: 'custom_data.disciplines',
      from: '{bad json',
      to: '[{"internal":"value"}]',
    })).toEqual({
      key: 'custom_data.disciplines',
      label: 'Направления',
      before: null,
      after: null,
    });
  });

  it('stores contact people only as safe counts', () => {
    const change = createSafeAuditChange({
      field: 'custom_data.contactPersons',
      from: [],
      to: [{ name: 'Анна', phone: '+79991234567' }],
    });

    expect(change).toEqual({
      field: 'custom_data.contactPersons',
      from: 0,
      to: 1,
      label: 'Контактные лица',
      valueType: 'contact_list',
      displayMode: 'count',
    });
    expect(JSON.stringify(change)).not.toContain('+79991234567');
  });
});
