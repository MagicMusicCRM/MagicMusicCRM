import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { GoogleOAuthService } from './google-oauth.service';
import { SessionService } from './session.service';

describe('GoogleOAuthService', () => {
  let query: jest.Mock;
  let transaction: jest.Mock;
  let sessions: { issueForUser: jest.Mock };
  let audit: { record: jest.Mock };
  let googleClient: { generateAuthUrl: jest.Mock; verifyIdToken: jest.Mock };
  let service: GoogleOAuthService;
  let fetchSpy: jest.SpiedFunction<typeof fetch>;

  const config = {
    get: jest.fn((key: string) => {
      const values: Record<string, string> = {
        GOOGLE_OAUTH_CLIENT_ID: 'google-client-id',
        GOOGLE_OAUTH_CLIENT_SECRET: 'google-client-secret',
        GOOGLE_OAUTH_REDIRECT_URI: 'https://api.example.com/auth/google/callback'
      };
      return values[key];
    }),
    getOrThrow: jest.fn((key: string) => {
      const values: Record<string, string> = {
        GOOGLE_OAUTH_CLIENT_ID: 'google-client-id',
        GOOGLE_OAUTH_CLIENT_SECRET: 'google-client-secret'
      };
      return values[key];
    })
  } as unknown as ConfigService;

  beforeEach(() => {
    query = jest.fn();
    transaction = jest.fn();
    sessions = {
      issueForUser: jest.fn().mockResolvedValue({
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'Bearer',
        expiresIn: 900
      })
    };
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    googleClient = {
      generateAuthUrl: jest.fn().mockReturnValue('https://accounts.google.com/o/oauth2/v2/auth'),
      verifyIdToken: jest.fn().mockResolvedValue({
        getPayload: () => ({
          sub: 'google-user-a',
          email: 'user@example.com',
          email_verified: true,
          name: 'User Example'
        })
      })
    };
    fetchSpy = jest.spyOn(global, 'fetch').mockResolvedValue({
      ok: true,
      json: async () => ({ id_token: 'google-id-token' })
    } as Response);

    service = new GoogleOAuthService(
      { query, transaction } as unknown as DatabaseService,
      config,
      sessions as unknown as SessionService,
      audit as unknown as AuditService,
      googleClient as unknown as OAuth2Client
    );
  });

  afterEach(() => {
    fetchSpy.mockRestore();
    jest.clearAllMocks();
  });

  it('creates one-time OAuth state and authorization URL', async () => {
    query.mockResolvedValueOnce({ rows: [] });

    const result = await service.start();

    expect(result.state.length).toBeGreaterThan(32);
    expect(result.authorizationUrl).toContain('accounts.google.com');
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('insert into app.oauth_states'),
      expect.arrayContaining(['https://api.example.com/auth/google/callback'])
    );
    expect(googleClient.generateAuthUrl).toHaveBeenCalledWith(
      expect.objectContaining({
        client_id: 'google-client-id',
        redirect_uri: 'https://api.example.com/auth/google/callback',
        scope: ['openid', 'email', 'profile']
      })
    );
  });

  it('exchanges callback and issues v3 session for linked identity', async () => {
    query.mockResolvedValueOnce({
      rows: [
        {
          id: 'state-a',
          redirect_uri: 'https://api.example.com/auth/google/callback'
        }
      ]
    });
    transaction.mockImplementation(async (work) =>
      work({
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              id: 'user-a',
              email: 'user@example.com',
              role: 'client',
              email_verified_at: new Date()
            }
          ]
        })
      })
    );

    const result = await service.callback('google-code', 'valid-state');

    expect(fetchSpy).toHaveBeenCalledWith(
      'https://oauth2.googleapis.com/token',
      expect.objectContaining({ method: 'POST' })
    );
    expect(googleClient.verifyIdToken).toHaveBeenCalledWith({
      idToken: 'google-id-token',
      audience: 'google-client-id'
    });
    expect(result.session.refreshToken).toBe('refresh-token');
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'auth.google_oauth_login' })
    );
  });

  it('verifies native mobile id token and issues v3 session', async () => {
    transaction.mockImplementation(async (work) =>
      work({
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              id: 'user-a',
              email: 'user@example.com',
              role: 'client',
              email_verified_at: new Date()
            }
          ]
        })
      })
    );

    const result = await service.idToken('native-google-id-token');

    expect(fetchSpy).not.toHaveBeenCalled();
    expect(googleClient.verifyIdToken).toHaveBeenCalledWith({
      idToken: 'native-google-id-token',
      audience: 'google-client-id'
    });
    expect(result.session.accessToken).toBe('access-token');
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'auth.google_id_token_login' })
    );
  });

  it('links native Google id token to current authenticated user', async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          {
            id: 'user-a',
            email: 'user@example.com',
            role: 'client',
            email_verified_at: null
          }
        ]
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] });
    transaction.mockImplementation(async (work) => work({ query: clientQuery }));

    const result = await service.linkIdToken(
      { userId: 'user-a', role: 'client' },
      'native-google-id-token'
    );

    expect(result).toEqual({ linked: true });
    expect(googleClient.verifyIdToken).toHaveBeenCalledWith({
      idToken: 'native-google-id-token',
      audience: 'google-client-id'
    });
    expect(clientQuery).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('insert into app.user_identities'),
      expect.arrayContaining(['user-a', 'google-user-a', 'user@example.com'])
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'auth.google_identity_linked' })
    );
    expect(sessions.issueForUser).not.toHaveBeenCalled();
  });

  it('rejects Google linking when email differs from current user', async () => {
    transaction.mockImplementation(async (work) =>
      work({
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              id: 'user-a',
              email: 'other@example.com',
              role: 'client',
              email_verified_at: null
            }
          ]
        })
      })
    );

    await expect(
      service.linkIdToken(
        { userId: 'user-a', role: 'client' },
        'native-google-id-token'
      )
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects invalid or consumed OAuth state before token exchange', async () => {
    query.mockResolvedValueOnce({ rows: [] });

    await expect(service.callback('google-code', 'bad-state')).rejects.toThrow(
      UnauthorizedException
    );
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('rejects Google payloads without verified email', async () => {
    query.mockResolvedValueOnce({
      rows: [
        {
          id: 'state-a',
          redirect_uri: 'https://api.example.com/auth/google/callback'
        }
      ]
    });
    googleClient.verifyIdToken.mockResolvedValueOnce({
      getPayload: () => ({
        sub: 'google-user-a',
        email: 'user@example.com',
        email_verified: false
      })
    });

    await expect(service.callback('google-code', 'valid-state')).rejects.toThrow(
      UnauthorizedException
    );
    expect(sessions.issueForUser).not.toHaveBeenCalled();
  });
});
