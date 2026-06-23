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
