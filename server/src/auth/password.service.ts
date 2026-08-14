import { Injectable, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const keyLength = 64;
const GCM_IV_LENGTH = 12;
const GCM_TAG_LENGTH = 16;

@Injectable()
export class PasswordService {
  constructor(@Optional() private readonly config?: ConfigService) {}

  async hash(password: string): Promise<string> {
    const salt = randomBytes(16).toString('hex');
    const derived = (await scrypt(password, salt, keyLength)) as Buffer;
    return `scrypt$${salt}$${derived.toString('hex')}`;
  }

  async verify(password: string, storedHash: string): Promise<boolean> {
    const [algorithm, salt, hash] = storedHash.split('$');
    if (algorithm !== 'scrypt' || !salt || !hash) return false;

    const expected = Buffer.from(hash, 'hex');
    const actual = (await scrypt(password, salt, expected.length)) as Buffer;
    if (actual.length !== expected.length) return false;

    return timingSafeEqual(actual, expected);
  }

  /**
   * Keeps an authenticated encrypted copy only for owner-managed staff access.
   * Authentication always continues to use the one-way scrypt hash above.
   */
  encryptForManagedAccess(password: string): string | null {
    const key = this.managedAccessKey();
    if (!key) return null;

    const iv = randomBytes(GCM_IV_LENGTH);
    const cipher = createCipheriv('aes-256-gcm', key, iv, {
      authTagLength: GCM_TAG_LENGTH,
    });
    const encrypted = Buffer.concat([
      cipher.update(password, 'utf8'),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return [
      'v1',
      iv.toString('base64url'),
      tag.toString('base64url'),
      encrypted.toString('base64url'),
    ].join(':');
  }

  decryptForManagedAccess(ciphertext: string | null | undefined): string | null {
    if (!ciphertext?.startsWith('v1:')) return null;
    const key = this.managedAccessKey();
    if (!key) return null;

    const parts = ciphertext.split(':');
    if (parts.length !== 4) return null;
    try {
      const iv = Buffer.from(parts[1], 'base64url');
      const tag = Buffer.from(parts[2], 'base64url');
      const encrypted = Buffer.from(parts[3], 'base64url');
      if (iv.length !== GCM_IV_LENGTH || tag.length !== GCM_TAG_LENGTH) {
        return null;
      }
      const decipher = createDecipheriv('aes-256-gcm', key, iv, {
        authTagLength: GCM_TAG_LENGTH,
      });
      decipher.setAuthTag(tag);
      return Buffer.concat([
        decipher.update(encrypted),
        decipher.final(),
      ]).toString('utf8');
    } catch {
      return null;
    }
  }

  private managedAccessKey(): Buffer | null {
    const secret = this.config
      ?.get<string>('MANAGED_PASSWORD_ENCRYPTION_KEY', '')
      .trim();
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
