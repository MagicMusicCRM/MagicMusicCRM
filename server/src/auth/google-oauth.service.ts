import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client, TokenPayload } from 'google-auth-library';
import { createHash, randomBytes } from 'node:crypto';
import { AuditService } from '../audit/audit.service';
import { ActorContext, UserRole } from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';
import { AuthUserResponse } from './auth.service';
import { GOOGLE_OAUTH_CLIENT } from './google-oauth.provider';
import { SessionService, TokenPair } from './session.service';

interface UserRecord {
  id: string;
  email: string;
  role: UserRole;
  email_verified_at: Date | string | null;
}

interface OAuthStateRecord {
  id: string;
  redirect_uri: string;
}

interface GoogleTokenResponse {
  id_token?: string;
  error?: string;
}

export interface GoogleOAuthStartResponse {
  authorizationUrl: string;
  state: string;
}

@Injectable()
export class GoogleOAuthService {
  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService,
    private readonly sessions: SessionService,
    private readonly audit: AuditService,
    @Inject(GOOGLE_OAUTH_CLIENT)
    private readonly googleClient: OAuth2Client
  ) {}

  async start(redirectUriInput?: string): Promise<GoogleOAuthStartResponse> {
    const { clientId, redirectUri } = this.oauthConfig(redirectUriInput);
    const state = randomBytes(32).toString('base64url');

    await this.database.query(
      `
        insert into app.oauth_states (provider, state_hash, redirect_uri, expires_at)
        values ('google', $1, $2, now() + interval '10 minutes')
      `,
      [this.tokenHash(state), redirectUri]
    );

    return {
      state,
      authorizationUrl: this.googleClient.generateAuthUrl({
        access_type: 'offline',
        prompt: 'select_account',
        response_type: 'code',
        client_id: clientId,
        redirect_uri: redirectUri,
        scope: ['openid', 'email', 'profile'],
        state
      })
    };
  }

  async callback(
    code: string,
    state: string,
    redirectUriInput?: string
  ): Promise<{ user: AuthUserResponse; session: TokenPair }> {
    const { clientId, redirectUri } = this.oauthConfig(redirectUriInput);
    const oauthState = await this.consumeState(state);
    if (oauthState.redirect_uri !== redirectUri) {
      throw new UnauthorizedException('OAuth state недействителен.');
    }

    const idToken = await this.exchangeCodeForIdToken(code, redirectUri);
    const payload = await this.verifyIdToken(idToken, clientId);
    const user = await this.upsertIdentity(payload);

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: 'auth.google_oauth_login',
      entityType: 'user',
      entityId: user.id,
      metadata: { emailHash: this.emailHash(user.email) }
    });

    return {
      user: this.toResponse(user),
      session: await this.sessions.issueForUser(user)
    };
  }

  async idToken(
    idToken: string
  ): Promise<{ user: AuthUserResponse; session: TokenPair }> {
    const clientId = this.config.get<string>('GOOGLE_OAUTH_CLIENT_ID');
    if (!clientId) {
      throw new BadRequestException('Google OAuth не настроен.');
    }

    const payload = await this.verifyIdToken(idToken, clientId);
    const user = await this.upsertIdentity(payload);

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: 'auth.google_id_token_login',
      entityType: 'user',
      entityId: user.id,
      metadata: { emailHash: this.emailHash(user.email) }
    });

    return {
      user: this.toResponse(user),
      session: await this.sessions.issueForUser(user)
    };
  }

  async linkIdToken(
    actor: ActorContext,
    idToken: string
  ): Promise<{ linked: true }> {
    const clientId = this.config.get<string>('GOOGLE_OAUTH_CLIENT_ID');
    if (!clientId) {
      throw new BadRequestException('Google OAuth не настроен.');
    }

    const payload = await this.verifyIdToken(idToken, clientId);
    await this.linkIdentity(actor, payload);

    await this.audit.record({
      actor,
      action: 'auth.google_identity_linked',
      entityType: 'user',
      entityId: actor.userId,
      metadata: { emailHash: this.emailHash(payload.email!.trim().toLowerCase()) }
    });

    return { linked: true };
  }

  private oauthConfig(redirectUriInput?: string) {
    const clientId = this.config.get<string>('GOOGLE_OAUTH_CLIENT_ID');
    const clientSecret = this.config.get<string>('GOOGLE_OAUTH_CLIENT_SECRET');
    const redirectUri =
      redirectUriInput ?? this.config.get<string>('GOOGLE_OAUTH_REDIRECT_URI');

    if (!clientId || !clientSecret || !redirectUri) {
      throw new BadRequestException('Google OAuth не настроен.');
    }

    return { clientId, clientSecret, redirectUri };
  }

  private async consumeState(state: string): Promise<OAuthStateRecord> {
    const result = await this.database.query<OAuthStateRecord>(
      `
        update app.oauth_states
        set consumed_at = now()
        where provider = 'google'
          and state_hash = $1
          and consumed_at is null
          and expires_at > now()
        returning id, redirect_uri
      `,
      [this.tokenHash(state)]
    );

    const record = result.rows[0];
    if (!record) throw new UnauthorizedException('OAuth state недействителен.');
    return record;
  }

  private async exchangeCodeForIdToken(
    code: string,
    redirectUri: string
  ): Promise<string> {
    const clientId = this.config.getOrThrow<string>('GOOGLE_OAUTH_CLIENT_ID');
    const clientSecret = this.config.getOrThrow<string>(
      'GOOGLE_OAUTH_CLIENT_SECRET'
    );
    const response = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code'
      })
    });

    if (!response.ok) throw new UnauthorizedException('Google OAuth отклонен.');

    const body = (await response.json()) as GoogleTokenResponse;
    if (!body.id_token || body.error) {
      throw new UnauthorizedException('Google OAuth отклонен.');
    }

    return body.id_token;
  }

  private async verifyIdToken(
    idToken: string,
    clientId: string
  ): Promise<TokenPayload> {
    const ticket = await this.googleClient.verifyIdToken({
      idToken,
      audience: clientId
    });
    const payload = ticket.getPayload();

    if (!payload?.sub || !payload.email || payload.email_verified !== true) {
      throw new UnauthorizedException('Google аккаунт не подтвержден.');
    }

    return payload;
  }

  private async upsertIdentity(payload: TokenPayload): Promise<UserRecord> {
    const email = payload.email!.trim().toLowerCase();
    const providerUserId = payload.sub!;

    return this.database.transaction(async (client) => {
      const existingIdentity = await client.query<UserRecord>(
        `
          select u.id, u.email, u.role, u.email_verified_at
          from app.user_identities ui
          join app.users u on u.id = ui.user_id
          where ui.provider = 'google'
            and ui.provider_user_id = $1
            and u.deleted_at is null
          limit 1
        `,
        [providerUserId]
      );

      if (existingIdentity.rows[0]) return existingIdentity.rows[0];

      const existingUser = await client.query<UserRecord>(
        `
          select id, email, role, email_verified_at
          from app.users
          where lower(email) = lower($1)
            and deleted_at is null
          limit 1
        `,
        [email]
      );

      const user =
        existingUser.rows[0] ??
        (
          await client.query<UserRecord>(
            `
              insert into app.users (email, full_name, role, email_verified_at, is_app_account)
              values ($1, $2, 'client', now(), true)
              returning id, email, role, email_verified_at
            `,
            [email, payload.name ?? null]
          )
        ).rows[0];

      const [firstName, lastName] = this.splitFullName(payload.name ?? '');
      await client.query(
        `
          insert into app.profiles (user_id, first_name, last_name)
          values ($1, $2, $3)
          on conflict (user_id) do nothing
        `,
        [user.id, firstName, lastName]
      );

      await client.query(
        `
          insert into app.user_identities (
            user_id,
            provider,
            provider_user_id,
            email,
            email_verified,
            raw_profile
          )
          values ($1, 'google', $2, $3, true, $4)
          on conflict (provider, provider_user_id) do nothing
        `,
        [user.id, providerUserId, email, JSON.stringify(payload)]
      );

      return user;
    });
  }

  private async linkIdentity(
    actor: ActorContext,
    payload: TokenPayload
  ): Promise<void> {
    const email = payload.email!.trim().toLowerCase();
    const providerUserId = payload.sub!;

    await this.database.transaction(async (client) => {
      const currentUser = await client.query<UserRecord>(
        `
          select id, email, role, email_verified_at
          from app.users
          where id = $1 and deleted_at is null
          limit 1
        `,
        [actor.userId]
      );
      const user = currentUser.rows[0];
      if (!user) throw new UnauthorizedException('Пользователь не найден.');
      if (user.email.trim().toLowerCase() !== email) {
        throw new ConflictException(
          'Google аккаунт должен использовать ту же почту, что и текущий пользователь.'
        );
      }

      const existingIdentity = await client.query<{ user_id: string }>(
        `
          select user_id
          from app.user_identities
          where provider = 'google'
            and provider_user_id = $1
          limit 1
        `,
        [providerUserId]
      );
      const ownerId = existingIdentity.rows[0]?.user_id;
      if (ownerId && ownerId !== actor.userId) {
        throw new ConflictException(
          'Этот Google аккаунт уже привязан к другому пользователю.'
        );
      }

      await client.query(
        `
          insert into app.user_identities (
            user_id,
            provider,
            provider_user_id,
            email,
            email_verified,
            raw_profile
          )
          values ($1, 'google', $2, $3, true, $4)
          on conflict (provider, provider_user_id)
          do update set
            email = excluded.email,
            email_verified = true,
            raw_profile = excluded.raw_profile
        `,
        [actor.userId, providerUserId, email, JSON.stringify(payload)]
      );

      await client.query(
        `
          update app.users
          set email_verified_at = coalesce(email_verified_at, now()),
              is_app_account = true,
              updated_at = now()
          where id = $1
        `,
        [actor.userId]
      );
    });
  }

  private tokenHash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private emailHash(email: string): string {
    return createHash('sha256').update(email).digest('hex');
  }

  private splitFullName(fullName: string): [string | null, string | null] {
    const parts = fullName.trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return [null, null];
    const [firstName, ...rest] = parts;
    return [firstName, rest.length > 0 ? rest.join(' ') : null];
  }

  private toResponse(user: UserRecord): AuthUserResponse {
    return {
      id: user.id,
      email: user.email,
      role: user.role,
      emailVerified: Boolean(user.email_verified_at)
    };
  }
}
