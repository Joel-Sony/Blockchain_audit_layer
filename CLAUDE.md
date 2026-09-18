# Blockchain-Based Healthcare Record Verification System

Final-year BTech project. I am learning Hyperledger Fabric, cryptography,
backend architecture, Docker, and FHIR as we go — explain concepts, don't
just produce code.

## Code style — this overrides instinct toward "impressive" code

- Simple and readable beats clever. No abstraction, pattern, or generic
  layer unless the current phase actually needs it.
- No speculative flexibility ("might need this later"). Build for what's
  asked now.
- Small, obviously-named files and functions over dense ones.
- Comment *why*, not *what* — only where the reason isn't obvious from the code.
- If a simple version and a "more correct" complex version both satisfy the
  phase's requirement, pick the simple one and say so.
- Every file must be complete and runnable — no `...`, no pseudocode, no
  "left as an exercise."

## Stack — locked, do not substitute without explicit approval

| Layer | Choice |
|---|---|
| Blockchain | Hyperledger Fabric (not Ethereum/Polygon) |
| Chaincode | Go (`fabric-contract-api-go`) |
| Backend | Go — talks to Fabric directly via the official Go Fabric Gateway SDK (no separate bridge service) |
| Backend router | `chi` (or `gin`) — kept thin, not a full framework |
| Frontend | React |
| DB | PostgreSQL |
| File storage | MinIO (S3-compatible), off-chain, AES-256-GCM encrypted |
| File hash | SHA-256 |
| Doctor signatures | ECDSA P-256 |
| Interop | HL7 FHIR R4, ABDM-aligned |
| Deployment | Docker / Docker Compose |

If you think a decision here should change: say why and wait for approval.
Never swap silently, even to "simplify."

### Go-specific notes (things FastAPI used to give for free)

- Request validation: use `go-playground/validator` with struct tags, don't
  hand-roll ad-hoc checks per handler.
- No auto-generated API docs for now — keep `docs/api.md` updated by hand
  as endpoints are added. Revisit `swaggo` only if there's time later.
- FHIR: only hand-write the specific R4 structs actually needed
  (`Patient`, `Observation`, `DiagnosticReport`, `DocumentReference` for the
  Blood Test / Diagnostic Report demo type) — do not attempt a general FHIR
  struct library.
- Crypto (ECDSA P-256, AES-256-GCM, Argon2id): use Go stdlib `crypto/*` and
  `golang.org/x/crypto` — no third-party crypto libraries unless a specific
  gap is found.

## Non-negotiable architecture rules

- Patients and doctors are **application users**, not Fabric peers. Only
  hospital/lab organizations run Fabric nodes.
- Doctor login identity, doctor's ECDSA signing key, and the organization's
  Fabric identity are three different things — never conflate them.
- **On-chain:** hashes, signatures, doctor/org registries, consent, access
  requests, version pointers, audit events (view/share/deny/emergency).
- **Never on-chain:** actual files, diagnoses, patient name/email/phone/address,
  passwords, raw Aadhaar. Patients are referenced only by a pseudonymous ID.
- Records are append-only. Corrections create a new version
  (`parentRecordId`); never mutate history in place.
- A revoked doctor's *past* signatures made while active stay valid.
  Verification checks authorization **at creation time**, not current status.
- Security must live in chaincode, not just FastAPI or React. Chaincode
  must independently verify org identity (from Fabric MSP, not payload
  claims), doctor authorization, and signatures.
- A denied application-level access attempt is not automatically a Fabric
  event — it requires an explicit `LogAccessAttempt(..., outcome="DENIED")` call.
- Reading the ledger (`evaluate`/query) does not create a block. Only
  `submit` transactions do.
- Adding a real hospital to the Fabric channel is a real network/config
  operation — chaincode governance voting can authorize it, but never
  pretend the vote itself performs the channel change.

## Workflow

- Build in phases (see `docs/phases.md`). Do not start the next phase until
  I confirm the current checkpoint works.
- For each phase: explain what/why/what-it-connects-to *before* writing
  code, then implement, then give a short manual test I can run.
- If I paste an error: debug the existing code first. Don't redesign
  the architecture in response to a bug.
- If uncertain about current Fabric/library API syntax, say so — don't
  invent plausible-looking syntax.
- Log meaningful architecture decisions in `docs/decisions.md` (ADR
  format, short — decision + one-line reason).

## Reference docs (read when relevant to the current task, not every turn)

- `docs/data-model.md` — full on-chain/off-chain data model
- `docs/demo-scenarios.md` — the four core demo flows + optional scenes
- `docs/phases.md` — full phase breakdown (19 phases)
- `docs/decisions.md` — ADR log
- `docs/viva-concepts.md` — concepts to explain as we go (peer, MSP,
  endorsement, world state vs. ledger, etc.)

## Current phase

Not started. Do not generate implementation code until I send
`START PHASE 1`.