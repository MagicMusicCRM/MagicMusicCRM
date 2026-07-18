[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DemoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Wrapper = Join-Path $DemoRoot "demo-reset.ps1"
$Preflight = Join-Path $DemoRoot "sql/preflight.sql"
$Reset = Join-Path $DemoRoot "sql/reset.sql"
$Support = Join-Path $DemoRoot "sql/ensure-support.sql"

function Assert-True {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "ASSERTION FAILED: $Message"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )
  Assert-True -Condition ($Text.Contains($Needle)) -Message $Message
}

function Assert-NotMatch {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )
  Assert-True -Condition (-not [regex]::IsMatch($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) -Message $Message
}

foreach ($path in @($Wrapper, $Preflight, $Reset, $Support)) {
  Assert-True -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "Missing file: $path"
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
  $Wrapper,
  [ref]$tokens,
  [ref]$parseErrors
)
Assert-True -Condition ($parseErrors.Count -eq 0) -Message "demo-reset.ps1 has PowerShell parse errors."

$wrapperText = Get-Content -Raw -LiteralPath $Wrapper
$preflightText = Get-Content -Raw -LiteralPath $Preflight
$resetText = Get-Content -Raw -LiteralPath $Reset
$supportText = Get-Content -Raw -LiteralPath $Support

Assert-Contains $wrapperText '[string]$Action = "Preflight"' "Default action must be read-only Preflight."
Assert-Contains $wrapperText '$AllowedEmail = "magic1@gmail.com"' "Target email must be a fixed allowlist constant."
Assert-Contains $wrapperText '$AllowedBackupDir = "/opt/magicmusiccrm/backups"' "Remote backup directory must be fixed."
Assert-Contains $wrapperText "New-VerifiedBackup" "Every mutation path must have a backup primitive."
Assert-Contains $wrapperText 'RESET DEMO magic1@gmail.com' "Reset must require an exact confirmation phrase."
Assert-Contains $wrapperText 'ENSURE DEMO SUPPORT magic1@gmail.com' "Support apply must require an exact confirmation phrase."

$resetBackupIndex = $wrapperText.IndexOf('[void](New-VerifiedBackup)', $wrapperText.IndexOf('"Reset"'))
$resetSqlIndex = $wrapperText.IndexOf('Invoke-RemoteSql -SqlPath $ResetSql', $wrapperText.IndexOf('"Reset"'))
Assert-True ($resetBackupIndex -ge 0 -and $resetSqlIndex -gt $resetBackupIndex) "Reset SQL must execute only after a verified backup."

$supportBackupIndex = $wrapperText.IndexOf('[void](New-VerifiedBackup)', $wrapperText.IndexOf('"EnsureSupport"'))
$supportSqlIndex = $wrapperText.IndexOf('Invoke-RemoteSql -SqlPath $SupportSql', $wrapperText.IndexOf('"EnsureSupport"'))
Assert-True ($supportBackupIndex -ge 0 -and $supportSqlIndex -gt $supportBackupIndex) "Support SQL must execute only after a verified backup."

foreach ($text in @($preflightText, $resetText, $supportText)) {
  Assert-Contains $text '18e4ca3f-f479-4ad8-875d-ed687b9fdcbc' "magic1 exact user ID must be asserted."
  Assert-Contains $text 'a0fe524d-21d8-411c-8fc8-d6a113e1b9be' "magic1 exact profile ID must be asserted."
}

Assert-Contains $preflightText "('magic2@gmail.com'" "Preflight must verify magic2."
Assert-Contains $preflightText "('magic3@gmail.com'" "Preflight must verify magic3."
Assert-Contains $preflightText "('magic4@gmail.com'" "Preflight must verify magic4."
Assert-Contains $preflightText "'active_subscription_package'" "Preflight must verify an active package."
Assert-Contains $preflightText "'magic1_fcm'" "Preflight must verify the client push device."
Assert-Contains $preflightText "target_notifications as" "Preflight must derive graph-scoped notification cleanup."
Assert-Contains $preflightText "'notification_deliveries'" "Preflight must report target push deliveries."
Assert-Contains $preflightText "'notification_email_outbox'" "Preflight must report target notification email rows."

Assert-Contains $resetText "begin isolation level repeatable read" "Reset must use one repeatable-read transaction."
Assert-Contains $resetText "demo_target_leads" "Reset must derive the target lead graph."
Assert-Contains $resetText "demo_target_students" "Reset must derive the target student graph."
Assert-Contains $resetText "demo_target_homeworks" "Reset must derive homework IDs before deleting notifications."
Assert-Contains $resetText "demo_target_tasks" "Reset must derive task IDs before deleting notifications."
Assert-Contains $resetText "demo_target_notifications" "Reset must derive graph-scoped notification IDs."
Assert-NotMatch $resetText "demo_allowed_notification_users" "Graph-scoped notification cleanup must not exclude non-demo recipients."
Assert-Contains $resetText "to_jsonb(homework) ->> 'lead_id'" "Reset must include T9.1 lead-owned homework when that column exists."
Assert-Contains $resetText "to_jsonb(subscription) ->> 'conversion_lead_id'" "Reset must include T9.1 conversion subscriptions when that column exists."
Assert-Contains $resetText "delete from app.messages where chat_id in (select id from demo_target_chats)" "Only private target-chat messages should be deleted."
Assert-Contains $resetText "notification.data ->> 'entityType' = 'lead'" "Lead notifications must be selected by graph identity."
Assert-Contains $resetText "notification.data ->> 'lessonId'" "Lesson notifications must be selected by graph identity."
Assert-Contains $resetText "notification.data ->> 'entityType' = 'task'" "Task notifications must be selected by graph identity."
Assert-Contains $resetText "recipient.notification_id in (select id from demo_target_notifications)" "Recipient deletion must be notification-scoped."
Assert-Contains $resetText "delivery.notification_id in (select id from demo_target_notifications)" "Delivery deletion must be notification-scoped."
Assert-Contains $resetText "unrelated_notification_recipient_signature" "Reset must prove all unrelated notification recipients were preserved."
Assert-Contains $resetText "unrelated_notification_delivery_signature" "Reset must prove all unrelated notification deliveries were preserved."
Assert-Contains $resetText "unrelated_notification_email_outbox_signature" "Reset must prove all unrelated notification email rows were preserved."
Assert-True -Condition ([regex]::IsMatch(
  $resetText,
  'delete\s+from\s+app\.notification_recipients\s+recipient\s+where\s+recipient\.notification_id\s+in\s*\(select\s+id\s+from\s+demo_target_notifications\)\s*;',
  [Text.RegularExpressions.RegexOptions]::IgnoreCase
)) -Message "Reset must delete every recipient of a captured target notification."
Assert-True -Condition ([regex]::IsMatch(
  $resetText,
  'delete\s+from\s+app\.notification_deliveries\s+delivery\s+where\s+delivery\.notification_id\s+in\s*\(select\s+id\s+from\s+demo_target_notifications\)\s*;',
  [Text.RegularExpressions.RegexOptions]::IgnoreCase
)) -Message "Reset must delete every delivery of a captured target notification."
Assert-True -Condition ([regex]::IsMatch(
  $resetText,
  'delete\s+from\s+app\.email_outbox\s+outbox\s+where\s+exists\s*\([\s\S]*?demo_target_notifications[\s\S]*?notificationId[\s\S]*?\)\s*;',
  [Text.RegularExpressions.RegexOptions]::IgnoreCase
)) -Message "Reset must delete every email row of a captured target notification."
Assert-Contains $resetText "orphan target notification remains" "Reset must reject leftover orphan target notifications."
Assert-Contains $resetText "immutable audit trail changed" "Reset must post-check immutable audit preservation."
Assert-Contains $resetText "Shared announcements allowlist mismatch" "Reset must guard shared announcements."
Assert-NotMatch $resetText "delete\s+from\s+app\.notification_recipients\s+where\s+user_id\s*=\s*'18e4ca3f" "Reset must not erase every magic1 notification."
Assert-NotMatch $resetText "delete\s+from\s+app\.notification_deliveries\s+where\s+user_id\s*=\s*'18e4ca3f" "Reset must not erase every magic1 delivery."

foreach ($table in @('users', 'profiles', 'legal_consents', 'notification_devices', 'audit_events', 'chats', 'chat_members')) {
  Assert-NotMatch $resetText "delete\s+from\s+app\.$table\b" "Reset must not delete from app.$table."
}
Assert-NotMatch $resetText "update\s+app\.users\b" "Reset must never update auth users or roles."
Assert-NotMatch $resetText "update\s+app\.profiles\b" "Reset must preserve the profile."

Assert-Contains $supportText "insert into app.teachers" "Support action must create a missing teacher."
Assert-Contains $supportText "insert into app.staff_members" "Support action must create missing staff."
Assert-Contains $supportText "insert into app.subscription_packages" "Support action must create a package only when missing."
Assert-Contains $supportText "where not exists" "Support inserts must be idempotent."
Assert-True -Condition ([regex]::IsMatch(
  $supportText,
  'insert\s+into\s+app\.subscription_packages[\s\S]*?where\s+not\s+exists\s*\(\s*select\s+1\s+from\s+app\.subscription_packages',
  [Text.RegularExpressions.RegexOptions]::IgnoreCase
)) -Message "Package creation must re-check the active catalog inside the apply transaction."
Assert-NotMatch $supportText "update\s+app\.users\b" "Support action must never update auth roles."
Assert-NotMatch $supportText "delete\s+from\b" "Support action must not delete data."

$checkOutput = & $Wrapper -CheckOnly 2>&1
Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Wrapper -CheckOnly failed."
Assert-True -Condition (($checkOutput -join "`n") -match 'CHECK_ONLY\|OK\|magic1@gmail\.com') -Message "Wrapper -CheckOnly did not prove the fixed allowlist."

Write-Host "DEMO_RESET_CONTRACT_TESTS|OK"
