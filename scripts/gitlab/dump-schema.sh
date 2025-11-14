#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'USAGE'
Usage: dump-schema.sh [output-file]

Emit a schema-only pg_dump of the GitLab database. Run this inside a RAVE VM
after GitLab has finished its initial migrations.

Arguments:
  output-file   Destination path for the SQL dump
                (defaults to /var/lib/gitlab/gitlab-schema.sql)
USAGE
  exit 0
fi

OUTPUT_PATH="${1:-/var/lib/gitlab/gitlab-schema.sql}"
PG_BIN=${PG_BIN:-pg_dump}
PSQL_BIN=${PSQL_BIN:-psql}
PG_ISREADY_BIN=${PG_ISREADY_BIN:-pg_isready}
POSTGRES_USER=${POSTGRES_USER:-postgres}

echo "Preparing to dump GitLab schema to ${OUTPUT_PATH}"

until sudo -u "${POSTGRES_USER}" "${PG_ISREADY_BIN}" -h 127.0.0.1 -d gitlab >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

ACTIVE_MIGRATIONS=$(sudo -u "${POSTGRES_USER}" "${PSQL_BIN}" -tAc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations';" gitlab)

if [[ "${ACTIVE_MIGRATIONS:-0}" -eq 0 ]]; then
  echo "GitLab schema_migrations table not found yet. Run this after the first boot completes."
  exit 1
fi

sudo -u "${POSTGRES_USER}" "${PG_BIN}" --schema-only --no-owner gitlab > "${OUTPUT_PATH}"
if getent passwd git >/dev/null 2>&1; then
  chown git:git "${OUTPUT_PATH}" || true
elif getent passwd gitlab >/dev/null 2>&1; then
  chown gitlab:gitlab "${OUTPUT_PATH}" || true
fi
echo "GitLab schema written to ${OUTPUT_PATH}"
