import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';
import { ActorContext, AuthenticatedRequest } from './actor-context';

export const CurrentActor = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): ActorContext | undefined => {
    const request = ctx.switchToHttp().getRequest<Request & AuthenticatedRequest>();
    return request.user;
  }
);
