import { Injectable } from "@nestjs/common";
import { UserRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";

export interface ProfileRow {
  id: string;
  user_id: string;
  email: string;
  role: UserRole;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  dob: Date | string | null;
  avatar_file_id: string | null;
  email_otp_2fa_enabled: boolean;
  is_app_account?: boolean;
  phone_verified_at?: Date | string | null;
  linked_students_count?: string;
  linked_leads_count?: string;
  linked_teachers_count?: string;
  linked_staff_count?: string;
  candidate_students_count?: string;
  candidate_leads_count?: string;
  candidate_teachers_count?: string;
  candidate_staff_count?: string;
  created_at: Date | string;
  updated_at: Date | string;
}

export interface ProfileNoteRow {
  id: string;
  profile_id: string;
  author_id: string | null;
  body: string;
  created_at: Date | string;
  author_email: string | null;
  author_first_name: string | null;
  author_last_name: string | null;
}

export interface ProfileDtoProjection {
  id: string;
  userId: string;
  email: string;
  role: UserRole;
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  dob: Date | string | null;
  avatarFileId: string | null;
  emailOtp2faEnabled: boolean;
  isAppAccount: boolean;
  phoneVerifiedAt: Date | string | null;
  createdAt: Date | string;
  updatedAt: Date | string;
}

export interface ProfileSummaryProjection {
  id: string;
  userId: string;
  email: string;
  role: UserRole;
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  isAppAccount: boolean;
  phoneVerifiedAt: Date | string | null;
  linkedStudents: number;
  linkedLeads: number;
  linkedTeachers: number;
  linkedStaff: number;
  candidateStudents: number;
  candidateLeads: number;
  candidateTeachers: number;
  candidateStaff: number;
}

export interface ProfileNoteProjection {
  id: string;
  profileId: string;
  authorId: string | null;
  body: string;
  createdAt: Date | string;
  author: {
    id: string;
    email: string | null;
    firstName: string | null;
    lastName: string | null;
  } | null;
}

export interface ProfileRecordPort {
  ensure(userId: string): Promise<void>;
  findByUserId(userId: string): Promise<ProfileRow | undefined>;
  findById(profileId: string): Promise<ProfileRow | undefined>;
  toProfileDto(row: ProfileRow): ProfileDtoProjection;
  toProfileSummaryDto(row: ProfileRow): ProfileSummaryProjection;
  toProfileNoteDto(row: ProfileNoteRow): ProfileNoteProjection;
}

@Injectable()
export class ProfileRecordRepository implements ProfileRecordPort {
  constructor(private readonly database: DatabaseService) {}

  async ensure(userId: string): Promise<void> {
    await this.database.query(
      `
        insert into app.profiles (user_id)
        values ($1)
        on conflict (user_id) do nothing
      `,
      [userId],
    );
  }

  async findByUserId(userId: string): Promise<ProfileRow | undefined> {
    const result = await this.database.query<ProfileRow>(
      `
        select p.id, p.user_id, u.email, u.role, p.first_name, p.last_name,
          p.phone, p.dob, p.avatar_file_id, p.email_otp_2fa_enabled,
          u.is_app_account, u.phone_verified_at,
          p.created_at, p.updated_at
        from app.profiles p
        join app.users u on u.id = p.user_id
        where p.user_id = $1 and p.deleted_at is null and u.deleted_at is null
        limit 1
      `,
      [userId],
    );
    return result.rows[0];
  }

  async findById(profileId: string): Promise<ProfileRow | undefined> {
    const result = await this.database.query<ProfileRow>(
      `
        select p.id, p.user_id, u.email, u.role, p.first_name, p.last_name,
          p.phone, p.dob, p.avatar_file_id, p.email_otp_2fa_enabled,
          u.is_app_account, u.phone_verified_at,
          p.created_at, p.updated_at
        from app.profiles p
        join app.users u on u.id = p.user_id
        where p.id = $1 and p.deleted_at is null and u.deleted_at is null
        limit 1
      `,
      [profileId],
    );
    return result.rows[0];
  }

  toProfileDto(row: ProfileRow): ProfileDtoProjection {
    return {
      id: row.id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      dob: row.dob,
      avatarFileId: row.avatar_file_id,
      emailOtp2faEnabled: row.email_otp_2fa_enabled,
      isAppAccount: row.is_app_account ?? true,
      phoneVerifiedAt: row.phone_verified_at ?? null,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  toProfileSummaryDto(row: ProfileRow): ProfileSummaryProjection {
    return {
      id: row.id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      isAppAccount: row.is_app_account ?? true,
      phoneVerifiedAt: row.phone_verified_at ?? null,
      linkedStudents: Number(row.linked_students_count ?? "0"),
      linkedLeads: Number(row.linked_leads_count ?? "0"),
      linkedTeachers: Number(row.linked_teachers_count ?? "0"),
      linkedStaff: Number(row.linked_staff_count ?? "0"),
      candidateStudents: Number(row.candidate_students_count ?? "0"),
      candidateLeads: Number(row.candidate_leads_count ?? "0"),
      candidateTeachers: Number(row.candidate_teachers_count ?? "0"),
      candidateStaff: Number(row.candidate_staff_count ?? "0"),
    };
  }

  toProfileNoteDto(row: ProfileNoteRow): ProfileNoteProjection {
    return {
      id: row.id,
      profileId: row.profile_id,
      authorId: row.author_id,
      body: row.body,
      createdAt: row.created_at,
      author: row.author_id
        ? {
            id: row.author_id,
            email: row.author_email,
            firstName: row.author_first_name,
            lastName: row.author_last_name,
          }
        : null,
    };
  }
}
