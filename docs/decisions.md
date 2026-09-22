# Architecture Decision Log

Short ADR entries — decision + one-line reason. Full stack choices live in
`CLAUDE.md`; this file is for decisions made *along the way*.

## ADR-000 — Go installed user-local, not system-wide

Installed Go 1.27.1 to `~/.local/go` instead of `/usr/local` because this
machine's `sudo` requires a password not available non-interactively.
No functional downside — PATH is set in `~/.bashrc` and `~/.profile`.
See `docs/environment-setup.md`.

## ADR-001 — Fabric CA (not `cryptogen`) for network identities

Each org runs its own `hyperledger/fabric-ca` container and issues its own
identities via register/enroll, instead of pre-generating static certs
offline with `cryptogen`. Matches Phase 2's scope (`docs/phases.md`
explicitly lists "CA" as a Phase 2 component) and how real deployments
actually issue identities — `cryptogen` is a tutorial-only shortcut.

## ADR-002 — 4 orgs: 3 peer orgs + a separate OrdererOrg

`HospitalAMSP`, `HospitalBMSP`, `LabMSP` each run one peer. Ordering is
owned by a 4th, separate `OrdererMSP` rather than any one hospital, so no
single hospital can unilaterally control transaction sequencing for the
other two. See chat transcript for the fuller "why does the orderer exist
/ who owns it" explanation — worth re-reading before the viva.

## ADR-003 — Single-node etcdraft orderer, no system channel

One orderer node (`orderer1`) is enough to prove the pipeline end-to-end
per Phase 2's scope; a real deployment would run 3+ Raft nodes for fault
tolerance — revisit if a later phase needs to demo orderer resilience.
Genesis block is generated directly as an application channel genesis
block (`configtxgen -outputBlock`, Fabric 2.x style) rather than via an
old-style system channel + channel-creation transaction.

## ADR-004 — Chaincode-as-a-Service (CCaaS), not peer-built Docker chaincode

Chaincode containers are built and started by us directly
(`docker build` / `docker run`), with the peer only told the running
container's address — instead of the classic mode where the peer itself
calls the Docker daemon to build and start the chaincode container.
Forced by a real compatibility break: the peer's embedded Docker API
client fails against this machine's Docker Engine (29.x) with `docker
build failed: write unix @->/run/docker.sock: write: broken pipe` — a
known incompatibility between Fabric 2.5's vendored Docker client and
recent Docker Engine versions, not something fixable by retrying or
reconfiguring the peer. CCaaS is also the officially recommended
approach going forward (Fabric 2.4+): it also means the peer no longer
needs the host's Docker socket mounted into it at all, which is a smaller
attack surface. Trade-off: chaincode containers must now be built/started
by hand (or a script) as part of deploying/updating any chaincode,
instead of that happening automatically on `peer lifecycle chaincode
install`.
