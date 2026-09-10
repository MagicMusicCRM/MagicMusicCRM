import { randomUUID } from 'node:crypto';
import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';
import { newRequestPerformance, performanceFields, requestPerformance } from '../observability/request-performance';

const requestIdHeader = 'x-request-id';

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HTTP');

  use(req: Request, res: Response, next: NextFunction) {
    const incoming = req.header(requestIdHeader);
    const requestId = incoming && /^[a-zA-Z0-9._:-]{1,128}$/.test(incoming) ? incoming : randomUUID();
    const incomingOperation = req.header('x-operation-id');
    const operationId = incomingOperation && /^[0-9a-f-]{36}$/i.test(incomingOperation)
      ? incomingOperation : undefined;
    const context = newRequestPerformance(requestId, operationId);

    req.headers[requestIdHeader] = requestId;
    res.setHeader(requestIdHeader, requestId);

    const writeHead = res.writeHead;
    res.writeHead = function (this: Response, ...args: Parameters<Response['writeHead']>) {
      const fields = performanceFields(context);
      res.setHeader('Server-Timing', `app;dur=${fields.durationMs}, db;dur=${fields.dbQueryMs}, pool;dur=${fields.dbAcquireMs}`);
      return writeHead.apply(this, args);
    } as Response['writeHead'];
    const complete = (outcome: 'completed' | 'aborted') => {
      if (context.closed) return;
      context.closed = true;
      if (req.path.startsWith('/api/') && !req.path.startsWith('/api/health')) {
        this.logger.log({ event: 'http.performance', ...performanceFields(context),
          method: req.method, route: typeof req.route?.path === 'string' ? req.route.path : 'unmatched',
          status: res.statusCode, outcome });
      }
    };
    res.once('finish', () => complete('completed'));
    res.once('close', () => complete('aborted'));
    requestPerformance.run(context, next);
  }
}
