import {
  buildLegacyKeys,
  buildLegacyStorageKey,
  inferMimeType,
  inferPurpose,
  sanitizePathSegment
} from './storage-import-utils';

describe('storage import utilities', () => {
  it('sanitizes untrusted path segments', () => {
    expect(sanitizePathSegment('../avatar<bad>.png')).toBe('avatar_bad_.png');
    expect(sanitizePathSegment('')).toBe('file');
  });

  it('infers mime type and purpose from legacy metadata', () => {
    expect(inferMimeType({ mimetype: 'image/webp' }, 'avatar.bin')).toBe('image/webp');
    expect(inferMimeType({}, 'voice.mp3')).toBe('audio/mpeg');
    expect(inferPurpose('avatars', 'photo.png', 'image/png')).toBe('profile_avatar');
    expect(inferPurpose('chat-attachments', 'voice-note', 'audio/ogg')).toBe('chat_voice');
  });

  it('builds local storage keys and legacy lookup aliases', () => {
    expect(buildLegacyStorageKey('chat-attachments', '11111111-1111-4111-8111-111111111111', 'a/b/file.pdf')).toBe(
      'private/legacy/chat-attachments/11111111-1111-4111-8111-111111111111/file.pdf'
    );
    expect(buildLegacyKeys('https://example.supabase.co/', 'avatars', 'u/a.png')).toContain(
      'https://example.supabase.co/storage/v1/object/avatars/u/a.png'
    );
  });
});
