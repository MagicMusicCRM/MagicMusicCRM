import { envValidationSchema } from './env.validation';

const DEV_DEFAULT = 'dev-only-change-me-dev-only-change-me';
const STRONG_SECRET = 'a'.repeat(40); // 40-символьный сильный секрет

const baseEnv = {
  DATABASE_URL: 'postgres://user:pass@localhost:5432/db',
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
      });
      expect(error).toBeUndefined();
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
