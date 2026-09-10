import { randomBytes, createHash } from 'node:crypto';
import {
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { AuditService } from '../audit/audit.service';
import {
  ActorContext,
  JWT_AUDIENCE,
  JWT_ISSUER,
  UserRole
} from '../common/security/actor-context';
import { DatabaseService } from '../db/database.service';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  tokenType: 'Bearer';
  expiresIn: number;
}

interface SessionUser {
  id: string;
  email: string;
  role: UserRole;
}

interface RefreshSessionRecord {
  id: string;
  user_id: string;
  family_id: string;
  expires_at: Date | string;
  revoked_at: Date | string | null;
  replaced_by_id: string | null;
  email: string;
  role: UserRole;
}

@Injectable()
export class SessionService {
  constructor(
    private readonly database: DatabaseService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly audit: AuditService
  ) {}

  async issueForUser(user: SessionUser): Promise<TokenPair> {
    const refreshToken = this.createOpaqueToken();
    await this.database.query(
      `
        insert into app.refresh_sessions (
          user_id,
          token_hash,
          family_id,
          expires_at
        )
        values ($1, $2, gen_random_uuid(), now() + ($3::text || ' days')::interval)
      `,
      [
        user.id,
        this.tokenHash(refreshToken),
        this.config.get<number>("REFRESH_TOKEN_TTL_DAYS", 30),
      ],
    );

    await this.audit.record({
      actor: { userId: user.id, role: user.role },
      action: "auth.session_issued",
      entityType: "user",
      entityId: user.id,
    });

    return {
      accessToken: await this.signAccessToken(user),
      refreshToken,
      tokenType: "Bearer",
      expiresIn: this.config.get<number>("ACCESS_TOKEN_TTL_SECONDS", 900),
    };
  }

  async rotate(refreshToken: string): Promise<TokenPair> {
    const tokenHash = this.tokenHash(refreshToken);
    const rotated = await this.database.transaction(async (client) => {
      // Serialize the whole family before reading revocation state. This also
      // avoids deadlocks between reuse detection and rotation of a successor.
      await client.query(
        "select pg_advisory_xact_lock(hashtextextended('auth-refresh:' || family_id::text, 0)) from app.refresh_sessions where token_hash = $1",
        [tokenHash],
      );
      const result = await client.query<RefreshSessionRecord>(
        `select rs.id, rs.user_id, rs.family_id, rs.expires_at,
          rs.revoked_at, rs.replaced_by_id, u.email, u.role
         from app.refresh_sessions rs join app.users u on u.id = rs.user_id
         where rs.token_hash = $1 and u.deleted_at is null
         for update of rs`,
        [tokenHash],
      );
      const session = result.rows[0];
      if (!session) return null;
      if (this.isInvalid(session)) {
        await client.query(
          "update app.refresh_sessions set revoked_at = coalesce(revoked_at, now()) where family_id = $1",
          [session.family_id],
        );
        await this.audit.record(
          {
            actor: { userId: session.user_id, role: session.role },
            action: "auth.refresh_reuse_detected",
            entityType: "refresh_session",
            entityId: session.id,
          },
          client,
        );
        // Throw only after commit, otherwise the family revocation rolls back.
        return null;
      }
      const nextRefreshToken = this.createOpaqueToken();
      const user = {
        id: session.user_id,
        email: session.email,
        role: session.role,
      };
      const accessToken = await this.signAccessToken(user);
      const inserted = await client.query<{ id: string }>(
        `insert into app.refresh_sessions(user_id, token_hash, family_id, expires_at)
         values($1, $2, $3, now() + ($4::text || ' days')::interval) returning id`,
        [
          user.id,
          this.tokenHash(nextRefreshToken),
          session.family_id,
          this.config.get<number>("REFRESH_TOKEN_TTL_DAYS", 30),
        ],
      );
      await client.query(
        "update app.refresh_sessions set revoked_at=now(), replaced_by_id=$2, last_used_at=now() where id=$1",
        [session.id, inserted.rows[0].id],
      );
      await this.audit.record(
        {
          actor: { userId: user.id, role: user.role },
          action: "auth.session_rotated",
          entityType: "refresh_session",
          entityId: session.id,
        },
        client,
      );
      return {
        accessToken,
        refreshToken: nextRefreshToken,
        tokenType: "Bearer" as const,
        expiresIn: this.config.get<number>("ACCESS_TOKEN_TTL_SECONDS", 900),
      };
    });
    if (!rotated) throw new UnauthorizedException("Сессия недействительна.");
    return rotated;
  }

  async revokeAll(actor: ActorContext): Promise<void> {
    await this.database.query(
      `
        update app.refresh_sessions
        set revoked_at = coalesce(revoked_at, now())
        where user_id = $1
          and revoked_at is null
      `,
      [actor.userId],
    );

    await this.audit.record({
      actor,
      action: "auth.logout_all",
      entityType: "user",
      entityId: actor.userId,
    });
  }

  private isInvalid(session: RefreshSessionRecord): boolean {
    return (
      Boolean(session.revoked_at) ||
      Boolean(session.replaced_by_id) ||
      new Date(session.expires_at).getTime() <= Date.now()
    );
  }

  private async signAccessToken(user: SessionUser): Promise<string> {
    return this.jwt.signAsync(
      {
        sub: user.id,
        role: user.role
      },
      {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        expiresIn: this.config.get<number>('ACCESS_TOKEN_TTL_SECONDS', 900),
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
        algorithm: 'HS256'
      }
    );
  }

  private createOpaqueToken(): string {
    return randomBytes(48).toString('base64url');
  }

  private tokenHash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
