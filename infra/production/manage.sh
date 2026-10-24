#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[[ -f generated/.env ]] || { echo 'Run configure.py first' >&2; exit 1; }
# configure.py restricts these generated values to shell-safe domain/key/email characters.
source generated/.env
COMPOSE_FILES=(-f docker-compose.yml)
if [[ -n "${PAIRDESK_CLOUD_SQL_CONNECTION_NAME:-}" ]]; then
  [[ -n "${PAIRDESK_DATABASE_URL:-}" ]] || { echo 'Cloud SQL connection is configured without a database URL' >&2; exit 1; }
  [[ "$PAIRDESK_DATABASE_URL" == *'@cloud-sql-proxy:5432/pairdesk?sslmode=disable' ]] || {
    echo 'Cloud SQL proxy is configured, but the database URL does not target its private Compose service' >&2
    exit 1
  }
  COMPOSE_FILES+=(-f docker-compose.cloudsql.yml)
elif [[ "${PAIRDESK_DATABASE_URL:-}" == *'@cloud-sql-proxy:5432/'* ]]; then
  echo 'The database URL targets Cloud SQL but its instance connection name is missing; run configure-cloudsql.py' >&2
  exit 1
fi
compose() { docker compose -p pairdesk-prod --env-file generated/.env "${COMPOSE_FILES[@]}" "$@"; }
case "${1:-}" in
  certificates)
    [[ "$(uname -s)" == Linux ]] || { echo 'Certificate bootstrap runs on the Linux deployment host' >&2; exit 1; }
    [[ ! -e generated/certificates/live/pairdesk/fullchain.pem ]] || { echo 'Certificate exists; use renew' >&2; exit 1; }
    docker run --rm -p 80:80 -v "$ROOT/generated/certificates:/etc/letsencrypt" \
      certbot/certbot:v3.2.0 certonly --standalone --non-interactive --agree-tos \
      --email "$CERT_CONTACT" --cert-name pairdesk -d "$API_DOMAIN" -d "$MEDIA_DOMAIN" -d "$TURN_DOMAIN"
    ;;
  up)
    [[ "$(uname -s)" == Linux ]] || { echo 'Production startup is restricted to the Linux host' >&2; exit 1; }
    [[ -f generated/certificates/live/pairdesk/fullchain.pem ]] || { echo 'Bootstrap trusted certificates first' >&2; exit 1; }
    build_commit=${PAIRDESK_BUILD_COMMIT:-$(git -C "$ROOT/../.." rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')}
    PAIRDESK_BUILD_COMMIT="$build_commit" compose up -d --build
    ;;
  deploy-api)
    [[ "$(uname -s)" == Linux ]] || { echo 'API deployment is restricted to the Linux host' >&2; exit 1; }
    [[ $# == 2 && "$2" =~ ^[0-9a-f]{40}$ ]] || { echo 'Usage: manage.sh deploy-api FULL_40_CHARACTER_COMMIT_SHA' >&2; exit 2; }
    build_commit=$2
    previous_image=$(compose images -q api | head -n 1)
    [[ -n "$previous_image" ]] || { echo 'Cannot deploy without a current API image to roll back to' >&2; exit 1; }
    rollback_image="pairdesk-prod-api:rollback-${build_commit:0:12}"
    docker image tag "$previous_image" "$rollback_image"
    if ! PAIRDESK_BUILD_COMMIT="$build_commit" compose build api; then
      echo 'API image build failed; the running service was left unchanged.' >&2
      exit 1
    fi
    if ! PAIRDESK_BUILD_COMMIT="$build_commit" compose up -d --no-deps --no-build api; then
      echo 'API container update failed; restoring the previous image.' >&2
      if ! docker image tag "$previous_image" pairdesk-prod-api:latest; then
        echo 'Could not restore the previous API image tag; manual recovery is required.' >&2
        exit 1
      fi
      if ! compose up -d --no-deps --no-build api; then
        echo 'Automatic rollback failed; inspect pairdesk-prod-api and the previous image immediately.' >&2
        exit 1
      fi
      exit 1
    fi
    ready=0
    for attempt in {1..24}; do
      if python3 - "$API_DOMAIN" "$build_commit" <<'PYDEPLOY'
import json, sys, urllib.request

domain, expected_commit = sys.argv[1:]
def read(path):
    with urllib.request.urlopen(f"https://{domain}{path}", timeout=8) as response:
        return json.load(response)

try:
    version = read("/version")
    readiness = read("/readyz")
    if version.get("buildCommit") == expected_commit and readiness.get("ok") is True and readiness.get("media") is True:
        raise SystemExit(0)
except Exception:
    pass
raise SystemExit(1)
PYDEPLOY
      then
        ready=1
        break
      fi
      sleep 5
    done
    if [[ "$ready" != 1 ]]; then
      echo 'New API did not report the expected build and healthy media path; restoring the previous image.' >&2
      docker image tag "$previous_image" pairdesk-prod-api:latest
      if ! compose up -d --no-deps --no-build api; then
        echo 'Automatic rollback failed; inspect pairdesk-prod-api and the previous image immediately.' >&2
        exit 1
      fi
      exit 1
    fi
    echo "API deployment healthy at commit $build_commit; previous image retained as $rollback_image"
    ;;
  admin)
    [[ $# == 3 ]] || { echo 'Usage: manage.sh admin NAME EMAIL' >&2; exit 1; }
    # Offline CLI must never compete with the API writer. Restart even if user creation fails.
    compose stop api
    trap 'compose up -d api' EXIT
    compose run --rm --no-deps -it --entrypoint /pairdesk-admin api create-user --admin --name "$2" --email "$3"
    ;;
  renew)
    before=$(sha256sum generated/certificates/live/pairdesk/fullchain.pem | cut -d' ' -f1)
    docker run --rm -v "$ROOT/generated/certificates:/etc/letsencrypt" \
      -v "$ROOT/generated/challenges:/var/www/certbot" certbot/certbot:v3.2.0 \
      renew --webroot -w /var/www/certbot --non-interactive
    after=$(sha256sum generated/certificates/live/pairdesk/fullchain.pem | cut -d' ' -f1)
    if [[ "$before" != "$after" ]]; then
      compose exec -T edge nginx -t
      compose exec -T edge nginx -s reload
      compose restart livekit
    else
      echo 'Certificate unchanged; running calls preserved.'
    fi
    ;;
  backup)
    [[ $# == 2 ]] || { echo 'Usage: manage.sh backup EXISTING_PRIVATE_DIRECTORY' >&2; exit 1; }
    [[ -d "$2" ]] || { echo 'Backup directory must already exist' >&2; exit 1; }
    umask 077
    backup_dir=$(cd "$2" && pwd)
    archive="$backup_dir/pairdesk-$(date -u +%Y%m%dT%H%M%SZ).json"
    [[ ! -e "$archive" ]] || { echo 'Backup already exists' >&2; exit 1; }
    if [[ -n "${PAIRDESK_DATABASE_URL:-}" ]]; then
      compose run --rm --no-deps -T -v "$backup_dir:/pairdesk-backups" \
        --entrypoint /pairdesk-admin api export-json --to "/pairdesk-backups/$(basename "$archive")"
    else
      compose cp api:/data/pairdesk.json "$archive"
    fi
    chmod 600 "$archive"
    echo "Account snapshot saved to $archive"
    ;;
  status) compose ps ;;
  logs) compose logs --tail 80 ;;
  *) echo 'Usage: manage.sh {certificates|up|admin NAME EMAIL|renew|backup DIRECTORY|status|logs}' >&2; exit 2 ;;
esac
