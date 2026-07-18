[CmdletBinding()]
param(
  [ValidateSet("Preflight", "Reset", "EnsureSupport")]
  [string]$Action = "Preflight",
  [switch]$Apply,
  [switch]$CreateMissingSupport,
  [string]$Confirm = "",
  [string]$Remote = "magicdeploy@161.104.49.153",
  [string]$SshKey = "C:/Users/potyl/.ssh/mmcrm_proxy_ed25519",
  [string]$Container = "magicmusiccrm-v3-postgres-1",
  [string]$Database = "magiccrm",
  [string]$DatabaseUser = "magiccrm_owner",
  [string]$BackupDir = "/opt/magicmusiccrm/backups",
  [string]$HealthUrl = "https://api.magicmusiccrm.ru/api/health",
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AllowedEmail = "magic1@gmail.com"
$AllowedRemote = "magicdeploy@161.104.49.153"
$AllowedBackupDir = "/opt/magicmusiccrm/backups"
$ResetConfirmation = "RESET DEMO magic1@gmail.com"
$SupportConfirmation = "ENSURE DEMO SUPPORT magic1@gmail.com"
$SqlRoot = Join-Path $PSScriptRoot "sql"
$PreflightSql = Join-Path $SqlRoot "preflight.sql"
$ResetSql = Join-Path $SqlRoot "reset.sql"
$SupportSql = Join-Path $SqlRoot "ensure-support.sql"

function Write-Step {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host "==> $Message"
}

function Assert-SafeConfiguration {
  if ($Remote -ne $AllowedRemote) {
    throw "Remote '$Remote' is not allowlisted. Expected exactly '$AllowedRemote'."
  }
  if ($Container -ne "magicmusiccrm-v3-postgres-1") {
    throw "Container '$Container' is not allowlisted."
  }
  if ($Database -ne "magiccrm" -or $DatabaseUser -ne "magiccrm_owner") {
    throw "Database target is not allowlisted."
  }
  if ($HealthUrl -ne "https://api.magicmusiccrm.ru/api/health") {
    throw "Health URL '$HealthUrl' is not allowlisted."
  }
  if ($BackupDir -ne $AllowedBackupDir) {
    throw "Backup directory '$BackupDir' is not allowlisted."
  }
  if (-not (Test-Path -LiteralPath $SshKey -PathType Leaf)) {
    throw "SSH key was not found: $SshKey"
  }
  foreach ($path in @($PreflightSql, $ResetSql, $SupportSql)) {
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

  # Keep the remote command line short: Windows rejects the reset SQL when it
  # is base64-encoded into argv. Do not use PowerShell's native pipeline here;
  # Windows PowerShell 5.1 may transcode or truncate a very long string.
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
  $started = $process.Start()
  if (-not $started) {
    throw "Failed to start ssh.exe."
  }

  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $stdinBytes = [Text.Encoding]::ASCII.GetBytes($StdinText)
  $stdinStream = $process.StandardInput.BaseStream
  $stdinStream.Write($stdinBytes, 0, $stdinBytes.Length)
  $stdinStream.Flush()
  $stdinStream.Close()
  $process.WaitForExit()
  $stdout = $stdoutTask.Result
  $stderr = $stderrTask.Result
  $exitCode = $process.ExitCode
  $process.Dispose()

  $output = @(
    @($stdout -split '\r?\n') | Where-Object { $_ -ne "" }
  )
  $errors = @(
    @($stderr -split '\r?\n') | Where-Object { $_ -ne "" }
  )
  if ($exitCode -ne 0 -or $errors.Count -gt 0) {
    $details = (@($output) + @($errors)) -join [Environment]::NewLine
    throw "Remote command failed or wrote to stderr (exit code $exitCode).`n$details"
  }
  return @($output)
}

function Invoke-RemoteSql {
  param([Parameter(Mandatory = $true)][string]$SqlPath)

  # Windows PowerShell 5.1 treats BOM-less UTF-8 as the active ANSI code page.
  # Read explicitly as UTF-8 so Russian dictionary/resource guards remain exact.
  $sql = [IO.File]::ReadAllText($SqlPath, [Text.Encoding]::UTF8)
  # The native PowerShell pipeline can still transcode non-ASCII characters on
  # Windows PowerShell 5.1. Transfer ASCII-only base64 via stdin and decode it
  # remotely so the SQL reaches psql byte-for-byte while staying out of argv.
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
  # .NET Framework's redirected StandardInput writes a UTF-8 BOM before the
  # ASCII payload. Those byte values cannot occur in base64, so strip them on
  # the remote side before decoding.
  $command = "LC_ALL=C tr -d '\357\273\277' | base64 -d | docker exec -i $Container psql -X -v ON_ERROR_STOP=1 -U $DatabaseUser -d $Database -At -F '|'"
  return Invoke-SshCommandWithInput -Command $command -StdinText $encoded
}

function Invoke-Preflight {
  param([switch]$RequireReady)

  Write-Step "Read-only preflight for the exact four demo accounts"
  $lines = @(Invoke-RemoteSql -SqlPath $PreflightSql)
  $lines | ForEach-Object { Write-Host $_ }
  $blockers = @($lines | Where-Object { $_ -match '^BLOCKER\|' })
  if ($RequireReady -and $blockers.Count -gt 0) {
    throw "Demo preflight has $($blockers.Count) blocker(s). Run EnsureSupport explicitly or resolve them manually."
  }
  return $blockers
}

function New-VerifiedBackup {
  $template = @'
set -eu
set -o pipefail
umask 077
ts=$(date -u +%Y%m%dT%H%M%SZ)
file="__BACKUP_DIR__/magiccrm-pre-demo-magic1-${ts}.sql.gz"
docker exec __CONTAINER__ pg_dump -U __DB_USER__ -d __DATABASE__ --no-owner --no-privileges | gzip -9 > "$file"
test -s "$file"
gzip -t "$file"
bytes=$(wc -c < "$file" | tr -d ' ')
hash=$(sha256sum "$file" | awk '{print $1}')
printf 'BACKUP|%s|%s|%s\n' "$file" "$bytes" "$hash"
'@
  $command = $template.Replace("__BACKUP_DIR__", $BackupDir).
    Replace("__CONTAINER__", $Container).
    Replace("__DB_USER__", $DatabaseUser).
    Replace("__DATABASE__", $Database)

  Write-Step "Create and verify a full PostgreSQL backup"
  $output = @(Invoke-SshCommand -Command $command)
  $backupLine = $output | Where-Object { $_ -match '^BACKUP\|' } | Select-Object -Last 1
  if (-not $backupLine) {
    throw "Backup command did not return a verification record."
  }
  $parts = $backupLine -split '\|'
  if ($parts.Count -ne 4) {
    throw "Malformed backup verification record."
  }
  $bytes = 0L
  if (-not [long]::TryParse($parts[2], [ref]$bytes) -or $bytes -lt 1024) {
    throw "Backup is unexpectedly small: $($parts[2]) bytes."
  }
  if ($parts[3] -notmatch '^[a-fA-F0-9]{64}$') {
    throw "Backup SHA-256 is malformed."
  }
  Write-Host "Verified backup: $($parts[1])"
  Write-Host "Bytes: $bytes"
  Write-Host "SHA-256: $($parts[3])"
  return $parts[1]
}

function Test-ApiHealth {
  Write-Step "Verify public API health"
  $response = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 20
  if ($response.StatusCode -ne 200) {
    throw "Health endpoint returned HTTP $($response.StatusCode)."
  }
  Write-Host "HEALTH|OK|$HealthUrl"
}

function Assert-Confirmation {
  param([Parameter(Mandatory = $true)][string]$Expected)
  if ($Confirm -cne $Expected) {
    throw "Apply requires -Confirm '$Expected'."
  }
}

if ($CheckOnly) {
  foreach ($path in @($PreflightSql, $ResetSql, $SupportSql)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required SQL file was not found: $path"
    }
  }
  Write-Output "CHECK_ONLY|OK|$AllowedEmail"
  exit 0
}

Assert-SafeConfiguration

if ($Apply -and $Action -eq "Preflight") {
  throw "Preflight is always read-only; remove -Apply."
}
if ($CreateMissingSupport -and $Action -ne "EnsureSupport") {
  throw "-CreateMissingSupport is valid only with -Action EnsureSupport."
}

switch ($Action) {
  "Preflight" {
    [void](Invoke-Preflight -RequireReady)
    Test-ApiHealth
  }
  "EnsureSupport" {
    [void](Invoke-Preflight)
    if (-not $Apply) {
      Write-Host "DRY_RUN|EnsureSupport|No database writes or backup were performed."
      Write-Host "To apply: -Action EnsureSupport -Apply -CreateMissingSupport -Confirm '$SupportConfirmation'"
      break
    }
    if (-not $CreateMissingSupport) {
      throw "Support apply requires the explicit -CreateMissingSupport switch."
    }
    Assert-Confirmation -Expected $SupportConfirmation
    [void](New-VerifiedBackup)
    Write-Step "Create only missing demo support records"
    Invoke-RemoteSql -SqlPath $SupportSql | ForEach-Object { Write-Host $_ }
    [void](Invoke-Preflight -RequireReady)
    Test-ApiHealth
  }
  "Reset" {
    [void](Invoke-Preflight)
    if (-not $Apply) {
      Write-Host "DRY_RUN|Reset|No database writes or backup were performed."
      Write-Host "Scope: exact CRM graph and private administration-chat messages for $AllowedEmail."
      Write-Host "To apply: -Action Reset -Apply -Confirm '$ResetConfirmation'"
      break
    }
    Assert-Confirmation -Expected $ResetConfirmation
    [void](Invoke-Preflight -RequireReady)
    [void](New-VerifiedBackup)
    Write-Step "Apply the guarded magic1 demo reset"
    Invoke-RemoteSql -SqlPath $ResetSql | ForEach-Object { Write-Host $_ }
    [void](Invoke-Preflight -RequireReady)
    Test-ApiHealth
  }
}
