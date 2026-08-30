import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import {
  ResendEmailProvider,
  SmtpFallbackEmailProvider,
} from "./notification-email.provider";
import { FirebasePushProvider } from "./notification-push.provider";
import { NotificationTokenCrypto } from "./notification-token-crypto.service";
import { NotificationWorker } from "./notification-worker.service";

describe("NotificationWorker", () => {
  it("renders student invitations with Android install and iOS availability actions", async () => {
    const previousAndroid = process.env.CLIENT_ANDROID_INSTALL_URL;
    const previousIos = process.env.CLIENT_IOS_INSTALL_URL;
    process.env.CLIENT_ANDROID_INSTALL_URL =
      "https://play.google.com/store/apps/details?id=magic.crm";
    process.env.CLIENT_IOS_INSTALL_URL = "";
    const query = jest
      .fn()
      .mockResolvedValueOnce({ rows: [{ id: "invite-a" }] })
      .mockResolvedValueOnce({
        rows: [
          {
            id: "invite-a",
            user_id: "user-a",
            email: "student@example.com",
            template: "student_invite",
            attempt_count: 0,
            payload: {
              title: "Приглашение в Magic Music",
              body: "Установите приложение и зарегистрируйтесь.",
            },
          },
        ],
      })
      .mockResolvedValue({ rows: [] });
    const resend = {
      send: jest.fn().mockResolvedValue({ provider: "resend", status: "sent" }),
    };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      { record: jest.fn() } as unknown as AuditService,
      resend as unknown as ResendEmailProvider,
      { send: jest.fn() } as unknown as SmtpFallbackEmailProvider,
      { decrypt: jest.fn() } as unknown as NotificationTokenCrypto,
      { send: jest.fn() } as unknown as FirebasePushProvider,
    );

    try {
      await expect(worker.dispatchPendingEmails()).resolves.toEqual({
        processed: 1,
        failed: 0,
      });

      expect(resend.send).toHaveBeenCalledWith(
        expect.objectContaining({
          text: expect.stringContaining(
            "https://play.google.com/store/apps/details?id=magic.crm",
          ),
          html: expect.stringMatching(
            /Установить на Android[\s\S]*iOS — скоро в App Store/,
          ),
        }),
      );
      expect(query.mock.calls[1]?.[0]).toContain("student.contact_email");
    } finally {
      if (previousAndroid === undefined)
        delete process.env.CLIENT_ANDROID_INSTALL_URL;
      else process.env.CLIENT_ANDROID_INSTALL_URL = previousAndroid;
      if (previousIos === undefined) delete process.env.CLIENT_IOS_INSTALL_URL;
      else process.env.CLIENT_IOS_INSTALL_URL = previousIos;
    }
  });

  it("falls back to SMTP when primary email provider fails", async () => {
    const query = jest
      .fn()
      // candidate ids
      .mockResolvedValueOnce({ rows: [{ id: "outbox-a" }] })
      // claim returns the full outbox row
      .mockResolvedValueOnce({
        rows: [
          {
            id: "outbox-a",
            user_id: "user-a",
            email: "user@example.com",
            template: "admin_broadcast",
            attempt_count: 0,
            payload: {
              notificationId: "notification-a",
              title: "Title",
              body: "Body",
            },
          },
        ],
      })
      .mockResolvedValue({ rows: [] });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const resend = {
      send: jest.fn().mockResolvedValue({
        provider: "resend",
        status: "failed",
        error: "status_500",
      }),
    };
    const smtp = {
      send: jest
        .fn()
        .mockResolvedValue({ provider: "smtp_fallback", status: "sent" }),
    };
    const tokenCrypto = { decrypt: jest.fn() };
    const pushProvider = { send: jest.fn() };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      resend as unknown as ResendEmailProvider,
      smtp as unknown as SmtpFallbackEmailProvider,
      tokenCrypto as unknown as NotificationTokenCrypto,
      pushProvider as unknown as FirebasePushProvider,
    );

    await expect(worker.dispatchPendingEmails()).resolves.toEqual({
      processed: 1,
      failed: 0,
    });

    expect(resend.send).toHaveBeenCalledTimes(1);
    expect(smtp.send).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("update app.email_outbox"),
      ["outbox-a"],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "notifications.email_delivery_attempted",
        metadata: { provider: "smtp_fallback", status: "sent" },
      }),
    );
  });

  it("marks outbox failed and audits when both email providers fail", async () => {
    const query = jest
      .fn()
      // candidate ids
      .mockResolvedValueOnce({ rows: [{ id: "outbox-a" }] })
      // claim returns the full outbox row
      .mockResolvedValueOnce({
        rows: [
          {
            id: "outbox-a",
            user_id: "user-a",
            email: "user@example.com",
            template: "auth_otp",
            attempt_count: 4,
            payload: {
              title: "Title",
              body: "Body",
            },
          },
        ],
      })
      .mockResolvedValue({ rows: [] });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const resend = {
      send: jest.fn().mockResolvedValue({
        provider: "resend",
        status: "failed",
        error: "timeout",
      }),
    };
    const smtp = {
      send: jest.fn().mockResolvedValue({
        provider: "smtp_fallback",
        status: "failed",
        error: "smtp_timeout",
      }),
    };
    const tokenCrypto = { decrypt: jest.fn() };
    const pushProvider = { send: jest.fn() };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      resend as unknown as ResendEmailProvider,
      smtp as unknown as SmtpFallbackEmailProvider,
      tokenCrypto as unknown as NotificationTokenCrypto,
      pushProvider as unknown as FirebasePushProvider,
    );

    await expect(worker.dispatchPendingEmails()).resolves.toEqual({
      processed: 1,
      failed: 1,
    });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("update app.email_outbox"),
      ["outbox-a", "resend:timeout|smtp_fallback:smtp_timeout", null],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "notifications.email_outbox_failed",
        entityType: "email_outbox",
        entityId: "outbox-a",
        metadata: expect.objectContaining({
          template: "auth_otp",
          primaryStatus: "failed",
          fallbackStatus: "failed",
        }),
      }),
    );
  });

  it("keeps transient email failures retryable with backoff before final failure", async () => {
    const query = jest
      .fn()
      // candidate ids
      .mockResolvedValueOnce({ rows: [{ id: "outbox-a" }] })
      // claim returns the full outbox row
      .mockResolvedValueOnce({
        rows: [
          {
            id: "outbox-a",
            user_id: "user-a",
            email: "user@example.com",
            template: "auth_otp",
            attempt_count: 1,
            payload: {
              title: "Title",
              body: "Body",
            },
          },
        ],
      })
      .mockResolvedValue({ rows: [] });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const resend = {
      send: jest.fn().mockResolvedValue({
        provider: "resend",
        status: "failed",
        error: "timeout",
      }),
    };
    const smtp = {
      send: jest.fn().mockResolvedValue({
        provider: "smtp_fallback",
        status: "failed",
        error: "smtp_timeout",
      }),
    };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      resend as unknown as ResendEmailProvider,
      smtp as unknown as SmtpFallbackEmailProvider,
      { decrypt: jest.fn() } as unknown as NotificationTokenCrypto,
      { send: jest.fn() } as unknown as FirebasePushProvider,
    );

    await expect(worker.dispatchPendingEmails()).resolves.toEqual({
      processed: 1,
      failed: 1,
    });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("eo.attempt_count < $2"),
      [20, 5],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("update app.email_outbox"),
      ["outbox-a", "resend:timeout|smtp_fallback:smtp_timeout", "2 minutes"],
    );
    expect(audit.record).not.toHaveBeenCalledWith(
      expect.objectContaining({ action: "notifications.email_outbox_failed" }),
    );
  });

  it("sends queued push delivery to enabled devices", async () => {
    const query = jest
      .fn()
      // candidate ids
      .mockResolvedValueOnce({ rows: [{ id: "delivery-a" }] })
      // claim returns the full delivery row
      .mockResolvedValueOnce({
        rows: [
          {
            id: "delivery-a",
            notification_id: "notification-a",
            user_id: "user-a",
            title: "Title",
            body: "Body",
            data: { chatId: "chat-a" },
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "device-a", encrypted_token: "v1:encrypted" }],
      })
      .mockResolvedValue({ rows: [] });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const tokenCrypto = {
      decrypt: jest.fn().mockReturnValue("push-token-1234567890"),
    };
    const pushProvider = {
      send: jest
        .fn()
        .mockResolvedValue({ provider: "firebase", status: "sent" }),
    };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      { send: jest.fn() } as unknown as ResendEmailProvider,
      { send: jest.fn() } as unknown as SmtpFallbackEmailProvider,
      tokenCrypto as unknown as NotificationTokenCrypto,
      pushProvider as unknown as FirebasePushProvider,
    );

    await expect(worker.dispatchPendingPush()).resolves.toEqual({
      processed: 1,
      failed: 0,
    });

    expect(pushProvider.send).toHaveBeenCalledWith({
      token: "push-token-1234567890",
      title: "Title",
      body: "Body",
      data: { chatId: "chat-a" },
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("update app.notification_deliveries"),
      ["delivery-a", "firebase", "sent", null],
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "notifications.push_delivery_attempted",
        metadata: {
          provider: "firebase",
          status: "sent",
          deviceId: "device-a",
        },
      }),
    );
  });

  it("skips queued push delivery when token cannot be decrypted", async () => {
    const query = jest
      .fn()
      // candidate ids
      .mockResolvedValueOnce({ rows: [{ id: "delivery-a" }] })
      // claim returns the full delivery row
      .mockResolvedValueOnce({
        rows: [
          {
            id: "delivery-a",
            notification_id: "notification-a",
            user_id: "user-a",
            title: "Title",
            body: "Body",
            data: {},
          },
        ],
      })
      .mockResolvedValueOnce({
        rows: [{ id: "device-a", encrypted_token: "sha256:abc" }],
      })
      .mockResolvedValue({ rows: [] });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const tokenCrypto = { decrypt: jest.fn().mockReturnValue(null) };
    const pushProvider = { send: jest.fn() };
    const worker = new NotificationWorker(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      { send: jest.fn() } as unknown as ResendEmailProvider,
      { send: jest.fn() } as unknown as SmtpFallbackEmailProvider,
      tokenCrypto as unknown as NotificationTokenCrypto,
      pushProvider as unknown as FirebasePushProvider,
    );

    await expect(worker.dispatchPendingPush()).resolves.toEqual({
      processed: 1,
      failed: 0,
    });

    expect(pushProvider.send).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("update app.notification_deliveries"),
      ["delivery-a", "firebase", "skipped", "missing_token_encryption_key"],
    );
  });
});
