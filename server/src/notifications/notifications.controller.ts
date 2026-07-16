import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Query, UseGuards } from '@nestjs/common';
import { ActorContext } from '../common/security/actor-context';
import { CurrentActor } from '../common/security/current-actor.decorator';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { Roles } from '../common/security/roles.decorator';
import { RolesGuard } from '../common/security/roles.guard';
import { AdminSendNotificationDto } from './dto/admin-send-notification.dto';
import { ListNotificationsQuery } from './dto/list-notifications.query';
import { RegisterDeviceDto } from './dto/register-device.dto';
import { UpdateNotificationPreferenceDto } from './dto/update-notification-preference.dto';
import { NotificationsService } from './notifications.service';

@UseGuards(JwtAuthGuard)
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  list(@CurrentActor() actor: ActorContext, @Query() query: ListNotificationsQuery) {
    return this.notifications.list(actor, query);
  }

  @Post('read-all')
  markAllRead(@CurrentActor() actor: ActorContext) {
    return this.notifications.markAllRead(actor);
  }

  @Post(':id/read')
  markRead(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.notifications.markRead(actor, id);
  }

  @Post('devices')
  registerDevice(@CurrentActor() actor: ActorContext, @Body() dto: RegisterDeviceDto) {
    return this.notifications.registerDevice(actor, dto);
  }

  @Delete('devices/:id')
  deleteDevice(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.notifications.deleteDevice(actor, id);
  }
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('admin/notifications')
export class AdminNotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Post()
  @Roles('manager', 'director', 'admin', 'system_admin')
  send(@CurrentActor() actor: ActorContext, @Body() dto: AdminSendNotificationDto) {
    return this.notifications.adminSend(actor, dto);
  }

  @Get('preferences')
  @Roles('manager', 'director', 'admin', 'system_admin')
  listPreferences(@CurrentActor() actor: ActorContext) {
    return this.notifications.listPreferences(actor);
  }

  @Put('preferences')
  @Roles('manager', 'director', 'admin', 'system_admin')
  updatePreference(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UpdateNotificationPreferenceDto
  ) {
    return this.notifications.updatePreference(actor, dto);
  }
}
