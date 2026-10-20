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

1. Take and verify an encrypted copy of `/data/pairdesk.json`; schedule a short
   maintenance window and stop the API and push worker.
2. Use the dedicated `pairdesk-pg` PostgreSQL 16 instance in `us-central1`.
   It has automated daily backups (7 retained), 7-day point-in-time recovery,
   SSL required, and no authorized public client networks. The `pairdesk`
   database and least-privilege `pairdesk_app` role are provisioned. Its
   password is held in Secret Manager as `pairdesk-db-password`; never copy it
   into this repository or a committed `.env` file. The instance is currently
   reached through the Cloud SQL Auth Proxy. Production API connectivity still
   needs a workload identity and a deployment secret/configuration path before
   cutover.
3. Run `PAIRDESK_DATABASE_URL=... pairdesk-admin import-json --from
   /data/pairdesk.json`. Import replaces the singleton state atomically and
   preserves accounts, password hashes, sessions, device registrations, audit
   entries, and unexpired pending jobs.
4. Start one API instance with the same DSN. Verify `/healthz`, `/readyz`,
   existing-user login, presence, call creation, and outbox delivery before
   enabling additional replicas.
5. Run the two-instance integration check against a disposable database with
   `PAIRDESK_TEST_DATABASE_URL=... go test ./internal/app -run
   TestPostgresConcurrentWorkersLeasePushOnce -count=1`.

The initial schema is created idempotently on application start. Back up before
upgrading; keep the JSON export until account owners confirm sign-in and call
flows after the migration.

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

Before cutover, attach a dedicated service account to the API VM (currently it
has no attached service account), grant only the required Cloud SQL client and
secret access, and configure the Cloud SQL Auth Proxy as a managed service or
sidecar. Then follow the migration steps during a maintenance window, verify
health/readiness, existing-user login, presence, calls, and push outbox
delivery, and retain the JSON export for rollback. Do not scale API replicas
until the PostgreSQL-backed API and push worker pass the two-instance
concurrency check. The current VM still runs JSON-volume mode.

Cloud Monitoring has one enabled Pairwise readiness alert policy. A temporary
test policy targeting the configured email channel opened an incident and was
removed after the incident closed. The test incident confirms the alert path
was exercised; mailbox receipt was not independently confirmed.
