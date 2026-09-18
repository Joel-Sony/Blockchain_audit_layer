# Environment Setup (Phase 0)

Records what's installed, how, and why — so the environment can be
reproduced or checked against `CLAUDE.md`'s locked stack at any time.

## Status: done

| Tool | Required for | Version | Install method | Status |
|---|---|---|---|---|
| Go | Chaincode, backend | 1.27.1 | Official tarball, user-local (no sudo) | ✅ installed |
| Docker | Fabric network, Postgres, MinIO, Compose | 29.7.2 | Already present | ✅ verified |
| Docker Compose | Multi-service orchestration | v5.4.0 (plugin) | Already present (`docker compose`) | ✅ verified |
| Node.js / npm | React frontend | v22.19.0 / 10.9.3 | Already present | ✅ verified |
| PostgreSQL client (`psql`) | Inspecting the DB | 14.24 | Already present | ✅ verified |
| Git | Version control | 2.55.0 | Already present | ✅ verified |

**Not installed yet, on purpose:** Hyperledger Fabric binaries/Docker images
(`peer`, `orderer`, `cryptogen`, `configtxgen`, CA), and a running Postgres/
MinIO instance. Per `docs/phases.md`, those are brought up in **Phase 2**
(Fabric network) and **Phase 1** (Docker Compose base infra) respectively —
installing them now would jump ahead of the phase gate. This doc only covers
the *language toolchains* needed to start Phase 1.

## Go — installation detail

Installed to `~/.local/go` (not `/usr/local`) because this machine's `sudo`
requires a password we don't have non-interactively. This is a completely
normal way to run Go and has no downsides for this project.

```bash
# what was done
curl -sL -o go1.27.1.linux-amd64.tar.gz https://go.dev/dl/go1.27.1.linux-amd64.tar.gz
# checksum verified against https://go.dev/dl/?mode=json before extracting
tar -C ~/.local -xzf go1.27.1.linux-amd64.tar.gz
```

PATH is set in both `~/.bashrc` (interactive shells) and `~/.profile`
(login shells) under the marker `GO_INSTALL_MARKER`:

```bash
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
```

`$HOME/go` is `GOPATH` (where `go install`-ed binaries and the module cache
live) — created automatically by the Go toolchain on first use, not by this
setup.

**New terminal required:** this only takes effect in shells started after
this change. Run `source ~/.bashrc` in an already-open terminal, or just
open a new one.

### Verify

```bash
go version          # go version go1.27.1 linux/amd64
which go            # ~/.local/go/bin/go
go env GOPATH GOROOT
```

## Docker

Already installed and working — verified with `docker run --rm hello-world`
and `docker info`. The current user can run Docker without `sudo` (already
in the `docker` group), which matters because Compose will run as this user
throughout the project.

## Node.js / npm

Already present system-wide, used for the Phase 16 React dashboards. No
action needed until that phase.

## PostgreSQL

Only the **client** (`psql`) is installed on the host, for inspecting the
database. The actual Postgres **server** will run as a Docker container
(via `docker-compose.yml`, Phase 1) — never installed directly on the host.
Same plan for MinIO.

## Deferred to later phases

- **Hyperledger Fabric binaries + sample network config** — pulled via the
  official bootstrap script in Phase 2:
  ```bash
  curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh | bash -s -- docker samples binary
  ```
  Not run yet. Flagging the command here so it's not a surprise later.
- **Go module dependencies** (`fabric-contract-api-go`, `chi`/`gin`,
  `go-playground/validator`, `golang.org/x/crypto`) — these are per-module
  `go get`s once `go.mod` files exist (Phase 1+), not standalone installs.

## Re-verifying this environment later

```bash
go version && docker --version && docker compose version && node --version && psql --version
```

If any of these fail in a fresh shell, the most likely cause is `~/.bashrc`'s
early-exit-on-non-interactive guard — re-check `~/.profile` picked up the
`GO_INSTALL_MARKER` line.
