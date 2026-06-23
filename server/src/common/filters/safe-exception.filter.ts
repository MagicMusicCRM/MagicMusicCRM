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
      this.logger.error(
        {
          message: 'Unhandled exception',
          requestId,
          path: request.path,
          method: request.method
        },
        undefined,
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
      statusCode: status,
      message: this.safeMessage(exception),
      requestId,
      timestamp: new Date().toISOString(),
      path: request.path
    });
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
