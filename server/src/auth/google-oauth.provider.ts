import { Provider } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';

export const GOOGLE_OAUTH_CLIENT = Symbol('GOOGLE_OAUTH_CLIENT');

export const googleOAuthClientProvider: Provider = {
  provide: GOOGLE_OAUTH_CLIENT,
  inject: [ConfigService],
  useFactory: (config: ConfigService) =>
    new OAuth2Client(
      config.get<string>('GOOGLE_OAUTH_CLIENT_ID'),
      config.get<string>('GOOGLE_OAUTH_CLIENT_SECRET'),
      config.get<string>('GOOGLE_OAUTH_REDIRECT_URI')
    )
};
