import { ArrayUnique, IsArray, IsBoolean, IsIn } from 'class-validator';

/** Role preferences only control inbound lead notifications. */
const NOTIFICATION_EVENT_TYPES = ['new_lead'] as const;

/**
 * Roles that can be configured. 'client' is absent on purpose: these are staff
 * broadcasts, and offering to send «Новая заявка» to every client would be a
 * data leak one careless toggle away. system_admin is absent because it is an
 * operations account, not a recipient.
 */
const NOTIFICATION_PREFERENCE_ROLES = [
  'admin',
  'manager',
  'director',
  'teacher'
] as const;

export class UpdateNotificationPreferenceDto {
  @IsIn(NOTIFICATION_PREFERENCE_ROLES as unknown as string[])
  role!: string;

  @IsIn(NOTIFICATION_EVENT_TYPES as unknown as string[])
  eventType!: string;

  @IsBoolean()
  enabled!: boolean;

  @IsArray()
  @ArrayUnique()
  @IsIn(['in_app', 'push', 'email'], { each: true })
  channels!: string[];
}
