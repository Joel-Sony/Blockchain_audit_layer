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

---

## Phase 2 — Basic Fabric network (checkpoint reached)

**Date:** 2026-09-21

### What was added (steps 1-5 of this phase)

- **`network/docker-compose-ca.yaml`** (new) — 4 `hyperledger/fabric-ca`
  containers, one per org: `ca-hospitala` (port 7054), `ca-hospitalb`
  (8054), `ca-lab` (9054), `ca-orderer` (10054). Each has its own
  bind-mounted volume under `network/organizations/fabric-ca/<org>/` and a
  bootstrap admin identity (`admin:adminpw` — dev-only, not meant to be
  secure). See ADR-001 for why Fabric CA over `cryptogen`.
- **`network/scripts/register-enroll.sh`** (new) — registers and enrolls,
  against each org's CA: an org admin identity, a `peer0` identity (MSP +
  separate TLS cert/key), and for the orderer org, an `orderer1` identity
  (MSP + TLS) plus its own org admin. Produces the real MSP folder trees
  under `network/organizations/peerOrganizations/` and
  `network/organizations/ordererOrganizations/`. See ADR-002 for the
  4-org (3 peer orgs + separate OrdererOrg) structure.
- **`network/configtx/configtx.yaml`** (new) — defines all 4 orgs'
  MSPs/policies and one channel profile, `HealthcareChannel`, with the 3
  hospital/lab orgs as Application members and `OrdererOrg` as the sole
  Orderer org (single-node etcdraft). See ADR-003.
- **`network/channel-artifacts/healthchannel.block`** (generated, not
  committed — see "What was changed" below) — the `healthchannel` genesis
  block, produced by `configtxgen -profile HealthcareChannel -outputBlock
  ... -channelID healthchannel` from `configtx.yaml`. Verified via
  `configtxgen -inspectBlock` that all 4 org MSP IDs are embedded
  correctly.
- **`network/config/peercfg/core.yaml`** (new, copied from
  `fabric-samples/test-network`'s stock config) — the peer's base config
  file. Almost everything in it is overridden by `CORE_*` env vars set per
  peer in the compose file below; it exists because the `peer` binary
  (both the container process and the CLI we run from the host) refuses
  to start without *some* `core.yaml` on its `FABRIC_CFG_PATH`. Copied
  into the project instead of pointed at `fabric-samples/` so the network
  doesn't depend on that gitignored/vendored folder at runtime.
- **`network/docker-compose-net.yaml`** (new) — the orderer
  (`orderer1.orderer.healthcare.com`) and one peer per hospital/lab org,
  all on the same Docker network as the CAs (`healthcare-fabric-net`).
  The orderer starts with `ORDERER_GENERAL_BOOTSTRAPMETHOD=none` and
  `ORDERER_CHANNELPARTICIPATION_ENABLED=true` — it comes up "empty" and
  is told which channel(s) to serve afterwards via its admin API, rather
  than being handed a genesis block file at boot. Peers mount their own
  MSP/TLS folders from Step 2 and the peer config from just above.
- **`network/scripts/join-channel.sh`** (new) — the two-part "actually
  form the channel" step:
  1. `osnadmin channel join` tells the orderer, over its admin API
     (port 7053, mTLS using the orderer's own TLS cert as the client
     cert), to start serving `healthchannel` using the genesis block from
     Step 3.
  2. `peer channel join -b <genesis block>`, run once per org (using that
     org's admin identity), tells each peer to fetch that channel's
     blocks and start tracking its world state.
  Verified with `peer channel list` on all 3 peers — each correctly
  reports membership in `healthchannel`.
- **`chaincode/proofoflife/`** (new) — the throwaway Go chaincode: `Put`
  (submit, writes a key/value to world state) and `Get` (evaluate, reads
  it back). Originally written for classic peer-built chaincode; switched
  to Chaincode-as-a-Service (CCaaS) mode (`shim.ChaincodeServer`, reading
  `CHAINCODE_ID`/`CHAINCODE_SERVER_ADDRESS` from env, TLS disabled since
  it only ever talks to peers over the project's private Docker network)
  after classic mode turned out to be broken on this machine — see "Bugs"
  below and ADR-004. Includes a `Dockerfile` (multi-stage, `golang:1.25-alpine`
  build → `alpine` runtime) built once as `proofoflife_ccaas_image:latest`.
- **`network/scripts/deploy-chaincode.sh`** (new) — packages a CCaaS
  "pointer" package per org (a `connection.json` naming that org's own
  chaincode container + a `metadata.json` with `"type": "ccaas"`, tarred
  up by hand — no source code in the package), installs it on that org's
  peer, starts that org's chaincode container
  (`proofoflife-hospitala`/`-hospitalb`/`-lab`, all on
  `healthcare-fabric-net`), then approves (all 3 orgs) and commits the
  chaincode definition. Verified: `checkcommitreadiness` showed all 3
  orgs' approvals as `true` before commit; all 3 `peer lifecycle
  chaincode commit` calls returned `VALID`.
- **`network/scripts/smoke-test.sh`** (new) — the actual Phase 2 proof:
  submits `Put("greeting", "hello from Hospital A")` endorsed by Hospital
  A + Hospital B (2 of 3 orgs — this channel's default endorsement policy
  is "majority of channel members"), then queries `Get("greeting")` via
  the **Lab's** peer, which did not endorse the write, to prove the
  result actually replicated across the shared channel rather than just
  being written locally. Confirmed: Lab's peer returned exactly `"hello
  from Hospital A"`.

### What was changed

- **`.gitignore`** — added rules to exclude all Fabric-generated crypto
  material (`network/organizations/peerOrganizations/`,
  `network/organizations/ordererOrganizations/`, each CA's `msp/`, `.db`,
  key files, TLS certs, server config) and the generated
  `network/channel-artifacts/`. None of this is meant to be committed:
  private keys obviously shouldn't be, and everything else is
  regenerable by re-running `register-enroll.sh` / `configtxgen` against
  a fresh set of CA containers.

### Bugs/issues encountered and how they were resolved

1. **`fabric-ca-client enroll -M <relative path>` resolves relative to
   `FABRIC_CA_CLIENT_HOME`, not the shell's working directory.** First run
   of `register-enroll.sh` used relative `-M` paths, which got
   double-prefixed with the org directory and failed with `cp: cannot
   create regular file ... No such file or directory`. Fixed by making
   every `-M` argument an absolute path (`${PWD}/${org_dir}/...`).
2. **Re-running the script after the above failure hit "Identity 'peer0'
   is already registered"** — the first (failed) run had already
   registered identities against the CA's database before the enrollment
   step failed, and `fabric-ca-client register` isn't idempotent. Fixed
   by resetting: stop the CA containers, wipe each CA's bind-mounted data
   directory, and start fresh. The CA's own data directory is written as
   root inside the container, so plain host-side `rm -rf` failed with
   `Permission denied` (this machine's `sudo` needs an interactive
   password — see ADR-000); worked around by running the delete inside a
   throwaway `alpine` container instead (Docker itself needs no `sudo`
   here since the user is in the `docker` group).
3. **`peer channel join` failed with `Fatal error when initializing core
   config : error when reading core config file: Config File "core" Not
   Found`** — the `peer` CLI (run from the host to administer the
   network, as opposed to the `peer` process running inside each peer
   container) needs `FABRIC_CFG_PATH` pointing at a directory containing
   `core.yaml`, same as the containerized peer does. Fixed by exporting
   `FABRIC_CFG_PATH=network/config/peercfg` before every `peer` CLI call
   in `join-channel.sh`.
4. **Re-running `osnadmin channel join` for a channel that's already
   joined returns `Status: 405 {"error": "cannot join: channel already
   exists"}` but still exits 0.** Not really a bug — `join-channel.sh` is
   safe to re-run in full even after a partial failure partway through,
   since the orderer step just no-ops instead of erroring out.
5. **`peer lifecycle chaincode install` (classic mode) failed with
   `could not build chaincode: docker build failed: docker image build
   failed: write unix @->/run/docker.sock: write: broken pipe`,
   consistently, even though a manual `docker build` of an equivalent
   Dockerfile from the host worked fine.** This is a real incompatibility
   between Fabric 2.5.9's embedded Docker API client and this machine's
   Docker Engine (29.x) — not a config mistake on our side (confirmed via
   `journalctl -u docker`: the daemon did start a build container and it
   ran to completion, but the peer's client still errored on the socket
   write). No config fix found; switched the chaincode to
   Chaincode-as-a-Service (CCaaS) instead, which removes the peer's
   Docker-building step entirely. See ADR-004.
6. **`peer chaincode invoke` initially failed with `cannot init crypto,
   specified path ".../config/peercfg/msp" does not exist`.**
   `smoke-test.sh`'s first draft set the endorsing peers via
   `--peerAddresses`/`--tlsRootCertFiles` but forgot to also set the
   *submitting client's own* identity (`CORE_PEER_MSPCONFIGPATH` etc.) —
   those are two separate things: who endorses vs. who's asking. Fixed
   by exporting Hospital A's admin identity as the client identity before
   the `invoke` call.

### Verification performed

- `docker ps --filter name=ca-` — all 4 CA containers `Up`, each logged
  `Listening on https://0.0.0.0:<port>`.
- After `register-enroll.sh`: confirmed non-empty `tls/server.key`,
  `tls/server.crt`, `tls/ca.crt` for `peer0.hospitala...` and non-empty
  MSP signcert for `orderer1...`.
- `configtxgen -inspectBlock network/channel-artifacts/healthchannel.block`
  — confirmed `HospitalAMSP`, `HospitalBMSP`, `LabMSP`, `OrdererMSP` all
  present in the block's embedded config.
- All 4 new containers (`orderer1...`, `peer0.hospitala...`,
  `peer0.hospitalb...`, `peer0.lab...`) came up clean — no errors in
  logs; orderer log confirmed it started with 0 channels (no
  bootstrap-from-file), as expected.
- `osnadmin channel join` on the orderer returned `Status: 201`,
  `"status": "active", "height": 1"`.
- `peer channel join` succeeded for all 3 peers; `peer channel list` run
  against each of the 3 peers afterwards confirmed each one reports
  membership in `healthchannel`.
- `docker ps` after `deploy-chaincode.sh`: all 3 `proofoflife-*`
  containers `Up`, no crash-restart loop.
- `smoke-test.sh`'s `Put` from Hospital A (endorsed by Hospital A + B)
  returned `status:200`; the following `Get` via the Lab's peer (not an
  endorser of the write) returned exactly `"hello from Hospital A"`.
- `peer channel getinfo` afterwards showed the channel's block height at
  6: genesis (1) + 3 chaincode approvals + 1 commit + 1 invoke = 5
  `submit` transactions, each producing a block, which matches exactly
  what the scripts did — good confirmation of the earlier "only submit
  creates a block, evaluate doesn't" explanation.

### How this interacts with existing functionality

Independent of Phase 1's `docker-compose.yml` (Postgres/MinIO) — Fabric's
network is brought up separately via `network/docker-compose-ca.yaml` and
`network/docker-compose-net.yaml`, per the plan noted in Phase 1's
changelog entry.

### Assumptions / trade-offs

- CA bootstrap admin credentials (`admin:adminpw`) and all registered
  identity secrets (`peer0pw`, `<org>adminpw`, `orderer1pw`,
  `ordererAdminpw`) are hardcoded in the script in plaintext. Acceptable
  for a local dev/demo network with no real secrets on the line; would
  need to move to a secrets mechanism before this pattern could be reused
  for a real deployment.
- Chaincode-as-a-Service means chaincode containers are no longer
  automatically managed by the peer — `deploy-chaincode.sh` builds one
  shared image and starts 3 containers (one per org) by hand. A future
  phase adding/upgrading chaincode needs to remember to rebuild the image
  and restart these containers, not just re-run the lifecycle commands.
- `proofoflife` itself is throwaway — two functions, no real data model,
  deleted or replaced entirely once Phase 3 defines the actual
  organization/doctor registry chaincode.

### Checkpoint

Per `docs/phases.md`'s Phase 2 scope ("a minimal Go chaincode that just
proves the network works end to end"), this phase's checkpoint is met:
3 peer orgs + 1 orderer org, one shared channel, all 3 peers joined, one
chaincode installed/approved/committed across all 3 orgs, and one write
from one org's peer confirmed readable from a different org's peer that
never endorsed it.
