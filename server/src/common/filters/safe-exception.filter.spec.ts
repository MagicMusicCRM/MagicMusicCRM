import {
  BadRequestException,
  HttpStatus,
  InternalServerErrorException
} from '@nestjs/common';
import * as Sentry from '@sentry/node';
import { LessonSettlementCalculationError } from '../../crm/commerce/lesson-settlement.calculation';
import { SubscriptionPreviewTokenError } from '../../crm/commerce/subscription-preview-token';
import { SafeExceptionFilter } from './safe-exception.filter';

jest.mock('@sentry/node', () => ({
  captureException: jest.fn(),
  withScope: jest.fn((cb: (scope: unknown) => void) =>
    cb({ setTag: jest.fn(), setExtra: jest.fn() })
  )
}));

function makeHost(path = '/api/x', method = 'GET') {
  const json = jest.fn();
  const status = jest.fn(() => ({ json }));
  const request = { path, method, header: jest.fn(() => 'req-1') };
  const host = {
    switchToHttp: () => ({
      getResponse: () => ({ status }),
      getRequest: () => request
    })
  } as never;
  return { host, json, status };
}

describe('SafeExceptionFilter Sentry reporting', () => {
  const filter = new SafeExceptionFilter({
    error: jest.fn(),
    warn: jest.fn(),
  } as never);

  beforeEach(() => jest.clearAllMocks());

  it('reports unhandled (500) exceptions to Sentry', () => {
    const { host, status, json } = makeHost();
    filter.catch(new Error('boom'), host);
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
    expect(status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(json).toHaveBeenCalledWith(expect.objectContaining({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Сервис временно недоступен. Попробуйте позже.',
      requestId: 'req-1',
    }));
  });

  it('does NOT report 4xx client errors to Sentry', () => {
    const { host, status } = makeHost();
    filter.catch(new BadRequestException('bad'), host);
    expect(Sentry.captureException).not.toHaveBeenCalled();
    expect(status).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
  });
});

describe('SafeExceptionFilter diagnostics', () => {
  beforeEach(() => jest.clearAllMocks());

  // An unhandled 500 used to log only «Unhandled exception» — no cause. This
  // pins that the error class, its message and stack now reach the logger, so a
  // DB check violation is legible in the logs instead of opaque.
  it('logs the error name, message and stack for an unhandled 500', () => {
    const error = jest.fn();
    const filter = new SafeExceptionFilter({ error, warn: jest.fn() } as never);
    const { host } = makeHost('/api/messenger/messages/x', 'DELETE');

    class DatabaseError extends Error {}
    const boom = new DatabaseError(
      'new row violates check constraint "message_payload_check"'
    );
    filter.catch(boom, host);

    expect(error).toHaveBeenCalledTimes(1);
    const [payload, stack, context] = error.mock.calls[0];
    expect(payload).toMatchObject({
      code: 'INTERNAL_SERVER_ERROR',
      error: 'DatabaseError',
      detail: 'new row violates check constraint "message_payload_check"',
      path: '/api/messenger/messages/x',
      method: 'DELETE'
    });
    expect(stack).toBe(boom.stack);
    expect(context).toBe('SafeExceptionFilter');
  });

  it('keeps an explicit 500 HttpException opaque while logging its cause', () => {
    const error = jest.fn();
    const filter = new SafeExceptionFilter({ error, warn: jest.fn() } as never);
    const { host, status, json } = makeHost('/api/crm/lessons/x/settle', 'POST');
    const exception = new InternalServerErrorException({
      code: 'DATABASE_FAILURE',
      message: 'select secret_token from private_table',
      sql: 'select * from private_table',
      token: 'bearer-secret'
    });

    filter.catch(exception, host);

    expect(status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
    const body = json.mock.calls[0]?.[0] as Record<string, unknown>;
    expect(body).toMatchObject({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Сервис временно недоступен. Попробуйте позже.',
      requestId: 'req-1',
      path: '/api/crm/lessons/x/settle'
    });
    expect(body).not.toHaveProperty('sql');
    expect(body).not.toHaveProperty('token');
    expect(JSON.stringify(body)).not.toMatch(/private_table|secret_token|bearer-secret/);
    expect(error).toHaveBeenCalledWith(
      expect.objectContaining({
        code: 'INTERNAL_SERVER_ERROR',
        detail: 'select secret_token from private_table',
        requestId: 'req-1',
        path: '/api/crm/lessons/x/settle',
        method: 'POST'
      }),
      exception.stack,
      'SafeExceptionFilter'
    );
  });

  it.each([
    [
      new LessonSettlementCalculationError('PARTIAL_DURATION_EXCEEDS_LESSON'),
      'PARTIAL_DURATION_EXCEEDS_LESSON',
      'Проверьте параметры расчёта занятия.',
    ],
    [
      new SubscriptionPreviewTokenError('PREVIEW_TOKEN_EXPIRED'),
      'PREVIEW_TOKEN_EXPIRED',
      'Предпросмотр устарел. Обновите расчёт и повторите действие.',
    ],
  ] as const)(
    'maps a proven domain error to a safe 422 response',
    (domainError, code, message) => {
      const error = jest.fn();
      const warn = jest.fn();
      const filter = new SafeExceptionFilter({ error, warn } as never);
      const { host, status, json } = makeHost('/api/crm/lessons/x/settle', 'POST');

      filter.catch(domainError, host);

      expect(status).toHaveBeenCalledWith(HttpStatus.UNPROCESSABLE_ENTITY);
      expect(json).toHaveBeenCalledWith(expect.objectContaining({
        code,
        message,
        requestId: 'req-1',
      }));
      expect(error).not.toHaveBeenCalled();
      expect(warn).toHaveBeenCalledWith(expect.objectContaining({
        code,
        requestId: 'req-1',
        path: '/api/crm/lessons/x/settle',
      }), 'SafeExceptionFilter');
      expect(Sentry.captureException).not.toHaveBeenCalled();
    },
  );

  it('does not log a body for a handled 4xx (only 500s are unhandled)', () => {
    const error = jest.fn();
    const warn = jest.fn();
    const filter = new SafeExceptionFilter({ error, warn } as never);
    const { host } = makeHost();
    filter.catch(new BadRequestException('bad'), host);
    expect(error).not.toHaveBeenCalled();
    expect(warn).toHaveBeenCalledWith(
      expect.objectContaining({
        message: 'Request rejected',
        status: HttpStatus.BAD_REQUEST,
        detail: 'bad'
      }),
      'SafeExceptionFilter'
    );
  });
});
