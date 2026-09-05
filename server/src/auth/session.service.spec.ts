import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { UnauthorizedException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { SessionService } from "./session.service";

function config() {
  return {
    get: jest.fn((key: string, fallback?: unknown) => {
      const values: Record<string, unknown> = {
        JWT_ACCESS_SECRET: "test-secret-test-secret-test-secret-123",
        ACCESS_TOKEN_TTL_SECONDS: 900,
        REFRESH_TOKEN_TTL_DAYS: 30,
      };
      return values[key] ?? fallback;
    }),
    getOrThrow: jest.fn((key: string) => {
      if (key === "JWT_ACCESS_SECRET") {
        return "test-secret-test-secret-test-secret-123";
      }
      throw new Error(`Missing ${key}`);
    }),
  } as unknown as ConfigService;
}

describe("SessionService", () => {
  let query: jest.Mock;
  let transaction: jest.Mock;
  let audit: { record: jest.Mock };
  let service: SessionService;

  beforeEach(() => {
    query = jest.fn();
    transaction = jest.fn(async (work) => work({ query }));
    audit = { record: jest.fn().mockResolvedValue(undefined) };
    service = new SessionService(
      { query, transaction } as unknown as DatabaseService,
      new JwtService(),
      config(),
      audit as unknown as AuditService,
    );
  });

  it("issues access and refresh tokens", async () => {
    query.mockResolvedValueOnce({ rows: [] });

    const tokens = await service.issueForUser({
      id: "user-a",
      email: "user@example.com",
      role: "client",
    });

    expect(tokens.tokenType).toBe("Bearer");
    expect(tokens.accessToken).toBeTruthy();
    expect(tokens.refreshToken).toBeTruthy();
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("rotates a valid refresh token", async () => {
    query.mockResolvedValueOnce({ rows: [] }).mockResolvedValueOnce({
      rows: [
        {
          id: "session-a",
          user_id: "user-a",
          family_id: "family-a",
          expires_at: new Date(Date.now() + 60_000).toISOString(),
          revoked_at: null,
          replaced_by_id: null,
          email: "user@example.com",
          role: "client",
        },
      ],
    });
    query
      .mockResolvedValueOnce({ rows: [{ id: "session-b" }] })
      .mockResolvedValueOnce({ rows: [] });

    const tokens = await service.rotate("valid-refresh-token");

    expect(tokens.accessToken).toBeTruthy();
    expect(tokens.refreshToken).not.toBe("valid-refresh-token");
    expect(transaction).toHaveBeenCalledTimes(1);
  });

  it("revokes session family when reuse is detected", async () => {
    query
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "session-a",
            user_id: "user-a",
            family_id: "family-a",
            expires_at: new Date(Date.now() + 60_000).toISOString(),
            revoked_at: new Date().toISOString(),
            replaced_by_id: "session-b",
            email: "user@example.com",
            role: "client",
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] });

    await expect(service.rotate("reused-token")).rejects.toThrow(
      UnauthorizedException,
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("where family_id"),
      ["family-a"],
    );
  });

  it("revokes all user sessions", async () => {
    query.mockResolvedValueOnce({ rows: [] });

    await service.revokeAll({ userId: "user-a", role: "client" });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("where user_id"),
      ["user-a"],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "auth.logout_all" }),
    );
  });
});
