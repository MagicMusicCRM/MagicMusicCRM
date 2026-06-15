import { randomUUID } from 'node:crypto';
import { Injectable, NestMiddleware } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';

const requestIdHeader = 'x-request-id';

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const incoming = req.header(requestIdHeader);
    const requestId = incoming && incoming.length <= 128 ? incoming : randomUUID();

    req.headers[requestIdHeader] = requestId;
    res.setHeader(requestIdHeader, requestId);
    next();
  }
}
