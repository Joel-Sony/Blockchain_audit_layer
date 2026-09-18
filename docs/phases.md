# Development Phases

Do not start a phase until the previous one's checkpoint is confirmed
working. Order below reflects ADR-006 (Go backend, no separate Fabric
bridge) — this replaces the original bridge-as-its-own-phase plan.

- **Phase 0** — Environment verification and architecture freeze. Confirm
  installed tooling matches `docs/decisions.md` / `CLAUDE.md` stack.
- **Phase 1** — Repository/folder structure + Docker base infrastructure.
- **Phase 2** — Basic Fabric network: Hospital A, Hospital B, Lab, one
  shared channel, one peer each, ordering service, CA, a minimal Go
  chaincode that just proves the network works end to end.
- **Phase 3** — Real chaincode data models: organization registry, doctor
  registry (register/revoke), basic validation rules.
- **Phase 4** — Go backend skeleton: auth (JWT + Argon2id), PostgreSQL
  schema/migrations, and Fabric Gateway client wiring so the backend can
  evaluate/submit transactions directly (no separate bridge service).
- **Phase 5** — File upload endpoint: SHA-256 hashing, AES-256-GCM
  encryption, encrypted storage in MinIO.
- **Phase 6** — Doctor ECDSA signing of the canonical record manifest +
  `CreateRecord()` chaincode transaction, including chaincode-side checks
  (org identity from MSP, doctor authorization, signature validity,
  duplicate detection).
- **Phase 7** — Record verification endpoint + live tampering demo (Demo 1)
  + forged signature demo (Demo 2).
- **Phase 8** — Patient blockchain identity (signing key pair) + consent
  flow (`GrantConsent`/`DenyConsent`/`RevokeConsent`).
- **Phase 9** — Cross-hospital access requests + secure record sharing
  (Demo 3): `CreateAccessRequest`, consent check, direct hospital-to-hospital
  transfer.
- **Phase 10** — Audit history, view events (`LogView`), unauthorized
  access attempts (`LogAccessAttempt`, Demo 4).
- **Phase 11** — Record versioning/corrections: `CreateRecordVersion`,
  `SUPERSEDED`/`CURRENT` status transitions, parent-record linkage.
- **Phase 12** — Emergency/break-glass access: reason capture, audit event,
  patient-visible notice.
- **Phase 13** — FHIR R4 interoperability, scoped to the Blood Test /
  Diagnostic Report subset (`Patient`, `Observation`, `DiagnosticReport`,
  `DocumentReference`).
- **Phase 14** — HFR verification adapter (mock + real-client interface)
  and organization join governance (proposal + voting).
- **Phase 15** — Real Fabric new-organization onboarding script
  (`./scripts/onboard-org.sh`) — actual MSP/channel-config operations,
  separate from the governance vote that authorizes it.
- **Phase 16** — React dashboards (Patient / Doctor / Admin) and UI
  refinement.
- **Phase 17** — Integration testing across the full stack; run through
  all four demo scenarios end to end.
- **Phase 18** — Documentation, architecture diagrams, viva preparation
  (see `docs/viva-concepts.md`).

## After each phase, expect a checkpoint like

```
CHECKPOINT
You should now be able to:
✓ <specific, testable thing>
✓ <specific, testable thing>

Try this: <one simple manual test>
```

Don't move on until that checkpoint actually works for you.