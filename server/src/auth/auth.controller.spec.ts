import { GoneException } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

describe('AuthController', () => {
  const controller = new AuthController({} as AuthService);

  it('keeps every Google sign-in and link endpoint explicitly disabled', async () => {
    await expect(controller.googleStart()).rejects.toThrow(GoneException);
    await expect(controller.googleCallback()).rejects.toThrow(GoneException);
    await expect(controller.googleIdToken()).rejects.toThrow(GoneException);
    await expect(controller.googleLinkIdToken({} as never)).rejects.toThrow(
      GoneException,
    );
  });
});
