[CmdletBinding()]
param(
  [ValidateSet("Preflight", "Reset")]
  [string]$Action = "Preflight",
  [switch]$Apply,
  [string]$Confirm = "",
  [string]$Remote = "magicdeploy@161.104.49.153",
  [string]$SshKey = (Join-Path $env:USERPROFILE ".ssh/mmcrm_proxy_ed25519"),
  [string]$Container = "magicmusiccrm-v3-postgres-1",
  [string]$Database = "magiccrm",
  [string]$DatabaseUser = "magiccrm_owner",
  [string]$StackDir = "/opt/magicmusiccrm/infra/staging",
  [string]$BackupRoot = "/opt/magicmusiccrm/backups",
  [string]$StorageDir = "/opt/magicmusiccrm/storage",
  [string]$HealthUrl = "https://api.magicmusiccrm.ru/api/health/ready",
  [string]$OffHostBackupDir = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "MagicMusicCRM Backups"),
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AllowedRemote = "magicdeploy@161.104.49.153"
$AllowedContainer = "magicmusiccrm-v3-postgres-1"
$AllowedDatabase = "magiccrm"
$AllowedDatabaseUser = "magiccrm_owner"
$AllowedStackDir = "/opt/magicmusiccrm/infra/staging"
$AllowedBackupRoot = "/opt/magicmusiccrm/backups"
$AllowedStorageDir = "/opt/magicmusiccrm/storage"
$AllowedHealthUrl = "https://api.magicmusiccrm.ru/api/health/ready"
$ResetConfirmation = "RESET PRELAUNCH MAGICMUSICCRM TO ZERO"
$SqlRoot = Join-Path $PSScriptRoot "sql"
$PreflightSql = Join-Path $SqlRoot "preflight.sql"
$ResetSql = Join-Path $SqlRoot "reset.sql"

function Write-Step {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "==> $Message"
}

function Assert-NativeSuccess {
  param([Parameter(Mandatory = $true)][string]$Operation)
  if ($LASTEXITCODE -ne 0) {
    throw "$Operation failed with exit code $LASTEXITCODE."
  }
}

function Assert-SafeConfiguration {
  if ($Remote -ne $AllowedRemote) {
    throw "Remote '$Remote' is not allowlisted."
  }
  if ($Container -ne $AllowedContainer) {
    throw "Container '$Container' is not allowlisted."
  }
  if ($Database -ne $AllowedDatabase -or $DatabaseUser -ne $AllowedDatabaseUser) {
    throw "Database target is not allowlisted."
  }
  if ($StackDir -ne $AllowedStackDir -or $BackupRoot -ne $AllowedBackupRoot) {
    throw "Stack or backup directory is not allowlisted."
  }
  if ($StorageDir -ne $AllowedStorageDir) {
    throw "Storage directory is not allowlisted."
  }
  if ($HealthUrl -ne $AllowedHealthUrl) {
    throw "Health URL is not allowlisted."
  }
  if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) {
    throw "SSH key was not found: $SshKey"
  }
  foreach ($path in @($PreflightSql, $ResetSql)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required SQL file was not found: $path"
    }
  }
}

function Invoke-SshCommand {
  param([Parameter(Mandatory = $true)][string]$Command)

  $output = & ssh `
    -i $SshKey `
    -o BatchMode=yes `
    -o ConnectTimeout=10 `
    $Remote `
    $Command 2>&1
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "Remote command failed with exit code $exitCode.`n$details"
  }
  return @($output | ForEach-Object { $_.ToString() })
}

function Invoke-SshCommandWithInput {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [Parameter(Mandatory = $true)][string]$StdinText
  )

  $escapedCommand = $Command.Replace('"', '\"')
  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = "ssh.exe"
  $startInfo.Arguments = "-i `"$SshKey`" -o BatchMode=yes -o ConnectTimeout=10 $Remote `"$escapedCommand`""
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true

  $process = New-Object Diagnostics.Process
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    throw "Failed to start ssh.exe."
  }
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $stdinBytes = [Text.Encoding]::ASCII.GetBytes($StdinText)
  $process.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
  $process.StandardInput.BaseStream.Flush()
  $process.StandardInput.BaseStream.Close()
  $process.WaitForExit()
  $stdout = $stdoutTask.Result
  $stderr = $stderrTask.Result
  $exitCode = $process.ExitCode
  $process.Dispose()

  $lines = @(@($stdout -split '\r?\n') | Where-Object { $_ -ne "" })
  $errors = @(@($stderr -split '\r?\n') | Where-Object { $_ -ne "" })
  if ($exitCode -ne 0 -or $errors.Count -gt 0) {
    $details = (@($lines) + @($errors)) -join [Environment]::NewLine
    throw "Remote command failed or wrote to stderr (exit code $exitCode).`n$details"
  }
  return $lines
}

function Invoke-RemoteSql {
  param([Parameter(Mandatory = $true)][string]$SqlPath)

  $sql = [IO.File]::ReadAllText($SqlPath, [Text.Encoding]::UTF8)
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
  $command = "LC_ALL=C tr -d '\357\273\277' | base64 -d | docker exec -i $Container psql -X -v ON_ERROR_STOP=1 -U $DatabaseUser -d $Database -At -F '|'"
  return Invoke-SshCommandWithInput -Command $command -StdinText $encoded
}

function Invoke-Preflight {
  Write-Step "Read-only preflight for the exact prelaunch reset target"
  $lines = @(Invoke-RemoteSql -SqlPath $PreflightSql)
  $lines | ForEach-Object { Write-Host $_ }
  if (-not ($lines | Where-Object { $_ -match '^PREFLIGHT\|OK\|0132_app_registration_source$' })) {
    throw "Preflight did not return the expected migration-pinned success record."
  }
}

function New-EncryptedBackup {
  Write-Step "Create the encrypted database + storage backup"
  $output = @(Invoke-SshCommand -Command "bash '$BackupRoot/../infra/scripts/backup-staging.sh'")
  $backupPath = $output | Where-Object {
    $_ -match '^/opt/magicmusiccrm/backups/encrypted/[A-Za-z0-9._-]+\.tgz\.enc$'
  } | Select-Object -Last 1
  if (-not $backupPath) {
    throw "Backup script did not return an allowlisted encrypted backup path."
  }

  $verify = @(Invoke-SshCommand -Command "set -eu; test -s '$backupPath'; sha256sum -c '$backupPath.sha256'; bytes=`$(wc -c < '$backupPath' | tr -d ' '); hash=`$(sha256sum '$backupPath' | awk '{print `$1}'); printf 'BACKUP|%s|%s|%s\n' '$backupPath' " + '"$bytes" "$hash"')
  $record = $verify | Where-Object { $_ -match '^BACKUP\|' } | Select-Object -Last 1
  if (-not $record) {
    throw "Encrypted backup verification record is missing."
  }
  $parts = $record -split '\|'
  $bytes = 0L
  if ($parts.Count -ne 4 -or -not [long]::TryParse($parts[2], [ref]$bytes) -or $bytes -lt 1024) {
    throw "Encrypted backup verification record is malformed."
  }
  if ($parts[3] -notmatch '^[a-fA-F0-9]{64}$') {
    throw "Encrypted backup SHA-256 is malformed."
  }
  Write-Host "BACKUP_VERIFIED|$backupPath|$bytes|$($parts[3])"
  return @{
    Path = $backupPath
    Hash = $parts[3].ToLowerInvariant()
    Bytes = $bytes
  }
}

function Copy-BackupOffHost {
  param([Parameter(Mandatory = $true)][hashtable]$Backup)

  Write-Step "Copy the encrypted backup off-host and verify SHA-256"
  if (-not (Test-Path -LiteralPath $OffHostBackupDir -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $OffHostBackupDir -Force)
  }
  $name = Split-Path -Leaf $Backup.Path
  $destination = Join-Path $OffHostBackupDir $name
  & scp -i $SshKey -o BatchMode=yes "$Remote`:$($Backup.Path)" $destination
  Assert-NativeSuccess -Operation "Off-host backup copy"
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash.ToLowerInvariant()
  if ($hash -ne $Backup.Hash) {
    throw "Off-host backup SHA-256 mismatch."
  }
  Write-Host "OFF_HOST_BACKUP|OK|$destination|$hash"
}

function Test-EncryptedBackupRestore {
  param([Parameter(Mandatory = $true)][string]$BackupPath)

  Write-Step "Restore the encrypted backup into an isolated PostgreSQL container"
  if ($BackupPath -notmatch '^/opt/magicmusiccrm/backups/encrypted/[A-Za-z0-9._-]+\.tgz\.enc$') {
    throw "Restore-check backup path is not allowlisted."
  }
  $template = @'
set -euo pipefail
backup='__BACKUP_PATH__'
backup_env='__STACK_DIR__/.backup.env'
tmp=$(mktemp -d)
container="mmcrm-prelaunch-restore-$(date -u +%Y%m%dT%H%M%SZ)-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT
set -a
. "$backup_env"
set +a
: "${BACKUP_PASSPHRASE:?missing backup passphrase}"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -in "$backup" -out "$tmp/payload.tgz" -pass env:BACKUP_PASSPHRASE
mkdir -p "$tmp/payload"
tar -C "$tmp/payload" -xzf "$tmp/payload.tgz"
(cd "$tmp/payload" && sha256sum -c SHA256SUMS >/dev/null)
docker run -d --name "$container" \
  -e POSTGRES_PASSWORD=prelaunch_restore_only \
  -e POSTGRES_DB=magiccrm_restore postgres:16.4-alpine >/dev/null
ready=0
for attempt in $(seq 1 60); do
  if docker exec "$container" pg_isready -U postgres -d magiccrm_restore >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
test "$ready" = 1
docker exec -i "$container" pg_restore -U postgres -d magiccrm_restore \
  --no-owner --no-privileges < "$tmp/payload/postgres.dump"
migration=$(docker exec "$container" psql -U postgres -d magiccrm_restore -Atc \
  "select id from public.app_schema_migrations order by id desc limit 1")
users=$(docker exec "$container" psql -U postgres -d magiccrm_restore -Atc \
  "select count(*) from app.users")
retained=$(docker exec "$container" psql -U postgres -d magiccrm_restore -Atc \
  "select count(*) from app.users where lower(email) in ('kvazar2727@gmail.com','yfnfkb5957@mail.ru')")
test "$retained" = 2
printf 'RESTORE_CHECK|OK|%s|%s|%s\n' "$migration" "$users" "$retained"
'@
  $command = $template.Replace("__BACKUP_PATH__", $BackupPath).
    Replace("__STACK_DIR__", $StackDir)
  $output = @(Invoke-SshCommand -Command $command)
  $output | ForEach-Object { Write-Host $_ }
  if (-not ($output | Where-Object { $_ -match '^RESTORE_CHECK\|OK\|' })) {
    throw "Isolated restore-check did not return success."
  }
}

function Stop-ApplicationRuntime {
  Write-Step "Stop API and public proxy for the reset transaction"
  [void](Invoke-SshCommand -Command "set -eu; cd '$StackDir'; docker compose --env-file .env stop caddy api")
}

function Reset-StorageAndCache {
  Write-Step "Quarantine old uploaded files and clear Redis cache"
  $template = @'
set -euo pipefail
storage='__STORAGE_DIR__'
backup_root='__BACKUP_ROOT__'
case "$storage" in
  /opt/magicmusiccrm/storage) ;;
  *) echo "unsafe storage target" >&2; exit 1 ;;
esac
resolved_parent=$(realpath -m "$(dirname "$storage")")
test "$resolved_parent" = '/opt/magicmusiccrm'
ts=$(date -u +%Y%m%dT%H%M%SZ)
quarantine="$backup_root/quarantine/prelaunch-storage-$ts"
mkdir -p "$(dirname "$quarantine")"
if [ -d "$storage" ]; then
  mv "$storage" "$quarantine"
fi
mkdir -p "$storage/private"
chown -R 10001:10001 "$storage"
chmod 700 "$storage" "$storage/private"
cd '__STACK_DIR__'
docker compose --env-file .env exec -T redis redis-cli FLUSHALL >/dev/null
printf 'STORAGE_RESET|OK|%s\n' "$quarantine"
'@
  $command = $template.Replace("__STORAGE_DIR__", $StorageDir).
    Replace("__BACKUP_ROOT__", $BackupRoot).
    Replace("__STACK_DIR__", $StackDir)
  Invoke-SshCommand -Command $command | ForEach-Object { Write-Host $_ }
}

function Start-ApplicationRuntime {
  Write-Step "Start API and public proxy"
  [void](Invoke-SshCommand -Command "set -eu; cd '$StackDir'; docker compose --env-file .env up -d storage-init; docker compose --env-file .env up -d api caddy")
}

function Test-ApiHealth {
  Write-Step "Wait for public readiness"
  for ($attempt = 1; $attempt -le 40; $attempt++) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 10
      if ($response.StatusCode -eq 200) {
        Write-Host "HEALTH|OK|$HealthUrl"
        return
      }
    } catch {
      if ($attempt -eq 40) { throw }
    }
    Start-Sleep -Seconds 3
  }
  throw "API readiness did not recover."
}

function Test-CommerceReconciliation {
  Write-Step "Run post-reset commerce reconciliation"
  $template = @'
set -eu
cd '__STACK_DIR__'
output=$(docker compose --env-file .env exec -T api node dist/platform/v7-commerce-data.js)
printf '%s\n' "$output"
printf '%s' "$output" | grep -Fq '"issues":[]'
'@
  $command = $template.Replace("__STACK_DIR__", $StackDir)
  Invoke-SshCommand -Command $command | ForEach-Object { Write-Host $_ }
}

if ($CheckOnly) {
  foreach ($path in @($PreflightSql, $ResetSql)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required SQL file was not found: $path"
    }
  }
  Write-Output "CHECK_ONLY|OK|prelaunch-reset"
  exit 0
}

Assert-SafeConfiguration

if ($Apply -and $Action -eq "Preflight") {
  throw "Preflight is always read-only; remove -Apply."
}

switch ($Action) {
  "Preflight" {
    Invoke-Preflight
    Test-ApiHealth
  }
  "Reset" {
    Invoke-Preflight
    if (-not $Apply) {
      Write-Host "DRY_RUN|Reset|No backup, service stop, storage move, cache flush or database write was performed."
      Write-Host "RETAIN|system_admin=1|director=1|system_fields=10|custom_fields=40|source=Приложение|chat=Объявления"
      Write-Host "REMOVE|clients|other_people|organization|schedule|commerce|messages|tasks|uploads|hollihopId"
      Write-Host "To apply after release 0132: -Action Reset -Apply -Confirm '$ResetConfirmation'"
      break
    }
    if ($Confirm -cne $ResetConfirmation) {
      throw "Apply requires -Confirm '$ResetConfirmation'."
    }

    $backup = New-EncryptedBackup
    Copy-BackupOffHost -Backup $backup
    Test-EncryptedBackupRestore -BackupPath $backup.Path

    $runtimeStopped = $false
    try {
      Stop-ApplicationRuntime
      $runtimeStopped = $true
      Write-Step "Apply the guarded prelaunch reset transaction"
      Invoke-RemoteSql -SqlPath $ResetSql | ForEach-Object { Write-Host $_ }
      Reset-StorageAndCache
      Start-ApplicationRuntime
      $runtimeStopped = $false
    } finally {
      if ($runtimeStopped) {
        Start-ApplicationRuntime
      }
    }

    Test-ApiHealth
    Invoke-Preflight
    Test-CommerceReconciliation
    Write-Host "PRELAUNCH_RESET|COMPLETE|backup=$($backup.Path)|sha256=$($backup.Hash)"
  }
}
