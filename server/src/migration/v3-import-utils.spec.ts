import {
  deterministicUuid,
  directChatId,
  normalizeDeletionStatus,
  normalizeLegalDocumentType,
  normalizeMessageType,
  normalizeRole,
  sha256Hex,
  splitFullName
} from './v3-import-utils';

describe('v3 import utilities', () => {
  it('normalizes legacy roles to v3 enum values', () => {
    expect(normalizeRole('administrator')).toBe('admin');
    expect(normalizeRole('super_admin')).toBe('system_admin');
    expect(normalizeRole('staff')).toBe('manager');
    expect(normalizeRole('instructor')).toBe('teacher');
    expect(normalizeRole('unknown')).toBe('client');
  });

  it('normalizes constrained message and legal values', () => {
    expect(normalizeMessageType('audio')).toBe('voice');
    expect(normalizeMessageType('image')).toBe('file');
    expect(normalizeDeletionStatus('approved')).toBe('completed');
    expect(normalizeLegalDocumentType('terms')).toBe('terms_of_use');
  });

  it('builds deterministic uuid values for synthetic chats', () => {
    const first = deterministicUuid('namespace', 'key');
    const second = deterministicUuid('namespace', 'key');
    expect(first).toBe(second);
    expect(first).toMatch(/^[0-9a-f-]{36}$/);
    expect(directChatId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')).toBe(
      directChatId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
    );
  });

  it('splits legacy full names when first and last names are absent', () => {
    expect(splitFullName({ name: 'Иван Петров' })).toEqual({
      firstName: 'Иван',
      lastName: 'Петров'
    });
  });

  it('hashes secret-like device tokens instead of preserving raw values', () => {
    const token = 'fcm-token-secret';
    const hash = sha256Hex(token);
    expect(hash).toHaveLength(64);
    expect(hash).not.toContain(token);
  });
});
