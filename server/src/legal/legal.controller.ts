import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { Request } from 'express';
import { ActorContext } from '../common/security/actor-context';
import { CurrentActor } from '../common/security/current-actor.decorator';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { Roles } from '../common/security/roles.decorator';
import { RolesGuard } from '../common/security/roles.guard';
import { AcceptCurrentConsentsDto } from './dto/accept-current-consents.dto';
import { CreateDeletionRequestDto } from './dto/create-deletion-request.dto';
import { ListDeletionRequestsQuery } from './dto/list-deletion-requests.query';
import { UpdateDeletionRequestDto } from './dto/update-deletion-request.dto';
import { LegalService } from './legal.service';

@UseGuards(JwtAuthGuard)
@Controller('legal')
export class LegalController {
  constructor(private readonly legal: LegalService) {}

  @Get('gate')
  getGate(@CurrentActor() actor: ActorContext) {
    return this.legal.getGate(actor);
  }

  @Get('documents/current')
  getCurrentDocuments() {
    return this.legal.listCurrentDocuments();
  }

  @Post('consents/current')
  acceptCurrentDocuments(
    @CurrentActor() actor: ActorContext,
    @Body() dto: AcceptCurrentConsentsDto,
    @Req() request: Request
  ) {
    return this.legal.acceptCurrentDocuments(actor, dto, {
      ip: this.forwardedIp(request),
      userAgent: request.headers['user-agent']
    });
  }

  private forwardedIp(request: Request): string | undefined {
    const forwardedFor = request.headers['x-forwarded-for'];
    if (typeof forwardedFor === 'string') return forwardedFor.split(',')[0]?.trim();
    return request.ip || request.socket.remoteAddress || undefined;
  }
}

@UseGuards(JwtAuthGuard)
@Controller('profile/deletion-request')
export class ProfileDeletionController {
  constructor(private readonly legal: LegalService) {}

  @Post()
  create(@CurrentActor() actor: ActorContext, @Body() dto: CreateDeletionRequestDto) {
    return this.legal.createDeletionRequest(actor, dto);
  }

  @Get()
  getOwn(@CurrentActor() actor: ActorContext) {
    return this.legal.getOwnDeletionRequest(actor);
  }
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('admin/deletion-requests')
export class AdminDeletionRequestsController {
  constructor(private readonly legal: LegalService) {}

  @Get()
  @Roles('manager', 'admin', 'system_admin')
  list(@CurrentActor() actor: ActorContext, @Query() query: ListDeletionRequestsQuery) {
    return this.legal.listDeletionRequests(actor, query);
  }

  @Patch(':id')
  @Roles('admin')
  update(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateDeletionRequestDto
  ) {
    return this.legal.updateDeletionRequest(actor, id, dto);
  }
}
