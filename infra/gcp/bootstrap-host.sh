#!/bin/bash
# Run on the new PairDesk Ubuntu host after uploading the deployment archive.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo on the PairDesk host' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io docker-compose-v2 python3 curl
systemctl enable --now docker
install -d -m 700 /opt/pairdesk /var/lib/pairdesk/backups
tar -xzf /tmp/pairdesk-deploy.tar.gz -C /opt/pairdesk
chmod 700 /opt/pairdesk
cat > /etc/systemd/system/pairdesk-renew.service <<'UNIT'
[Unit]
Description=Renew PairDesk TLS certificate
After=docker.service network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/pairdesk/infra/production/manage.sh renew
UNIT
cat > /etc/systemd/system/pairdesk-renew.timer <<'UNIT'
[Unit]
Description=Daily PairDesk certificate renewal check
[Timer]
OnCalendar=*-*-* 04:00:00 UTC
RandomizedDelaySec=3600
Persistent=true
[Install]
WantedBy=timers.target
UNIT
cat > /etc/systemd/system/pairdesk-backup.service <<'UNIT'
[Unit]
Description=Snapshot PairDesk account file
After=docker.service
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/pairdesk/infra/production/manage.sh backup /var/lib/pairdesk/backups
UNIT
cat > /etc/systemd/system/pairdesk-backup.timer <<'UNIT'
[Unit]
Description=Daily PairDesk account backup
[Timer]
OnCalendar=*-*-* 02:00:00 UTC
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
# Start timers only after live services and the initial account are verified.
echo 'Docker installed and PairDesk staged; timers prepared but not enabled yet.'
