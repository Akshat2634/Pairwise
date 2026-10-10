#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
[[ -f generated/.env ]] || { echo 'Run configure.py first' >&2; exit 1; }
# configure.py restricts these generated values to shell-safe domain/key/email characters.
source generated/.env
compose() { docker compose -p pairdesk-prod --env-file generated/.env -f docker-compose.yml "$@"; }
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
    compose up -d --build
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
    archive="$2/pairdesk-$(date -u +%Y%m%dT%H%M%SZ).json"
    [[ ! -e "$archive" ]] || { echo 'Backup already exists' >&2; exit 1; }
    compose cp api:/data/pairdesk.json "$archive"
    chmod 600 "$archive"
    echo "Account snapshot saved to $archive"
    ;;
  status) compose ps ;;
  logs) compose logs --tail 80 ;;
  *) echo 'Usage: manage.sh {certificates|up|admin NAME EMAIL|renew|backup DIRECTORY|status|logs}' >&2; exit 2 ;;
esac
