# Changelog

Detailed, developer-facing log of implementation changes, in the order they
happened. This is separate from `docs/decisions.md`, which stays a short
ADR-style log of *why* an architectural choice was made; this file covers
*what was actually built or changed*, in enough detail to reconstruct the
work without asking the original author. Entries are grouped by phase (see
`docs/phases.md`).

---

## Phase 1 — Repository structure + Docker base infrastructure

**Date:** 2026-09-18

### What was added

- **`docker-compose.yml`** (new, repo root) — defines two services:
  - `postgres` — image `postgres:16-alpine`, reads credentials from `.env`
    via `env_file`, exposes `5432:5432`, persists data to a named volume
    `postgres-data`, healthcheck via `pg_isready`.
  - `minio` — image `quay.io/minio/minio:latest` (see "Bugs encountered"
    below for why not `minio/minio`), reads credentials from `.env`, runs
    `server /data --console-address ":9001"`, exposes `9000` (S3 API) and
    `9001` (web console), persists to named volume `minio-data`, healthcheck
    against `/minio/health/live`.
  - No application schema or MinIO buckets are created yet — Postgres comes
    up as an empty database (`healthcare_records`), MinIO with no buckets.
    Schema arrives in Phase 4 (backend + migrations); buckets arrive in
    Phase 5 (file upload).
- **`.env.example`** (new, repo root) — template for required environment
  variables: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`,
  `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`. Copy to `.env` before running
  `docker compose up`. `.env` itself is gitignored and was created locally
  but is not committed.
- **`backend/`** and **`chaincode/`** (new, empty directories with
  `.gitkeep`) — placeholders for the Go backend (Phase 4+) and Go chaincode
  (Phase 2/3+). No code yet; created now so the repo layout matches the
  phases that will fill them in, per Phase 1's scope ("repository/folder
  structure").

### What was changed

- **`.gitignore`** — previously contained a single line, `*.md`. Replaced
  with:
  ```
  .env
  fabric-samples/
  *.exe
  *.test
  node_modules/
  ```
  See "Bugs encountered" for why the old rule was a problem, not a
  convenience.

### Bugs/issues encountered and how they were resolved

1. **`.gitignore` was silently hiding all project documentation from git.**
   The original `.gitignore` (`*.md`) meant `CLAUDE.md` and everything
   under `docs/` (`phases.md`, `decisions.md`, `data-model.md`,
   `demo-scenarios.md`, `environment-setup.md`, `viva-concepts.md`) never
   appeared in `git status` and could never be `git add`-ed. Checking
   `git log`/`git ls-files` confirmed only `README.md` existed in git
   history since the initial commit — `CLAUDE.md` and `docs/` had been
   on-disk only, uncommitted, the entire time. Fixed by rewriting
   `.gitignore` to only ignore things that actually should never be
   committed (secrets, build artifacts, vendored external repos), and this
   phase's commit includes `CLAUDE.md` and `docs/` for the first time.
   **Impact:** none on running code — this only affected version control,
   not functionality. **Risk avoided:** project documentation and the ADR
   log existed nowhere except one machine's disk.

2. **`minio/minio` image pull denied on Docker Hub.**
   `docker compose up -d` initially failed with:
   ```
   Error pull access denied for minio/minio, repository does not exist or
   may require 'docker login': denied: requested access to the resource is
   denied
   ```
   MinIO no longer publishes to Docker Hub under anonymous pull for this
   tag. Resolved by switching the image reference in `docker-compose.yml`
   to `quay.io/minio/minio:latest`, MinIO's current official registry —
   same image/binary, different host. No other configuration changes were
   needed; `docker pull quay.io/minio/minio:latest` succeeded immediately.

### Verification performed

- `docker compose up -d` — both containers reported `healthy` via their
  compose healthchecks within ~5 seconds.
- `psql -h localhost -U hcr_app -d healthcare_records -c '\conninfo'` —
  confirmed a real client connection to the Postgres container from the
  host (not just the internal healthcheck).
- `curl -sf http://localhost:9000/minio/health/live` — confirmed MinIO's
  S3 API port is reachable from the host and returns a healthy response.
- Manual follow-up left for the user: open `http://localhost:9001` in a
  browser and log in with the `.env` MinIO credentials to confirm the web
  console is reachable (no buckets expected yet).

### How this interacts with existing functionality

Nothing pre-existing to interact with — this is the first infrastructure
in the project. Future phases build on top:
- Phase 2 will add Fabric's own network (peers/orderer/CA), brought up
  separately from this `docker-compose.yml`, not merged into it.
- Phase 4 will point the Go backend's Postgres connection string and MinIO
  client at `localhost:5432` / `localhost:9000` (or the Docker service
  names `postgres`/`minio` once the backend itself is containerized).
- Phase 5 will create the actual MinIO bucket(s) used for encrypted file
  storage.

### Setup steps to use this

```bash
cp .env.example .env     # fill in real values; .env is gitignored
docker compose up -d
docker compose ps        # both services should show "healthy"
```

To tear down: `docker compose down` (add `-v` to also delete the named
volumes and lose persisted data — not needed for normal stop/start).

### Assumptions / trade-offs

- No Postgres schema and no MinIO bucket policy are defined yet — this
  phase is infrastructure-only, per `docs/phases.md`'s Phase 1 scope.
  Defining them now would be exactly the kind of speculative work
  `CLAUDE.md` says to avoid ("build for what's asked now"). Defining a
  schema or bucket policy now would mean redoing that config once Phase
  4/5's actual requirements are known — deferred instead of guessed.
- Named Docker volumes (not host bind-mounts) are used for Postgres/MinIO
  data, so persisted data lives under Docker's own storage rather than a
  visible path in the repo. This keeps the repo clean and matches the
  "server always runs as a container, never installed on host" plan from
  `docs/environment-setup.md`.
