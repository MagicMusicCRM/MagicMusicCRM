import { envValidationSchema } from './env.validation';

const DEV_DEFAULT = 'dev-only-change-me-dev-only-change-me';
const STRONG_SECRET = 'a'.repeat(40); // 40-символьный сильный секрет

const baseEnv = {
  DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
};
const productionV4 = {
  MANAGED_PASSWORD_ENCRYPTION_KEY: STRONG_SECRET,
  V4_ACCESS_MODE: 'v4',
  V4_ACCESS_KILL_SWITCH: false,
  V4_SCHEDULE_MODE: 'v4',
  V4_SCHEDULE_KILL_SWITCH: false,
  V4_PARITY_UNEXPLAINED_DIFFS: 0,
  LESSON_COMPLETION_WORKER_ENABLED: true,
  PLATFORM_OUTBOX_WORKER_ENABLED: true,
  INSTALLMENT_DUE_WORKER_ENABLED: true,
  LESSON_REMINDERS_ENABLED: true,
  TASK_REMINDERS_ENABLED: true,
  SCHEDULE_SERIES_AUTOEXTEND: true,
};

describe('envValidationSchema — JWT_ACCESS_SECRET', () => {
  describe('в production', () => {
    it('даёт ошибку при слабом (короткий) секрете', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: 'short',
      });
      expect(error).toBeDefined();
    });

    it('даёт ошибку при дефолтном dev-секрете', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: DEV_DEFAULT,
      });
      expect(error).toBeDefined();
    });

    it('даёт ошибку при отсутствующем секрете', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
      });
      expect(error).toBeDefined();
    });

    it('нет ошибки при сильном 40-символьном секрете', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_SECRET,
        ...productionV4,
      });
      expect(error).toBeUndefined();
    });

    it('требует отдельный ключ управляемых паролей', () => {
      const { MANAGED_PASSWORD_ENCRYPTION_KEY: _, ...withoutManagedKey } =
        productionV4;
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_SECRET,
        ...withoutManagedKey,
      });
      expect(error?.details[0]?.path).toContain(
        'MANAGED_PASSWORD_ENCRYPTION_KEY',
      );
    });

    it('не запускается на legacy/shadow маршрутах', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_SECRET,
        ...productionV4,
        V4_SCHEDULE_MODE: 'shadow',
      });
      expect(error).toBeDefined();
    });

    it('не запускается с отключённым обязательным production worker', () => {
      const { error } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_SECRET,
        ...productionV4,
        INSTALLMENT_DUE_WORKER_ENABLED: false,
      });
      expect(error).toBeDefined();
    });
  });

  describe('в development', () => {
    it('нет ошибки без секрета (берётся default)', () => {
      const { error, value } = envValidationSchema.validate({
        ...baseEnv,
        NODE_ENV: 'development',
      });
      expect(error).toBeUndefined();
      expect(value.JWT_ACCESS_SECRET).toBe(DEV_DEFAULT);
    });
  });
});
