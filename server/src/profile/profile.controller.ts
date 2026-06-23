import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ActorContext } from '../common/security/actor-context';
import { CurrentActor } from '../common/security/current-actor.decorator';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { Roles } from '../common/security/roles.decorator';
import { RolesGuard } from '../common/security/roles.guard';
import { CreateProfileNoteDto } from './dto/create-profile-note.dto';
import { LinkProfileCrmDto } from './dto/link-profile-crm.dto';
import { ListProfilesQuery } from './dto/list-profiles.query';
import { UpdateProfileDto } from './dto/update-profile.dto';
import { UpdateRoleDto } from './dto/update-role.dto';
import { ProfileService } from './profile.service';

@UseGuards(JwtAuthGuard)
@Controller('profile')
export class ProfileController {
  constructor(private readonly profiles: ProfileService) {}

  @Get('me')
  getMe(@CurrentActor() actor: ActorContext) {
    return this.profiles.getMe(actor);
  }

  @Patch('me')
  updateMe(@CurrentActor() actor: ActorContext, @Body() dto: UpdateProfileDto) {
    return this.profiles.updateMe(actor, dto);
  }
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('admin/profiles')
export class AdminProfilesController {
  constructor(private readonly profiles: ProfileService) {}

  @Get()
  @Roles('manager', 'admin', 'system_admin')
  list(@CurrentActor() actor: ActorContext, @Query() query: ListProfilesQuery) {
    return this.profiles.listProfiles(actor, query);
  }

  @Get(':id')
  @Roles('manager', 'admin', 'system_admin')
  get(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.profiles.getProfile(actor, id);
  }

  @Get(':id/notes')
  @Roles('manager', 'admin', 'system_admin')
  listNotes(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string
  ) {
    return this.profiles.listProfileNotes(actor, id);
  }

  @Post(':id/notes')
  @Roles('manager', 'admin', 'system_admin')
  createNote(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CreateProfileNoteDto
  ) {
    return this.profiles.createProfileNote(actor, id, dto.body);
  }

  @Get(':id/link-candidates')
  @Roles('manager', 'admin', 'system_admin')
  listLinkCandidates(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string
  ) {
    return this.profiles.listLinkCandidates(actor, id);
  }

  @Post(':id/links/auto')
  @Roles('manager', 'admin', 'system_admin')
  autoLinkByPhone(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string
  ) {
    return this.profiles.autoLinkByPhone(actor, id);
  }

  @Post(':id/links')
  @Roles('manager', 'admin', 'system_admin')
  linkCrmEntity(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: LinkProfileCrmDto
  ) {
    return this.profiles.linkCrmEntity(actor, id, dto);
  }

  @Patch(':id/role')
  @Roles('manager', 'system_admin')
  updateRole(
    @CurrentActor() actor: ActorContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateRoleDto
  ) {
    return this.profiles.updateRole(actor, id, dto.role);
  }
}
