[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Wrapper = Join-Path $Root "prelaunch-reset.ps1"
$Preflight = Join-Path $Root "sql/preflight.sql"
$Reset = Join-Path $Root "sql/reset.sql"

function Assert-True {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )
  Assert-True -Condition $Text.Contains($Needle) -Message $Message
}

foreach ($path in @($Wrapper, $Preflight, $Reset)) {
  Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing file: $path"
}

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
  $Wrapper,
  [ref]$tokens,
  [ref]$parseErrors
)
Assert-True ($parseErrors.Count -eq 0) "prelaunch-reset.ps1 has PowerShell parse errors."

$wrapperText = Get-Content -Raw -LiteralPath $Wrapper
$preflightText = Get-Content -Raw -LiteralPath $Preflight
$resetText = Get-Content -Raw -LiteralPath $Reset

Assert-Contains $wrapperText '[string]$Action = "Preflight"' "Default action must be read-only."
Assert-Contains $wrapperText '$ResetConfirmation = "RESET PRELAUNCH MAGICMUSICCRM TO ZERO"' "Apply must require an exact confirmation phrase."
Assert-Contains $wrapperText 'New-EncryptedBackup' "Reset must create an encrypted backup."
Assert-Contains $wrapperText 'Copy-BackupOffHost' "Reset must copy the backup off-host."
Assert-Contains $wrapperText 'Test-EncryptedBackupRestore' "Reset must restore-check the exact backup."
Assert-Contains $wrapperText 'Stop-ApplicationRuntime' "Reset must stop writers before mutation."
Assert-Contains $wrapperText 'Reset-StorageAndCache' "Reset must clear non-database state."
Assert-Contains $wrapperText 'Test-CommerceReconciliation' "Reset must reconcile after mutation."
Assert-Contains $wrapperText 'bash ''$BackupRoot/../infra/scripts/backup-staging.sh''' "Backup must run through bash even without an executable bit."
Assert-Contains $wrapperText 'set -a' "Restore-check must export the backup environment for openssl."
Assert-Contains $wrapperText '$verifyTemplate = @''' "Backup verification must use a literal remote-command template."
Assert-True (-not $wrapperText.Contains('" + ''"$bytes" "$hash"''')) "Backup verification must not concatenate shell arguments at invocation time."
Assert-Contains $wrapperText 'docker start magicmusiccrm-v3-api-1 magicmusiccrm-v3-caddy-1' "Restart must preserve the exact release containers."
Assert-True (-not $wrapperText.Contains('docker compose --env-file .env up -d api caddy')) "Reset must not recreate API from the base compose file."

$backupIndex = $wrapperText.LastIndexOf('$backup = New-EncryptedBackup')
$restoreIndex = $wrapperText.LastIndexOf('Test-EncryptedBackupRestore -BackupPath $backup.Path')
$stopIndex = $wrapperText.LastIndexOf('Stop-ApplicationRuntime')
$sqlIndex = $wrapperText.LastIndexOf('Invoke-RemoteSql -SqlPath $ResetSql')
Assert-True ($backupIndex -ge 0 -and $restoreIndex -gt $backupIndex) "Restore-check must follow backup."
Assert-True ($stopIndex -gt $restoreIndex -and $sqlIndex -gt $stopIndex) "Mutation must follow backup, restore-check and writer stop."

foreach ($text in @($preflightText, $resetText)) {
  Assert-Contains $text '0132_app_registration_source' "Reset must be pinned to migration 0132."
  Assert-Contains $text 'kvazar2727@gmail.com' "System administrator allowlist is missing."
  Assert-Contains $text 'yfnfkb5957@mail.ru' "Director allowlist is missing."
  Assert-Contains $text 'announcements' "System announcements chat must be guarded."
  Assert-Contains $text 'Приложение' "System application source must be guarded."
}

Assert-Contains $preflightText 'retained_custom_field_count <> 40' "Preflight must retain exactly 40 custom fields."
Assert-Contains $preflightText "field_key = 'hollihopId' and deleted_at is null) > 1" "Preflight must accept the post-reset absence of HolliHop ID while rejecting duplicates."
Assert-Contains $resetText "field_key = 'hollihopId'" "HolliHop ID must be removed."
Assert-Contains $resetText 'reset_keep_custom_fields' "Retained custom fields must be captured and post-checked."
Assert-Contains $resetText 'retained password hash changed' "Credentials must be post-checked."
Assert-Contains $resetText 'system registry or legal document baseline changed' "System registry must be post-checked."
Assert-Contains $resetText 'begin isolation level repeatable read' "Reset must be one repeatable-read transaction."
Assert-Contains $resetText 'lock table app.users in access exclusive mode' "Reset must lock the identity root."
Assert-Contains $resetText 'restart identity cascade' "Immutable test facts must be truncated transactionally."
Assert-Contains $resetText "'system.prelaunch_reset_applied'" "The clean database must retain one reset audit fact."

$checkOutput = & $Wrapper -CheckOnly 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Wrapper -CheckOnly failed."
Assert-True (($checkOutput -join "`n") -match 'CHECK_ONLY\|OK\|prelaunch-reset') "Check-only success record is missing."

Write-Host "PRELAUNCH_RESET_CONTRACT_TESTS|OK"
