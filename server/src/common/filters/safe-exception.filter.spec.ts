import { BadRequestException, HttpStatus } from '@nestjs/common';
import * as Sentry from '@sentry/node';
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
  const filter = new SafeExceptionFilter({ error: jest.fn() } as never);

  beforeEach(() => jest.clearAllMocks());

  it('reports unhandled (500) exceptions to Sentry', () => {
    const { host, status } = makeHost();
    filter.catch(new Error('boom'), host);
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
    expect(status).toHaveBeenCalledWith(HttpStatus.INTERNAL_SERVER_ERROR);
  });

  it('does NOT report 4xx client errors to Sentry', () => {
    const { host, status } = makeHost();
    filter.catch(new BadRequestException('bad'), host);
    expect(Sentry.captureException).not.toHaveBeenCalled();
    expect(status).toHaveBeenCalledWith(HttpStatus.BAD_REQUEST);
  });
});

describe('SafeExceptionFilter diagnostics', () => {
  // An unhandled 500 used to log only «Unhandled exception» — no cause. This
  // pins that the error class, its message and stack now reach the logger, so a
  // DB check violation is legible in the logs instead of opaque.
  it('logs the error name, message and stack for an unhandled 500', () => {
    const error = jest.fn();
    const filter = new SafeExceptionFilter({ error } as never);
    const { host } = makeHost('/api/messenger/messages/x', 'DELETE');

    class DatabaseError extends Error {}
    const boom = new DatabaseError(
      'new row violates check constraint "message_payload_check"'
    );
    filter.catch(boom, host);

    expect(error).toHaveBeenCalledTimes(1);
    const [payload, stack, context] = error.mock.calls[0];
    expect(payload).toMatchObject({
      error: 'DatabaseError',
      detail: 'new row violates check constraint "message_payload_check"',
      path: '/api/messenger/messages/x',
      method: 'DELETE'
    });
    expect(stack).toBe(boom.stack);
    expect(context).toBe('SafeExceptionFilter');
  });

  it('does not log a body for a handled 4xx (only 500s are unhandled)', () => {
    const error = jest.fn();
    const filter = new SafeExceptionFilter({ error } as never);
    const { host } = makeHost();
    filter.catch(new BadRequestException('bad'), host);
    expect(error).not.toHaveBeenCalled();
  });
});
