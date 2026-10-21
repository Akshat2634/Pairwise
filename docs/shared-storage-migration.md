# Shared PostgreSQL storage

The API can use PostgreSQL by setting `PAIRDESK_DATABASE_URL` on every API
instance. When it is unset, the server uses `PAIRDESK_DATA` and remains a
single-writer deployment. Do not scale JSON-volume mode to multiple API
instances.

The first PostgreSQL implementation stores the existing state document in a
single JSONB row and locks that row for every store transaction. This preserves
atomic call creation plus push-outbox insertion and prevents lost updates
across instances. Push workers claim jobs by writing a 30-second owner lease
before contacting APNs/FCM. Delivery is at-least-once across process crashes:
an expired lease can be retried, and mobile clients must treat call/request IDs
as idempotency keys. The single-row lock favors correctness for Pairwise's
small team; it is a deliberate throughput limit. Normalize hot tables before
using this design for a substantially larger deployment.

## Migration

1. Schedule a short maintenance window and take a private JSON-mode backup with
   `bash infra/production/manage.sh backup /secure-backup`. Verify that the
   resulting file is valid JSON and retain an encrypted copy outside the VM.
   Stop the API and push worker before importing so no writes are lost.
2. Use the dedicated `pairdesk-pg` PostgreSQL 16 instance in `us-central1`.
   It has automated daily backups (7 retained), 7-day point-in-time recovery,
   SSL required, and no authorized public client networks. The `pairdesk`
   database and least-privilege `pairdesk_app` role are provisioned. Its
   password is held in Secret Manager as `pairdesk-db-password`; never copy it
   into this repository or a committed `.env` file. A dedicated runtime
   service account is prepared as
   `pairdesk-api-runtime@named-tube-444103-p0.iam.gserviceaccount.com`; it has
   the Cloud SQL Client role and Secret Accessor on this database password
   secret. It is not yet attached to the production VM. The isolated restore
   drill used the Cloud SQL Auth Proxy; the production API does not yet use it.
3. Import the verified snapshot while the API remains stopped. Start only the
   proxy, then run the admin importer against the private backup path:

   ```sh
   docker compose -p pairdesk-prod --env-file infra/production/generated/.env \
     -f infra/production/docker-compose.yml \
     -f infra/production/docker-compose.cloudsql.yml up -d cloud-sql-proxy
   docker compose -p pairdesk-prod --env-file infra/production/generated/.env \
     -f infra/production/docker-compose.yml \
     -f infra/production/docker-compose.cloudsql.yml run --rm --no-deps \
     -v /secure-backup:/pairdesk-backups:ro --entrypoint /pairdesk-admin api \
     import-json --from /pairdesk-backups/PAIRWISE-BACKUP.json
   ```

   Import replaces the singleton state atomically and preserves accounts,
   password hashes, sessions, device registrations, audit entries, and
   unexpired pending jobs. Export the database to a separate temporary JSON
   file, normalize both JSON files, and compare them before starting the API.
4. Start one API instance with the same DSN. Verify `/healthz`, `/readyz`,
   existing-user login, presence, call creation, and outbox delivery before
   enabling additional replicas.
5. Run the two-instance integration check against a disposable database with
   `PAIRDESK_TEST_DATABASE_URL=... go test ./internal/app -run
   TestPostgresConcurrentWorkersLeasePushOnce -count=1`.

Only after the import comparison passes should the API be started in Cloud SQL
mode with `bash infra/production/manage.sh up`. If import or comparison fails,
keep the API stopped and use the pre-cutover JSON snapshot as the recovery
source.

The initial schema is created idempotently on application start. Back up before
upgrading; keep the JSON export until account owners confirm sign-in and call
flows after the migration.

## Production proxy configuration

The production stack has an optional Cloud SQL Auth Proxy Compose override. On
the VM, after the runtime service account is attached and the VM has the
`cloud-platform` API scope, run:

```sh
python3 infra/production/configure-cloudsql.py \
  --project named-tube-444103-p0 \
  --instance pairdesk-pg \
  --secret pairdesk-db-password
```

The helper verifies the instance is `RUNNABLE`, reads the password from Secret
Manager without printing it, URL-escapes it, and writes the DSN and instance
connection name into `infra/production/generated/.env` with mode `0600`.
`manage.sh` then includes the pinned Cloud SQL Auth Proxy sidecar, which uses
the VM's attached identity and is reachable only on the private Compose
network. If the connection name is configured without a matching DSN, startup
fails closed. A non-Cloud-SQL PostgreSQL URL can still be used without the
sidecar.

In Cloud SQL mode, `manage.sh backup DIRECTORY` exports the current PostgreSQL
state through the app's store before saving a mode-`0600` JSON snapshot. In
JSON mode it retains the atomic file-copy backup. Keep the snapshot from
before cutover separately from later PostgreSQL exports so rollback preserves
the exact pre-migration state.

## Rollback

Stop every API and worker first so the export is a consistent snapshot. Run
`PAIRDESK_DATABASE_URL=... pairdesk-admin export-json --to
/secure-backup/pairdesk-postgres-export.json`, validate the JSON file and its
permissions, then point the single API writer back to `PAIRDESK_DATA` on a
restored volume. This returns to single-writer mode and rolls state back to the
export point. Keep the Cloud SQL instance and backups until owners confirm
sign-in and pending-call behavior; do not delete the database as part of
rollback.

## Recovery and cutover status

The production instance has been provisioned and its backup/PITR settings
verified. A manual backup was restored to an isolated temporary clone; a
sentinel row was read back successfully through the application database role,
then the probe and clone were removed. The primary instance has deletion
protection enabled. This proves the Cloud SQL backup/restore path, not recovery
of Pairwise production accounts: the live API has not been migrated and
existing-user sign-in after a production data import has not yet been tested.

Before cutover, take and verify the JSON-mode backup, then attach the prepared
service account to the API VM (currently it has no attached service account)
with the Cloud SQL Client and Secret Accessor roles and the Cloud SQL API
scope. Attaching an identity requires a VM stop/start and must be scheduled
with the application maintenance window. Run the proxy configuration helper,
stop the API, import the JSON snapshot into PostgreSQL, export the database
state back to a temporary JSON file and compare the complete structures before
restarting the API in Cloud SQL mode. If import or comparison fails, keep the
API stopped until the operator chooses recovery; the original JSON snapshot
remains the rollback source. Then verify health/readiness, existing-user
login, presence, calls, and push outbox delivery. Do not scale API replicas
until the PostgreSQL-backed API and push worker pass the two-instance
concurrency check. The current VM still runs JSON-volume mode.

Cloud Monitoring has one enabled Pairwise readiness alert policy. A temporary
test policy targeting the configured email channel opened an incident and was
removed after the incident closed. The test incident confirms the alert path
was exercised; mailbox receipt was not independently confirmed.
