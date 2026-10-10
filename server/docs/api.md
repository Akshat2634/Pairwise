# Pairdesk local backend

This service is for a small, invited team. It has no signup endpoint, external identity provider, email service, or third-party integrations. Team members are created with the admin CLI. Team members can change their own password in the app. Disabling an account invalidates all its sessions.

## Run locally

From `pairdesk/infra`, run `./setup.sh` and then `docker compose up --build`. The API is at `http://127.0.0.1:18080`; LiveKit websocket signaling is at `ws://127.0.0.1:17880`. All published ports bind to localhost. The named volume stores the JSON database at `/data/pairdesk.json` with mode 0600. Back up the volume as sensitive data. The JSON file uses atomic replacement and the process serializes updates with a mutex; run one API replica against a data file.

Bootstrap the first admin in the compose data volume before starting the API: from `pairdesk/infra`, run `./setup.sh`, `docker compose build api`, then `docker compose run --rm --no-deps -it --entrypoint /pairdesk-admin api create-user --admin --name 'Taylor Example' --email taylor@example.com`. The CLI prompts for a password of at least 12 characters, or reads `PAIRDESK_ADMIN_PASSWORD` if set in the environment. Deliver the initial password through an existing private channel; it is never printed. Then run `docker compose up`. Once signed in as an admin, create and manage invited members through Account settings; the CLI remains available for offline bootstrap and recovery.
## API

All endpoints use JSON. Protected routes require `Authorization: Bearer <token>`. Error responses are JSON `{ "error": "..." }`. Timestamps are UTC RFC3339. The login session is a cryptographically random opaque bearer token, stored server-side, and expires after seven days. The client should store it in Keychain and clear it on logout. Login is limited to 10 failed attempts per source IP per rolling 15 minutes per API process; a successful login clears that IP counter.

- `POST /v1/login` `{ "email": "...", "password": "..." }` → `{ "token": "...", "user": {"id":"...","name":"...","email":"..."}, "expiresAt":"...Z" }`
- `GET /v1/me` → `{ "user": {"id":"...","name":"...","email":"...","admin":true} }`; `admin` is included for administrators only.
- `POST /v1/password` `{ "currentPassword":"...", "newPassword":"..." }` → `{ "ok":true }`. New passwords must be at least 12 characters. The current session remains valid; other sessions for the account are revoked.
- `POST /v1/logout` → `{ "ok":true }`; invalidates the current session.
- `POST /v1/admin/users` (admins only) `{ "name":"...", "email":"...", "password":"..." }` → HTTP 201 `{ "user":{"id":"...","name":"...","email":"..."} }`; creates a normal invited account.
- `GET /v1/admin/users` (admins only) → all accounts and enabled state; never returns password hashes.
- `POST /v1/admin/users/{id}/password` (admins only) `{ "newPassword":"..." }` → resets the password and revokes all sessions for that account.
- `POST /v1/admin/users/{id}/enabled` (admins only) `{ "enabled":true|false }` → enables/disables an account; disabling invalidates sessions and cannot disable the last enabled admin.
- `GET /healthz` is a liveness check. `GET /readyz` checks the configured LiveKit media service and returns HTTP 503 when that dependency is unavailable; responses contain no credentials.
- `GET /v1/users` → `{ "users":[{"id":"...","name":"...","email":"...","online":true}] }`
- `POST /v1/heartbeat` `{}` → `{ "ok":true }`; marks the signed-in user online for 30 seconds.
- `GET /v1/rooms` → `{ "rooms":[{"id":"...","name":"...","participantCount":0,"participants":[]}] }`. Participant list/count reflects active API reservations, not a LiveKit admin query.
- `POST /v1/rooms` `{ "name":"..." }` → HTTP 201 `{ "room": {"id":"...","name":"...","participantCount":0,"participants":[]} }`
- `POST /v1/rooms/{id}/join` `{}` → `{ "room":{"id":"...","name":"...","participantCount":1}, "url":"ws://...", "token":"<LiveKit JWT>", "participantIdentity":"<stable user id>" }`
- `POST /v1/rooms/{id}/share` `{ "enabled":true|false }` → HTTP 204. One current room member can claim screen sharing; a competing claim returns HTTP 409. The server updates that connected LiveKit participant to microphone plus screen-share sources.
- `POST /v1/rooms/{id}/leave` `{}` → `{ "ok":true }`; releases any share claim and its screen permission.
- `POST /v1/rooms/{id}/heartbeat` `{}` → `{ "ok":true }`; refreshes the room reservation. A room heartbeat before joining returns 403.
- `POST /v1/calls` `{ "userId":"<teammate id>" }` starts a private direct call; include `roomId` to invite into a room where the caller is already an active member. The target must be enabled, online, and not busy. Returns HTTP 201 `{ "call": {"id":"...","status":"pending","caller":{...},"target":{...},"room":{"id":"...","name":"Direct call","participantCount":2,"participants":[...]},"expiresAt":"<RFC3339>"} }`.
- `GET /v1/calls` → `{ "calls":[...] }` for invitations involving the signed-in user, including recent terminal states. New direct-call rooms are omitted from `GET /v1/rooms`.
- `POST /v1/calls/{id}/accept` (target only), `/decline` (target only), or `/cancel` (caller while ringing; either participant after acceptance) → `{ "call":{...} }`. Calls ring for 45 seconds. An accepted target has a 30-second room reservation to join; an expired reservation ends the invitation. Caller can join the private room while ringing; the target can join only after accepting. Leaving the room cancels pending calls from that caller and accepted calls for a departing target.

## Media admission and limits

The backend reserves a participant slot when join succeeds. Each user has one slot per room, refreshed by the room heartbeat, and reservations expire after 30 seconds. Join refuses a fifth unexpired reservation with HTTP 409. Keep room heartbeat running while connected and call leave on exit. LiveKit JWTs last 60 seconds; they grant room join, subscribe, and microphone and data publishing only. Camera and screen-share audio are never granted. The `/share` endpoint temporarily adds screen-share video permission for the single recorded holder, and disabling or leaving removes that permission. Tokens use the stable user ID as LiveKit identity, so a user cannot appear as multiple identities.

The API creates each LiveKit room with `maxParticipants: 4`, then checks for and recreates it on every join in case LiveKit expired the idle room. Join tokens also carry `roomConfig.maxParticipants: 4` as a fallback. LiveKit applies that setting only when the room is first created; all room creation must therefore continue through this API. LiveKit is the final hard cap if API reservations temporarily disagree with connected media participants. A disconnected-but-not-left participant can occupy a LiveKit slot until LiveKit considers that participant gone, while its API reservation can expire after 30 seconds. This can cause brief false-full responses; LiveKit will not allow a fifth connected media participant. If an administrator creates a room outside this service, its capacity is not guaranteed.

## Production notes

This compose stack is development-only and binds services to localhost. Production requires HTTPS for the API and WSS for LiveKit, trusted TLS certificates, firewall rules for LiveKit signaling and UDP media, and TURN/TLS relay for restrictive networks. Keep API key/secret and session database private, rotate development values before any shared deployment, use a managed secret store, and back up encrypted persistent data. Configure reverse-proxy timeouts to allow regular heartbeat requests. The current file store and per-process login limiter are intended for one small API instance, not horizontal scaling. `LIVEKIT_API_URL` is the private admin URL (`http://livekit:7880` in compose); `LIVEKIT_URL` is the client-facing signaling URL returned by the API. No real host deployment is included.
