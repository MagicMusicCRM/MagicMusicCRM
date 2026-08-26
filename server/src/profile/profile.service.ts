import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { ListProfilesQuery } from "./dto/list-profiles.query";
import { UpdateProfileDto } from "./dto/update-profile.dto";
import { MyProfileService } from "./my-profile.service";
import { ProfileDirectoryService } from "./profile-directory.service";
import { ProfileNotesService } from "./profile-notes.service";

@Injectable()
export class ProfileService {
  constructor(
    private readonly self: MyProfileService,
    private readonly directory: ProfileDirectoryService,
    private readonly notes: ProfileNotesService,
  ) {}

  getMe(actor: ActorContext) {
    return this.self.getMe(actor);
  }

  updateMe(actor: ActorContext, dto: UpdateProfileDto) {
    return this.self.updateMe(actor, dto);
  }

  listProfiles(actor: ActorContext, query: ListProfilesQuery) {
    return this.directory.listProfiles(actor, query);
  }

  getProfile(actor: ActorContext, profileId: string) {
    return this.directory.getProfile(actor, profileId);
  }

  listProfileLinks(actor: ActorContext, profileId: string) {
    return this.directory.listProfileLinks(actor, profileId);
  }

  listProfileNotes(actor: ActorContext, profileId: string) {
    return this.notes.listProfileNotes(actor, profileId);
  }

  createProfileNote(actor: ActorContext, profileId: string, body: string) {
    return this.notes.createProfileNote(actor, profileId, body);
  }
}
