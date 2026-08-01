import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

const GCM_IV_LENGTH = 12;
const GCM_TAG_LENGTH = 16;

@Injectable()
export class NotificationTokenCrypto {
  constructor(private readonly config: ConfigService) {}

  hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  encrypt(token: string): string {
    const key = this.key();
    if (!key) return `sha256:${this.hash(token)}`;

    const iv = randomBytes(GCM_IV_LENGTH);
    const cipher = createCipheriv('aes-256-gcm', key, iv, {
      authTagLength: GCM_TAG_LENGTH
    });
    const encrypted = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [
      'v1',
      iv.toString('base64url'),
      tag.toString('base64url'),
      encrypted.toString('base64url')
    ].join(':');
  }

  decrypt(encryptedToken: string | null | undefined): string | null {
    if (!encryptedToken?.startsWith('v1:')) return null;
    const key = this.key();
    if (!key) return null;

    const parts = encryptedToken.split(':');
    if (parts.length !== 4) return null;
    try {
      const iv = Buffer.from(parts[1], 'base64url');
      const tag = Buffer.from(parts[2], 'base64url');
      const encrypted = Buffer.from(parts[3], 'base64url');
      if (iv.length !== GCM_IV_LENGTH || tag.length !== GCM_TAG_LENGTH) return null;
      const decipher = createDecipheriv('aes-256-gcm', key, iv, {
        authTagLength: GCM_TAG_LENGTH
      });
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString('utf8');
    } catch {
      return null;
    }
  }

  private key(): Buffer | null {
    const secret = this.config.get<string>('NOTIFICATION_TOKEN_ENCRYPTION_KEY', '').trim();
    if (!secret) return null;

    if (/^[a-f0-9]{64}$/i.test(secret)) return Buffer.from(secret, 'hex');

    const base64 = Buffer.from(secret, 'base64');
    if (base64.length === 32) return base64;

    if (Buffer.byteLength(secret, 'utf8') >= 32) {
      return createHash('sha256').update(secret).digest();
    }

    return null;
  }
}
