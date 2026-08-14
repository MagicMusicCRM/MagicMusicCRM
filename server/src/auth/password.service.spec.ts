import { ConfigService } from '@nestjs/config';
import { PasswordService } from './password.service';

describe('PasswordService', () => {
  const service = new PasswordService();

  it('verifies a valid password hash', async () => {
    const hash = await service.hash('strong-password-123');

    await expect(service.verify('strong-password-123', hash)).resolves.toBe(true);
  });

  it('rejects invalid password and malformed hash', async () => {
    const hash = await service.hash('strong-password-123');

    await expect(service.verify('wrong-password', hash)).resolves.toBe(false);
    await expect(service.verify('strong-password-123', 'bad-hash')).resolves.toBe(false);
  });

  it('encrypts and decrypts a managed password with authenticated encryption', () => {
    const managed = new PasswordService({
      get: jest.fn().mockReturnValue('managed-password-key-with-32-bytes-minimum'),
    } as unknown as ConfigService);

    const encrypted = managed.encryptForManagedAccess('staff-password-123');

    expect(encrypted).toMatch(/^v1:/);
    expect(encrypted).not.toContain('staff-password-123');
    expect(managed.decryptForManagedAccess(encrypted)).toBe('staff-password-123');
    expect(managed.decryptForManagedAccess(`${encrypted}tampered`)).toBeNull();
  });

  it('does not create a recoverable password without the dedicated key', () => {
    expect(service.encryptForManagedAccess('staff-password-123')).toBeNull();
    expect(service.decryptForManagedAccess('v1:a:b:c')).toBeNull();
  });
});
