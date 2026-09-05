[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CandidateImage,
  [Parameter(Mandatory)][string]$RollbackImage,
  [Parameter(Mandatory)][string]$ExpectedMigrationId,
  [string]$BackupPath,
  [string]$BackupSecretFile,
  [string]$MigrationBaseline,
  [string]$EvidencePath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backupRoot = Join-Path $repoRoot 'dist/backups'
if (-not $BackupPath) {
  $archive = Get-ChildItem -LiteralPath $backupRoot -File -Filter '*.tgz.enc' |
    Where-Object { Test-Path -LiteralPath ($_.FullName + '.sha256') } |
    Sort-Object Name -Descending | Select-Object -First 1
  if (-not $archive) { throw 'No encrypted archive with a checksum exists in dist/backups.' }
  $BackupPath = $archive.FullName
}
$backup = (Resolve-Path -LiteralPath $BackupPath).Path
if (-not $backup.EndsWith('.tgz.enc')) { throw 'Expected a .tgz.enc backup.' }
if (-not $BackupSecretFile) { $BackupSecretFile = Join-Path $repoRoot 'infra/staging/.backup.env' }
$secret = (Resolve-Path -LiteralPath $BackupSecretFile).Path
if (-not $EvidencePath) { $EvidencePath = Join-Path $repoRoot ('dist/backup-drills/' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force -Path $EvidencePath | Out-Null
$evidence = (Resolve-Path -LiteralPath $EvidencePath).Path
function Read-Image([string]$Image) {
  if ($Image -notmatch '^magicmusiccrm-server:[a-zA-Z0-9_.+-]+$') { throw 'Only local CRM image tags are allowed.' }
  $raw = & docker image inspect $Image
  if ($LASTEXITCODE -ne 0) { throw "Local image is missing: $Image" }
  return ($raw | ConvertFrom-Json)[0]
}
$candidate = Read-Image $CandidateImage
$rollback = Read-Image $RollbackImage
$toolImage = 'magiccrm-backup-drill-tools:local'
& docker build --quiet --tag $toolImage (Join-Path $repoRoot 'infra/backup-drill-tools')
if ($LASTEXITCODE -ne 0) { throw 'Backup drill tooling build failed.' }
$scriptFile = Join-Path $repoRoot 'infra/scripts/verify-release-backup-compatibility.sh'
$arguments = @('run', '--rm', '--pull', 'never', '--network', 'none', '--read-only',
  '--tmpfs', '/private:rw,nosuid,nodev,mode=0700', '--tmpfs', '/tmp:rw,nosuid,nodev',
  '--mount', 'type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock',
  '--mount', "type=bind,source=$scriptFile,target=/drill/verify-release-backup-compatibility.sh,readonly",
  '--mount', "type=bind,source=$(Split-Path -Parent $backup),target=/backups,readonly",
  '--mount', "type=bind,source=$secret,target=/backup-secret/env,readonly",
  $toolImage, '--backup', ('/backups/' + (Split-Path -Leaf $backup)),
  '--candidate-image', $CandidateImage, '--candidate-revision', $candidate.Config.Labels.'org.opencontainers.image.revision',
  '--candidate-version', $candidate.Config.Labels.'org.opencontainers.image.version',
  '--rollback-image', $RollbackImage, '--rollback-revision', $rollback.Config.Labels.'org.opencontainers.image.revision',
  '--rollback-version', $rollback.Config.Labels.'org.opencontainers.image.version',
  '--expected-migration', $ExpectedMigrationId)
if ($MigrationBaseline) {
  $baseline = (Resolve-Path -LiteralPath $MigrationBaseline).Path
  if (-not $baseline.EndsWith('.json')) { throw 'Expected a reviewed JSON migration baseline.' }
  # This mount belongs to the helper; the inner isolated command receives only
  # the reviewed hash manifest, never a host database or secret configuration.
  $toolIndex = [Array]::IndexOf($arguments, $toolImage)
  $arguments = @($arguments[0..($toolIndex - 1)]) + @('--mount', "type=bind,source=$baseline,target=/reviewed-baseline.json,readonly") + @($arguments[$toolIndex..($arguments.Length - 1)]) + @('--migration-baseline', '/reviewed-baseline.json')
}
$started = Get-Date
& docker @arguments *> (Join-Path $evidence 'restore.log')
$exitCode = $LASTEXITCODE
$result = [ordered]@{ status = $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' });
  finishedAt = (Get-Date).ToUniversalTime().ToString('o');
  archive = (Split-Path -Leaf $backup); sha256 = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash;
  archiveAgeDays = [math]::Round(((Get-Date) - (Get-Item -LiteralPath $backup).LastWriteTime).TotalDays, 2);
  candidateImageId = $candidate.Id; rollbackImageId = $rollback.Id;
  migrationBaselineSha256 = $(if ($MigrationBaseline) { (Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash } else { $null });
  durationSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 2);
  scope = 'Encrypted local copy; existing isolated Docker restore/migration/reconciliation/rollback drill. No live database writes.' }
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding utf8NoBOM
Write-Output "Encrypted backup drill: $($result.status). Evidence: $evidence"
if ($exitCode -ne 0) { throw 'Encrypted backup restore failed; inspect restore.log.' }
