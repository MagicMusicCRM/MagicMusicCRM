/**
 * A student's card email is contact data, not the globally unique app login.
 * Legacy rows can still fall back to a real (non-placeholder) profile email.
 */
export function studentContactEmailSql(
  studentAlias = "s",
  userAlias = "u",
): string {
  return `coalesce(
    nullif(btrim(${studentAlias}.contact_email), ''),
    case
      when lower(${userAlias}.email) like '%@local.magicmusiccrm.invalid' then null
      when lower(${userAlias}.email) like '%@migration.invalid' then null
      else nullif(btrim(${userAlias}.email), '')
    end
  )`;
}
