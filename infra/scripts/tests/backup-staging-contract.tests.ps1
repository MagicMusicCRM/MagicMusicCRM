$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\backup-staging.sh"
$scriptText = Get-Content -Raw -LiteralPath $scriptPath

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $scriptText.Contains($Needle)) {
    throw $Message
  }
}

Assert-Contains `
  'compose=(docker compose --env-file "${ENV_FILE}")' `
  "Backup must let Docker Compose parse the dotenv file."
Assert-Contains `
  'sh -ceu ''printf %s "$POSTGRES_USER"''' `
  "Backup must obtain the owner role from the PostgreSQL container."
Assert-Contains `
  'pg_dump -U "${postgres_owner_user}" -d "${postgres_db}"' `
  "Backup must use the container-derived database identity."
Assert-Contains `
  '-aes-256-cbc -pbkdf2 -iter 600000 -salt' `
  "Backup encryption strength must remain explicit."
Assert-Contains `
  'sha256sum "${out_file}" > "${out_file}.sha256"' `
  "Encrypted backups must retain a sidecar checksum."
Assert-Contains `
  '--mount "type=bind,src=${STORAGE_DIR},dst=/storage,readonly"' `
  "Storage backup must read the protected runtime mount without changing its permissions."
Assert-Contains `
  '--network none' `
  "The storage snapshot helper must remain network-isolated."
Assert-Contains `
  '--read-only' `
  "The storage snapshot helper filesystem must remain read-only."

if ($scriptText -match '(?m)^\s*\.\s+"\$\{ENV_FILE\}"\s*$') {
  throw "Docker dotenv must never be executed as a Bash program."
}

Write-Output "backup-staging contract: PASS"
