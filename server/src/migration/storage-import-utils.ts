import { createHash } from 'node:crypto';

export interface LegacyFileMapEntry {
  id: string;
  bucketId: string;
  name: string;
  storageKey: string;
  purpose: 'profile_avatar' | 'chat_attachment' | 'chat_voice' | 'legal_document' | 'crm_document';
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  sha256: string;
  legacyKeys: string[];
}

export function sanitizePathSegment(value: string): string {
  const sanitized = value
    .replace(/\\/g, '/')
    .split('/')
    .pop()
    ?.replace(/[\u0000-\u001f]/g, '')
    .replace(/[<>:"|?*]/g, '_')
    .trim()
    .slice(0, 180);
  return sanitized && sanitized.length > 0 ? sanitized : 'file';
}

export function inferMimeType(metadata: unknown, name: string): string {
  if (metadata && typeof metadata === 'object' && !Array.isArray(metadata)) {
    const record = metadata as Record<string, unknown>;
    for (const key of ['mimetype', 'mimeType', 'contentType', 'content-type']) {
      if (typeof record[key] === 'string' && record[key].trim().length > 0) {
        return record[key].trim();
      }
    }
  }
  const extension = name.split('.').pop()?.toLowerCase();
  const byExtension: Record<string, string> = {
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    webp: 'image/webp',
    pdf: 'application/pdf',
    txt: 'text/plain',
    mp3: 'audio/mpeg',
    m4a: 'audio/mp4',
    ogg: 'audio/ogg',
    webm: 'audio/webm',
    wav: 'audio/wav',
    mp4: 'video/mp4'
  };
  return extension ? (byExtension[extension] ?? 'application/octet-stream') : 'application/octet-stream';
}

export function inferSizeBytes(metadata: unknown, fallback: number): number {
  if (metadata && typeof metadata === 'object' && !Array.isArray(metadata)) {
    const record = metadata as Record<string, unknown>;
    for (const key of ['size', 'contentLength', 'content-length']) {
      const raw = record[key];
      if (typeof raw === 'number' && Number.isFinite(raw)) return raw;
      if (typeof raw === 'string' && raw.trim() !== '') {
        const parsed = Number(raw);
        if (Number.isFinite(parsed)) return parsed;
      }
    }
  }
  return fallback;
}

export function inferPurpose(bucketId: string, name: string, mimeType: string): LegacyFileMapEntry['purpose'] {
  if (bucketId === 'avatars') return 'profile_avatar';
  if (bucketId.includes('legal')) return 'legal_document';
  if (mimeType.startsWith('audio/') || name.toLowerCase().includes('voice')) return 'chat_voice';
  if (bucketId.includes('chat')) return 'chat_attachment';
  return 'crm_document';
}

export function buildLegacyStorageKey(bucketId: string, objectId: string, name: string): string {
  return `private/legacy/${sanitizePathSegment(bucketId)}/${objectId}/${sanitizePathSegment(name)}`;
}

export function sha256Buffer(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}

export function buildLegacyKeys(supabaseUrl: string, bucketId: string, name: string): string[] {
  const normalizedBase = supabaseUrl.replace(/\/+$/, '');
  const encodedPath = name.split('/').map(encodeURIComponent).join('/');
  return [
    `${bucketId}/${name}`,
    name,
    `${normalizedBase}/storage/v1/object/${bucketId}/${encodedPath}`,
    `${normalizedBase}/storage/v1/object/public/${bucketId}/${encodedPath}`
  ];
}
