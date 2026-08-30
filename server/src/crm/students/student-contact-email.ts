/**
 * A student's card email is contact data, not the globally unique app login.
 * An empty value is intentional and must never fall back to login identity.
 */
export function studentContactEmailSql(studentAlias = "s"): string {
  return `nullif(btrim(${studentAlias}.contact_email), '')`;
}
