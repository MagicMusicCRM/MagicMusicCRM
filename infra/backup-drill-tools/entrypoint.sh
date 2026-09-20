#!/bin/sh
set -eu
umask 077
# Legacy backup configuration also contains storage paths. Pass only the key
# accepted by the existing strict parser; never source shell configuration.
grep '^BACKUP_PASSPHRASE=' /backup-secret/env > /private/backup.env
chmod 600 /private/backup.env
export BACKUP_ENV=/private/backup.env BACKUP_ROOT=/backups POSTGRES_IMAGE=postgres:17-alpine
exec bash /drill/verify-release-backup-compatibility.sh "$@"
