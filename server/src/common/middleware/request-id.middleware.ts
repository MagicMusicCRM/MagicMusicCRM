import { randomUUID } from 'node:crypto';
import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';

const requestIdHeader = 'x-request-id';

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HTTP');

  use(req: Request, res: Response, next: NextFunction) {
    const incoming = req.header(requestIdHeader);
    const requestId = incoming && incoming.length <= 128 ? incoming : randomUUID();

    req.headers[requestIdHeader] = requestId;
    res.setHeader(requestIdHeader, requestId);

    if (req.path.startsWith('/api/') && !req.path.startsWith('/api/health')) {
      const start = Date.now();
      res.on('finish', () => {
        const ms = Date.now() - start;
        const tag = ms > 500 ? 'SLOW ' : '';
        this.logger.log(`${tag}${req.method} ${req.path} ${res.statusCode} ${ms}ms`);
      });
    }

    next();
  }
}
