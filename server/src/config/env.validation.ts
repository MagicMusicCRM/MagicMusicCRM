import * as Joi from 'joi';

export const envValidationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'test', 'staging', 'production')
    .default('development'),
  PORT: Joi.number().port().default(3000),
  CORS_ALLOWED_ORIGINS: Joi.string().allow('').default(''),
  DATABASE_URL: Joi.string()
    .uri({ scheme: ['postgres', 'postgresql'] })
    .required(),
  JWT_ACCESS_SECRET: Joi.string().when('NODE_ENV', {
    is: 'production',
    then: Joi.string()
      .min(32)
      .invalid('dev-only-change-me-dev-only-change-me')
      .required(),
    otherwise: Joi.string()
      .min(32)
      .default('dev-only-change-me-dev-only-change-me')
  }),
  ACCESS_TOKEN_TTL_SECONDS: Joi.number().integer().min(60).max(3600).default(900),
  REFRESH_TOKEN_TTL_DAYS: Joi.number().integer().min(1).max(90).default(30),
  FILE_STORAGE_ROOT: Joi.string().default('/opt/magicmusiccrm/storage'),
  RESEND_API_KEY: Joi.string().allow('').default(''),
  RESEND_FROM_EMAIL: Joi.string().email().allow('').default(''),
  RESEND_TIMEOUT_MS: Joi.number().integer().min(100).max(30000).default(5000),
  SMTP_FALLBACK_HOST: Joi.string().allow('').default(''),
  SMTP_FALLBACK_PORT: Joi.number().port().default(465),
  SMTP_FALLBACK_SECURE: Joi.boolean().default(true),
  SMTP_FALLBACK_USER: Joi.string().allow('').default(''),
  SMTP_FALLBACK_PASSWORD: Joi.string().allow('').default(''),
  SMTP_FALLBACK_FROM_EMAIL: Joi.string().email().allow('').default(''),
  FIREBASE_SERVER_KEY: Joi.string().allow('').default(''),
  FIREBASE_PROJECT_ID: Joi.string().allow('').default(''),
  FIREBASE_CLIENT_EMAIL: Joi.string().email().allow('').default(''),
  FIREBASE_PRIVATE_KEY: Joi.string().allow('').default(''),
  FIREBASE_TIMEOUT_MS: Joi.number().integer().min(100).max(30000).default(5000),
  NOTIFICATION_TOKEN_ENCRYPTION_KEY: Joi.string().allow('').default(''),
  LESSON_REMINDERS_ENABLED: Joi.boolean().default(false),
  TASK_REMINDERS_ENABLED: Joi.boolean().default(false),
  V4_ACCESS_MODE: Joi.string().valid('legacy', 'shadow', 'v4').default('shadow'),
  V4_ACCESS_KILL_SWITCH: Joi.boolean().default(false),
  V4_SCHEDULE_MODE: Joi.string().valid('legacy', 'shadow', 'v4').default('shadow'),
  V4_SCHEDULE_KILL_SWITCH: Joi.boolean().default(false),
  V4_PARITY_UNEXPLAINED_DIFFS: Joi.number().integer().min(0).default(1),
  LEAD_WEBHOOK_SECRET: Joi.string().allow('').min(32).default(''),
  HOLLIHOP_BASE_URL: Joi.string().uri().default('https://sokol.t8s.ru/Api/V2/'),
  HOLLIHOP_AUTH_KEY: Joi.string().allow('').default(''),
  HOLLIHOP_TIMEOUT_MS: Joi.number().integer().min(100).max(30000).default(5000)
});
