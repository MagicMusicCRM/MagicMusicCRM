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
});
