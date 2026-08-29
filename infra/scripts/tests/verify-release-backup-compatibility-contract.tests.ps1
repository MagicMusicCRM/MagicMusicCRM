$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptPath = Join-Path $PSScriptRoot "..\verify-release-backup-compatibility.sh"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  throw "Reusable release backup compatibility script is missing: $scriptPath"
}

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

function Assert-Before {
  param(
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $firstIndex = $scriptText.IndexOf($First, [StringComparison]::Ordinal)
  $secondIndex = $scriptText.IndexOf($Second, [StringComparison]::Ordinal)
  if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
    throw $Message
  }
}

Assert-Contains 'set -Eeuo pipefail' `
  'The drill must fail closed on shell, pipeline and function errors.'
Assert-Contains 'BACKUP_ROOT="${BACKUP_ROOT:-/opt/magicmusiccrm/backups/encrypted}"' `
  'Only the encrypted production backup root may be accepted by default.'
Assert-Contains 'backup_archive="$(realpath -e -- "${backup_archive}")"' `
  'The exact backup path must be resolved before any resource is created.'
Assert-Contains '[[ "${backup_archive}" == "${backup_root_real}/"* ]]' `
  'Resolved backup paths must remain below the encrypted backup root.'
Assert-Contains 'actual_encrypted_sha="$(sha256sum -- "${backup_archive}")"' `
  'The encrypted sidecar checksum must be verified before decryption.'
Assert-Contains 'read_backup_passphrase()' `
  'The backup passphrase must be parsed as data, never sourced as shell code.'
Assert-Contains 'backup secret file contains an unexpected key or shell syntax' `
  'Unexpected dotenv keys and shell statements must be rejected.'
Assert-Contains '[[ "${backup_env_mode}" == 400 || "${backup_env_mode}" == 600 ]]' `
  'The backup secret file must reject group, world and executable modes.'
Assert-Contains 'backup secret file must be owned by the current user' `
  'The backup secret owner must be validated before reading it.'
Assert-Contains 'unset BACKUP_ENV' `
  'The backup secret file path must not enter the decrypt process environment.'
Assert-Contains 'BACKUP_PASSPHRASE="${backup_passphrase}"' `
  'Only the strictly parsed passphrase may enter the OpenSSL process.'
Assert-Contains '-d -aes-256-cbc -pbkdf2 -iter 600000' `
  'Decryption parameters must match backup-staging.sh.'
Assert-Contains 'sha256sum -c --strict --quiet SHA256SUMS' `
  'Every internal payload checksum must be verified.'
Assert-Contains 'run_bounded "${ARCHIVE_TIMEOUT_SECONDS}" "verify internal backup checksum"' `
  'Internal checksum verification must be interruptible and archive-time bounded.'
Assert-Contains 'docker network create --internal' `
  'The restore database must use a new internal-only Docker network.'
Assert-Contains 'docker volume create' `
  'The restore database must use a new temporary volume.'
Assert-Contains 'capture_bounded database_password "${CRYPTO_TIMEOUT_SECONDS}"' `
  'The restore database password must be random per drill.'
Assert-Contains '--pull never' `
  'The drill must use exact locally loaded images without an implicit pull.'
Assert-Contains 'org.opencontainers.image.revision' `
  'Candidate and rollback source revision labels must be validated.'
Assert-Contains 'org.opencontainers.image.version' `
  'Candidate and rollback version labels must be validated.'
Assert-Contains 'candidate and rollback revision labels must be different' `
  'Candidate and rollback source revisions must be distinct.'
Assert-Contains 'candidate and rollback version labels must be different' `
  'Candidate and rollback application versions must be distinct.'
Assert-Contains 'readonly candidate_image_id' `
  'Resolved candidate image identity must be immutable.'
Assert-Contains 'readonly rollback_image_id' `
  'Resolved rollback image identity must be immutable.'
Assert-Contains 'readonly postgres_image_id' `
  'Resolved PostgreSQL image identity must be immutable.'
Assert-Contains '"${candidate_migrate_container}" "${candidate_image_id}"' `
  'Candidate commands must run by immutable image ID, never by mutable tag.'
Assert-Contains '"${rollback_migrate_container}" "${rollback_image_id}"' `
  'Rollback commands must run by immutable image ID, never by mutable tag.'
Assert-Contains 'node dist/db/migrate.js up' `
  'Both runtime images must exercise the production migration command.'
Assert-Contains 'node dist/migration/commerce/v7/commerce-data.js' `
  'Both runtime images must exercise V7 reconciliation.'
Assert-Contains 'run_bounded()' `
  'Potentially hanging child processes must use the tracked bounded runner.'
Assert-Contains 'run_bounded_from_file()' `
  'The binary PostgreSQL archive must use a dedicated bounded file-input runner.'
Assert-Contains '"$@" <"${input_file}" &' `
  'The file-input runner must redirect the archive on the background command itself.'
Assert-Contains 'run_bounded_from_file "${RESTORE_TIMEOUT_SECONDS}" "restore PostgreSQL backup"' `
  'pg_restore must receive the verified dump through the dedicated file-input runner.'
Assert-Contains 'setsid timeout --foreground --signal=TERM' `
  'Every tracked child must have a process group and hard timeout.'
Assert-Contains 'forward_active_child "${signal_name}"' `
  'HUP, INT and TERM must be forwarded while the shell is waiting.'
Assert-Contains 'trap ''handle_signal HUP 129'' HUP' `
  'HUP must interrupt the tracked child and enter cleanup.'
Assert-Contains 'trap ''handle_signal INT 130'' INT' `
  'INT must interrupt the tracked child and enter cleanup.'
Assert-Contains 'trap ''handle_signal TERM 143'' TERM' `
  'TERM must interrupt the tracked child and enter cleanup.'
Assert-Contains 'begin transaction read only' `
  'Rollback compatibility must include the readiness database query in a read-only transaction.'
Assert-Contains 'grep -Fq ''Applied migrations: none''' `
  'The rollback image must prove that candidate schema migration is a no-op.'
Assert-Contains 'docker volume rm -f "${volume_name}"' `
  'The isolated restore volume must be removed by the exit trap.'
Assert-Contains 'rm -rf -- "${tmp_dir}"' `
  'Decrypted plaintext and restore logs must be removed by the exit trap.'

Assert-Before `
  'get_restore_migration candidate_head' `
  'node dist/migration/commerce/v7/commerce-data.js' `
  'Candidate migration head must be checked before reconciliation.'
Assert-Before `
  '"${candidate_reconcile_container}" "${candidate_image_id}"' `
  '"${rollback_migrate_container}" "${rollback_image_id}"' `
  'Candidate reconciliation must pass before rollback compatibility starts.'
Assert-Before `
  'grep -Fq ''Applied migrations: none''' `
  'get_restore_migration rollback_head' `
  'Rollback migration output must be a no-op before the unchanged head is accepted.'

$forbiddenPatterns = @(
  '(?m)docker\s+compose',
  '(?m)\bcompose\s+down\b',
  '(?m)migrate\.js\s+down',
  'magicmusiccrm-v3_postgres_data',
  '/opt/magicmusiccrm/infra/staging/docker-compose'
)
foreach ($pattern in $forbiddenPatterns) {
  if ($scriptText -match $pattern) {
    throw "Backup compatibility drill contains forbidden live-stack operation: $pattern"
  }
}

if ($scriptText -match '(?m)^\s*(source|\.)\s+"?\$\{BACKUP_ENV\}') {
  throw 'Backup secret dotenv must never be executed as Bash.'
}

$canonicalReconcilePath = 'node dist/migration/commerce/v7/commerce-data.js'
if ([regex]::Matches($scriptText, [regex]::Escape($canonicalReconcilePath)).Count -ne 2) {
  throw 'Candidate and rollback must each execute the canonical compiled V7 reconciliation path.'
}

Write-Output "verify-release-backup-compatibility contract: PASS"
