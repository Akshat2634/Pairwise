# Self-hosting

Pairwise needs an account/presence API and a LiveKit media server. The client-to-server API is not a substitute for the media relay. Local Compose is loopback-only and is suitable for development on one machine. A team on different networks needs public DNS, HTTPS/WSS, media connectivity, and TURN/TLS for restrictive networks.

## Production outline

Use a Linux host with Docker Compose and a static public address. For a small team, begin with 2–4 vCPU and at least 4 GiB RAM, then measure real calls before sizing for more users. A single host is a single point of failure. No database cluster, GPU, recording bucket, or transcription service is required by this design.

Create three DNS names that resolve to the host: API, media signaling, and TURN. The production configuration routes HTTPS through Nginx and TURN/TLS on port 443. Permit TCP 80/443 and 7881, UDP 3478, and the configured LiveKit UDP media range. Restrict SSH to the operators. Do not put the media or TURN names behind a conventional HTTP proxy.

From the repository root, configure a private production directory with your own domains and contact address:

```sh
python3 infra/production/configure.py \
  --api-domain api.example.com \
  --media-domain media.example.com \
  --turn-domain turn.example.com \
  --public-ip YOUR_STATIC_IPV4 \
  --contact ops@example.com
bash infra/production/manage.sh certificates
bash infra/production/manage.sh up
bash infra/production/manage.sh admin 'Administrator Name' 'admin@example.com'
python3 infra/production/check-health.py
```

The configuration generator creates media credentials locally and keeps generated configuration ignored by Git. The admin command prompts for the first password. Create additional invited users from the app. Back up the account store and TLS/configuration data to a private, encrypted destination. Never commit generated credentials or account snapshots.

Before real use, test a call from outside the server network, confirm TURN/TLS allocation on a network that blocks UDP, inspect logs for personal data, and rehearse restore from a backup. The single-host service is not highly available. Media is transport-encrypted, but the self-hosted SFU is trusted; application-level end-to-end encryption is not implemented.

## GCP

The repository includes an optional GCP provisioning script. It requires an explicitly selected project, region, and zone and supports a plan-only mode. Review the script and the current Google Cloud pricing before running any `--apply` command. Network egress, destination region, DNS, snapshots, IPv4, and logging can materially change cost. No project ID, hostname, IP address, or account credentials are configured in the public source.
