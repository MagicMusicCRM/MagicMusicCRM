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
