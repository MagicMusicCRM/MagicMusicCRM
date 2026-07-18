import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus
} from '@nestjs/common';
import * as Sentry from '@sentry/node';
import { Request, Response } from 'express';
import { SafeLogger } from '../logging/safe-logger.service';

@Catch()
export class SafeExceptionFilter implements ExceptionFilter {
  constructor(private readonly logger: SafeLogger) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const requestId = request.header('x-request-id');

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    if (!(exception instanceof HttpException)) {
      // Carry the error's class, message and stack into the log. Sentry may be
      // unconfigured (SENTRY_DSN unset), and until this was added an unhandled
      // 500 logged only «Unhandled exception» with no cause — a Postgres check
      // violation or an EACCES read as an opaque «Internal server error», and
      // diagnosis meant reproducing the fault by hand. The class name and DB
      // message (e.g. «violates check constraint …») are not sensitive; the
      // stack is passed to the logger's stack channel, not the message body.
      const error = exception instanceof Error ? exception : undefined;
      this.logger.error(
        {
          message: 'Unhandled exception',
          // Constructor name, not `.name` — a `pg` error carries the useful
          // class («DatabaseError») on its constructor while `.name` is a bare
          // «error».
          error: error?.constructor?.name ?? typeof exception,
          detail: error?.message,
          requestId,
          path: request.path,
          method: request.method
        },
        error?.stack,
        'SafeExceptionFilter'
      );
    } else if (status >= 400 && status < 500) {
      // 4xx used to be INVISIBLE: only non-HttpException 500s were logged and
      // Caddy keeps no access log, so a ValidationPipe 400 («statusId must be
      // a UUID» broke 22% of lead cards) left zero trace anywhere. One warn
      // line per rejected request — message and path only, никаких значений
      // полей (privacy-safe) — turns client/DTO contract drift into a
      // greppable signal.
      this.logger.warn(
        {
          message: 'Request rejected',
          status,
          detail: this.safeMessage(exception),
          requestId,
          path: request.path,
          method: request.method
        },
        'SafeExceptionFilter'
      );
    }

    // Report server-side faults to Sentry (KVA-225). No-op when Sentry is not
    // initialised (SENTRY_DSN unset). 4xx client errors are not reported.
    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      Sentry.withScope((scope) => {
        scope.setTag('path', request.path);
        scope.setTag('method', request.method);
        if (requestId) scope.setExtra('requestId', requestId);
        Sentry.captureException(exception);
      });
    }

    response.status(status).json({
      // Structured payloads first: a ConflictException may carry machine-read
      // fields next to the message (e.g. the 409 {message, conflicts:[…]} of
      // the schedule contract). Flattening it to a bare message would strip
      // the data the client renders. The envelope fields below always win.
      ...this.extraPayload(exception),
      statusCode: status,
      message: this.safeMessage(exception),
      requestId,
      timestamp: new Date().toISOString(),
      path: request.path
    });
  }

  /** Extra structured fields of an HttpException object response (if any). */
  private extraPayload(exception: unknown): Record<string, unknown> {
    if (!(exception instanceof HttpException)) return {};
    const response = exception.getResponse();
    if (typeof response !== 'object' || response === null) return {};
    const { message: _message, statusCode: _statusCode, error: _error, ...rest } =
      response as Record<string, unknown>;
    return rest;
  }

  private safeMessage(exception: unknown): string {
    if (!(exception instanceof HttpException)) return 'Internal server error';

    const response = exception.getResponse();
    if (typeof response === 'string') return response;
    if (typeof response === 'object' && response !== null && 'message' in response) {
      const message = (response as { message: unknown }).message;
      if (Array.isArray(message)) return message.join('; ');
      if (typeof message === 'string') return message;
    }

    return exception.message;
  }
}
