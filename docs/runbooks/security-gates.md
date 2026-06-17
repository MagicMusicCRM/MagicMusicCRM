# MagicMusicCRM v3 Security Gates

**Scope**: repeatable local and CI checks before `INT-S7` launch acceptance.

Run these checks from the repository root after backend and Flutter verification.

## 1. Local Preflight

```bash
cd server
npm run security:gate
```

The default mode fails on repository errors that can be checked locally:

- `git diff --check`
- `server/exports` and `server/storage` Git ignore coverage
- Docker build-context exclusion for `exports/`, `storage/` and `security-scans/`
- tracked or unignored runtime `.env` files
- generated source maps
- frontend runtime secret defaults
- `npm audit --audit-level=moderate`

The default mode reports missing external tools as warnings so development can
continue on a workstation that does not have the full security toolchain.

## 2. Production/CI Gate

```bash
cd server
SECURITY_GATE_STRICT=1 npm run security:gate
```

Strict mode also fails when these tools or runtime prerequisites are missing:

- `gitleaks` or equivalent history-aware secret scanning
- `semgrep` or equivalent SAST scanning
- `trivy` or equivalent dependency/container scanning
- reachable Docker daemon for image scanning

Attach the JSON output to the S7 evidence bundle.

## 3. Required Manual Evidence

The script does not replace release evidence that must be captured manually:

- Rotation confirmation for all credentials exposed during migration.
- Removal or encryption of real-data `_archive/backups/**`.
- History-aware secret/PII scan result after archive cleanup.
- Final production host evidence: `sshd -T`, UFW/listeners, Docker networks,
  backup restore drill and forced alert drill.
- Android runtime/UI smoke for auth, dashboard, messenger, files and account
  deletion.

Do not close `INT-S7` until all manual evidence is attached and the strict gate
is clean.
