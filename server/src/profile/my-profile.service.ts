import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import {
  LEAD_INTAKE_PORT,
  LeadIntakePort,
} from "../common/lead-intake.port";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { UpdateProfileDto } from "./dto/update-profile.dto";
import { ProfileLinkingService } from "./profile-linking.service";
import {
  ProfileDtoProjection,
  ProfileRecordRepository,
  ProfileRow,
} from "./profile-record.repository";

export interface MyProfileOperations {
  getMe(actor: ActorContext): Promise<
    ProfileDtoProjection & {
      branchIds: string[];
      homeBranchId: string | null;
    }
  >;
  updateMe(
    actor: ActorContext,
    dto: UpdateProfileDto,
  ): Promise<ProfileDtoProjection>;
}

@Injectable()
export class MyProfileService implements MyProfileOperations {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly linking: ProfileLinkingService,
    @Inject(LEAD_INTAKE_PORT) private readonly leadIntake: LeadIntakePort,
    private readonly repository: ProfileRecordRepository,
  ) {}

  async getMe(actor: ActorContext) {
    let profile = await this.repository.findByUserId(actor.userId);
    if (!profile) {
      await this.repository.ensure(actor.userId);
      profile = await this.repository.findByUserId(actor.userId);
    }
    if (!profile) throw new NotFoundException("Профиль не найден.");

    const branches = await this.database.query<{ branch_id: string }>(
      `
        select sba.branch_id::text as branch_id
        from app.staff_members sm
        join app.staff_branch_assignments sba
          on sba.staff_member_id = sm.id and sba.deleted_at is null
        where sm.profile_id = $1 and sm.deleted_at is null
        order by sba.created_at asc, sba.branch_id asc
      `,
      [profile.id],
    );
    const branchIds = branches.rows.map((row) => row.branch_id);
    return {
      ...this.repository.toProfileDto(profile),
      branchIds,
      homeBranchId: branchIds[0] ?? null,
    };
  }

  async updateMe(actor: ActorContext, dto: UpdateProfileDto) {
    await this.repository.ensure(actor.userId);
    if (dto.avatarFileId) {
      await this.assertOwnAvatarFile(actor, dto.avatarFileId);
    }
    const firstName = dto.firstName?.trim() || null;
    const lastName = dto.lastName?.trim() || null;
    const phone = dto.phone?.trim() || null;
    const result = await this.database.query<ProfileRow>(
      `
        update app.profiles p
        set
          first_name = coalesce($2, p.first_name),
          last_name = coalesce($3, p.last_name),
          phone = coalesce($4, p.phone),
          dob = coalesce($5::date, p.dob),
          email_otp_2fa_enabled = coalesce($6, p.email_otp_2fa_enabled),
          avatar_file_id = coalesce($7::uuid, p.avatar_file_id),
          updated_at = now()
        from app.users u
        where p.user_id = u.id
          and p.user_id = $1
          and p.deleted_at is null
          and u.deleted_at is null
        returning p.id, p.user_id, u.email, u.role,
          p.first_name, p.last_name, p.phone,
          p.dob, p.avatar_file_id,
          p.email_otp_2fa_enabled, p.created_at,
          p.updated_at
      `,
      [
        actor.userId,
        firstName,
        lastName,
        phone,
        dto.dob ?? null,
        dto.emailOtp2faEnabled ?? null,
        dto.avatarFileId ?? null,
      ],
    );

    const profile = result.rows[0];
    if (!profile) throw new NotFoundException("Профиль не найден.");
    if (profile.first_name && profile.last_name && profile.phone) {
      await this.database.query(
        `
          update app.users
          set profile_completed = true,
              is_app_account = true,
              phone_verified_at = coalesce(phone_verified_at, now()),
              updated_at = now()
          where id = $1
            and deleted_at is null
        `,
        [actor.userId],
      );
      if (profile.role === "client") {
        await this.leadIntake.autoCreateLeadFromChat(
          actor,
          actor.userId,
          "onboarding",
        );
      } else {
        await this.linking.linkProfileByPhone(actor, profile, "auto_phone");
      }
    }

    await this.audit.record({
      actor,
      action: "profile.updated",
      entityType: "profile",
      entityId: profile.id,
    });

    return this.repository.toProfileDto(profile);
  }

  private async assertOwnAvatarFile(
    actor: ActorContext,
    fileId: string,
  ): Promise<void> {
    const result = await this.database.query<{ id: string }>(
      `
        select id
        from app.file_objects
        where id = $1
          and owner_user_id = $2
          and purpose = 'profile_avatar'
          and deleted_at is null
        limit 1
      `,
      [fileId, actor.userId],
    );
    if (!result.rows[0]) {
      throw new NotFoundException("Файл аватара не найден.");
    }
  }
}
