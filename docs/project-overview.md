# Project Overview — Blockchain-Based Healthcare Record Verification System

> **Purpose of this document:** a complete, self-contained description of the
> project for anyone (human or LLM) who needs to write a report, abstract,
> presentation, or viva answer about it without reading the whole repo.
> It covers the problem, objectives, architecture, every component, the
> security model, data flows, demo scenarios, technology justifications,
> the development plan, and **exactly what has been built so far vs. what
> is still planned**.
>
> **Last updated:** 2026-09-30 (end of Phase 2 of 19).
>
> **Important for report writers:** Sections are marked with a status where
> relevant:
> - ✅ **Implemented** — exists in the repo and has been verified working.
> - 🟡 **Designed / planned** — decided and documented, not yet coded.
>
> Do not describe planned features as finished work.

---

## Table of contents

1. [One-paragraph summary](#1-one-paragraph-summary)
2. [Problem statement](#2-problem-statement)
3. [Objectives](#3-objectives)
4. [What the system is — and is not](#4-what-the-system-is--and-is-not)
5. [Stakeholders and actors](#5-stakeholders-and-actors)
6. [High-level architecture](#6-high-level-architecture)
7. [Components in detail](#7-components-in-detail)
8. [On-chain vs. off-chain data](#8-on-chain-vs-off-chain-data)
9. [Cryptography used and why](#9-cryptography-used-and-why)
10. [Identity model — three separate identities](#10-identity-model--three-separate-identities)
11. [Security model and trust boundaries](#11-security-model-and-trust-boundaries)
12. [Core workflows (end to end)](#12-core-workflows-end-to-end)
13. [Demo scenarios](#13-demo-scenarios)
14. [Record lifecycle rules](#14-record-lifecycle-rules)
15. [Interoperability: HL7 FHIR R4 and ABDM](#15-interoperability-hl7-fhir-r4-and-abdm)
16. [Organization onboarding and governance](#16-organization-onboarding-and-governance)
17. [Technology stack and justification](#17-technology-stack-and-justification)
18. [Hyperledger Fabric concepts used](#18-hyperledger-fabric-concepts-used)
19. [Development methodology and phase plan](#19-development-methodology-and-phase-plan)
20. [Current implementation status (detailed)](#20-current-implementation-status-detailed)
21. [Architecture decisions (ADR log)](#21-architecture-decisions-adr-log)
22. [Problems encountered and solutions](#22-problems-encountered-and-solutions)
23. [Repository structure](#23-repository-structure)
24. [How to run what exists today](#24-how-to-run-what-exists-today)
25. [Limitations, assumptions, and future scope](#25-limitations-assumptions-and-future-scope)
26. [Glossary](#26-glossary)
27. [Notes for report writers](#27-notes-for-report-writers)

---

## 1. One-paragraph summary

This is a final-year BTech project that builds a **permissioned blockchain
audit and verification layer for medical records** shared between
hospitals and diagnostic labs. Medical files (e.g. a blood test report PDF)
are stored **off-chain**, encrypted with AES-256-GCM in MinIO object
storage. What goes **on-chain** — on a Hyperledger Fabric network run
jointly by the participating hospitals and lab — is a tamper-evident proof
of each record: its SHA-256 hash, the issuing doctor's ECDSA P-256 digital
signature, the issuing organization's identity, patient consent decisions,
access requests, record version links, and an audit trail of who viewed,
shared, was denied, or used emergency access. Any hospital receiving a
record can independently recompute the hash and check the signature
against its **own copy** of the shared ledger, so it never has to simply
trust the sending hospital. Patients are referenced on-chain only by a
pseudonymous ID and give cryptographically signed consent. Records are
exchanged in HL7 FHIR R4 format aligned with India's Ayushman Bharat
Digital Mission (ABDM). The backend is written in Go and talks to Fabric
directly via the official Fabric Gateway SDK; the frontend is React; the
whole stack runs in Docker.

---

## 2. Problem statement

Healthcare records today are fragmented across institutions, each running
its own database. When a patient moves from Hospital A to Hospital B, or a
lab sends results to a clinic, several problems arise:

1. **No independent way to prove a record is authentic.** A PDF or a
   database row can be edited (by an insider, an attacker, or by accident)
   and the receiver cannot tell. Changing `Glucose: 96 mg/dL` to
   `196 mg/dL` in a report is trivial and invisible.
2. **No reliable proof of authorship.** A record may *say* "signed by
   Dr John," but there is no cryptographic evidence that Dr John actually
   produced it, or that he was authorized at the time.
3. **Single administrative domain = single point of trust.** A central
   database (even a well-secured PostgreSQL instance) is controlled by one
   administrator. That administrator can rewrite history, including audit
   logs. Other hospitals must trust them completely.
4. **Weak, unverifiable consent.** "The patient clicked approve" is just a
   row the application wrote; it is not independently provable.
5. **Poor auditability.** Unauthorized access attempts, emergency
   "break-glass" access, and record sharing are often not logged in a way
   that the patient or other organizations can see or trust.
6. **Schema mismatch between systems.** Different hospital systems store
   the same medical information in different formats, making exchange
   error-prone.
7. **Privacy constraints.** Medical data is highly sensitive (and subject to
   law), so simply "putting records on a blockchain" is not acceptable —
   blockchains are replicated and effectively permanent.

The project addresses these by separating **data** (kept private,
encrypted, off-chain) from **proof** (hashes, signatures, consent, audit
events kept on a shared, replicated, append-only ledger operated by
multiple independent organizations).

---

## 3. Objectives

### Primary objectives

1. **Tamper detection:** detect any modification to a medical file after
   it was registered, by comparing a freshly computed SHA-256 hash with the
   hash recorded on the blockchain.
2. **Authorship proof:** bind every record to a specific doctor through an
   ECDSA P-256 digital signature over a canonical record manifest, and
   detect forged signatures.
3. **Authorization at creation time:** verify (in chaincode) that the
   signing doctor was registered and active with the issuing organization
   **at the moment the record was created**.
4. **Cross-organization verification without trust:** allow a receiving
   hospital to verify a record entirely against its own peer's copy of the
   ledger, without trusting the sending hospital.
5. **Patient-controlled consent:** record patient consent
   (grant/deny/revoke) on-chain as a cryptographically signed decision.
6. **Complete, trustworthy audit trail:** record views, shares, denied
   access attempts, and emergency access as on-chain events visible to the
   patient.
7. **Privacy by design:** keep all medical content and personal
   identifiers off-chain; use pseudonymous patient IDs on-chain; encrypt
   files at rest.

### Secondary objectives

8. **Append-only versioning:** corrections create a new linked version;
   history is never mutated.
9. **Interoperability:** exchange records as HL7 FHIR R4 resources,
   aligned with ABDM.
10. **Consortium governance:** model how a new hospital is verified (HFR
    registry check), voted in, and actually onboarded onto the Fabric
    network.
11. **Demonstrability:** four live demos (tampering, forged signature,
    cross-hospital verification, unauthorized access) that can be run in
    front of an examiner.

### Learning objectives (explicitly part of the project)

The author is learning Hyperledger Fabric, applied cryptography, backend
architecture, Docker, and FHIR during the project. The project therefore
favours **simple, readable, explainable** code over clever abstractions,
and maintains a checklist of concepts to be able to explain in the viva
(`docs/viva-concepts.md`).

---

## 4. What the system is — and is not

**It is:**
- A **verification and audit layer** that sits alongside hospital systems.
- A **permissioned consortium blockchain** (Hyperledger Fabric) run by
  hospitals and labs.
- A backend + web app that lets doctors upload and sign records, patients
  manage consent and see their audit trail, and hospitals verify records
  they receive.

**It is not:**
- **Not a blockchain that stores medical records.** Files, diagnoses, and
  personal details never go on-chain.
- **Not a public/cryptocurrency blockchain.** No mining, no gas, no tokens,
  no Ethereum/Polygon.
- **Not a full Electronic Health Record (EHR) system.** It handles a
  focused demo record type (Blood Test / Diagnostic Report).
- **Not a general FHIR server.** Only the four FHIR R4 resources needed for
  the demo are implemented.
- **Not a replacement for access control in the application** — it adds an
  independent, cryptographically enforced layer underneath it.

---

## 5. Stakeholders and actors

| Actor | Who they are | Runs a Fabric node? | What they do |
|---|---|---|---|
| **Hospital A** | Healthcare organization (`HospitalAMSP`) | Yes — one peer | Creates records, shares them, verifies incoming records |
| **Hospital B** | Healthcare organization (`HospitalBMSP`) | Yes — one peer | Requests access, receives & verifies records |
| **Lab** | Diagnostic lab organization (`LabMSP`) | Yes — one peer | Produces diagnostic reports; independent verifier/endorser |
| **Orderer organization** | Neutral ordering-service operator (`OrdererMSP`) | Yes — ordering node | Orders transactions into blocks; not a hospital |
| **Doctor** | Application user employed by an org | **No** | Logs in, uploads and signs records, requests access |
| **Patient** | Application user | **No** | Approves/denies/revokes consent, views their audit trail |
| **Org admin** | Application/admin user | No | Registers/revokes doctors, governance votes |
| **Hospital D (optional)** | Prospective new member | Not until onboarded | Demonstrates the join process |

**Key principle:** patients and doctors are **application users**, not
blockchain nodes. Only organizations operate Fabric infrastructure.
Doctors and patients do still hold their own **signing keys** (for record
signatures and consent signatures), but a signing key does not make
someone a Fabric node.

---

## 6. High-level architecture

```
                         ┌──────────────────────────────────────────┐
                         │               React Frontend             │ 🟡
                         │  Patient portal · Doctor dashboard · Admin│
                         └────────────────────┬─────────────────────┘
                                              │ HTTPS / JSON (JWT auth)
                         ┌────────────────────▼─────────────────────┐
                         │            Go Backend (chi router)        │ 🟡
                         │  auth (JWT + Argon2id) · validation        │
                         │  SHA-256 hashing · AES-256-GCM encryption  │
                         │  ECDSA verification · FHIR R4 mapping      │
                         │  Fabric Gateway client (evaluate/submit)   │
                         └───────┬───────────────┬──────────────┬────┘
                                 │               │              │ gRPC (Fabric Gateway SDK)
                 ┌───────────────▼──┐   ┌────────▼───────┐   ┌──▼───────────────────────────────┐
                 │   PostgreSQL 16  │✅ │   MinIO (S3)   │✅ │ Hyperledger Fabric network        │✅
                 │ users, sessions, │   │ AES-256-GCM    │   │ channel: healthchannel            │
                 │ patient PII,     │   │ encrypted files│   │                                   │
                 │ key metadata,    │   │ (off-chain)    │   │  peer0.hospitala  (HospitalAMSP)  │
                 │ FHIR data        │   │                │   │  peer0.hospitalb  (HospitalBMSP)  │
                 └──────────────────┘   └────────────────┘   │  peer0.lab        (LabMSP)        │
                                                             │  orderer1 (OrdererMSP, etcdraft)  │
                                                             │  4 × Fabric CA                    │
                                                             │  Go chaincode (CCaaS containers)  │
                                                             └───────────────────────────────────┘
```

(✅ = infrastructure running today; 🟡 = planned. The Fabric network is
running with a throwaway test chaincode; the real healthcare chaincode
starts in Phase 3.)

### Architectural layers

1. **Presentation layer** — React dashboards for patients, doctors, admins.
2. **Application layer** — a single Go backend. It authenticates users,
   validates requests, hashes/encrypts files, builds FHIR resources, and
   submits/evaluates Fabric transactions directly using the official Go
   Fabric Gateway SDK. There is **no separate "blockchain bridge"
   microservice** (earlier plans had one; it was removed to simplify).
3. **Off-chain storage layer** — PostgreSQL (structured, private
   application data) and MinIO (encrypted files).
4. **Trust layer** — Hyperledger Fabric: a shared ledger replicated on
   every organization's peer, with Go chaincode enforcing the security
   rules independently of the backend.

---

## 7. Components in detail

### 7.1 Hyperledger Fabric network ✅ (infrastructure) / 🟡 (real chaincode)

- **Organizations (4):** `HospitalAMSP`, `HospitalBMSP`, `LabMSP` (peer
  orgs), `OrdererMSP` (ordering org).
- **Certificate Authorities (4):** one `hyperledger/fabric-ca` container
  per org (`ca-hospitala` :7054, `ca-hospitalb` :8054, `ca-lab` :9054,
  `ca-orderer` :10054). Each org issues its own identities through
  register/enroll — the realistic approach rather than the tutorial
  `cryptogen` tool.
- **Peers (3):** `peer0.hospitala.healthcare.com` (:7051),
  `peer0.hospitalb.healthcare.com` (:8051), `peer0.lab.healthcare.com`
  (:9051). Each holds a full copy of the ledger and world state and
  endorses transactions.
- **Orderer (1):** `orderer1.orderer.healthcare.com` (:7050, admin API
  :7053), Raft (`etcdraft`) consensus, single node, batch timeout 2s,
  max 10 messages per block. Started with no system channel; joined to the
  channel via the channel participation API (`osnadmin`).
- **Channel:** `healthchannel`, all three peer orgs as members. Profile
  `HealthcareChannel` in `network/configtx/configtx.yaml`.
- **Policies:** channel-level endorsement and lifecycle endorsement are
  `MAJORITY Endorsement` (i.e. 2 of 3 peer orgs must endorse a write);
  admin changes need `MAJORITY Admins`. Each org's MSP uses Node OUs so the
  role (admin / peer / client / orderer) is embedded in each certificate.
- **TLS:** enabled everywhere between Fabric components (separate TLS
  certs per node).
- **Chaincode deployment mode:** Chaincode-as-a-Service (CCaaS). One Docker
  image, one chaincode container per org; the peer connects to it over the
  private Docker network (see ADR-004 for why).
- **Current chaincode:** `proofoflife` — a throwaway contract with `Put`
  (submit, writes a key) and `Get` (evaluate, reads a key), used only to
  prove the network works end to end. It will be replaced in Phase 3.

### 7.2 Chaincode (smart contracts) 🟡

Written in Go using `fabric-contract-api-go`. Planned functions (from
`docs/phases.md` and `docs/demo-scenarios.md`):

| Area | Planned functions / responsibilities | Phase |
|---|---|---|
| Organization registry | Register organizations, record status | 3 |
| Doctor registry | Register doctor (with ECDSA public key), revoke doctor, keep activity history | 3 |
| Record creation | `CreateRecord()` — verifies caller's org **from MSP identity** (not from payload), doctor authorized & active for that org, ECDSA signature valid over the manifest, no duplicate record | 6 |
| Verification queries | Read record proof, doctor status at creation time | 7 |
| Consent | `GrantConsent`, `DenyConsent`, `RevokeConsent` (patient-signed) | 8 |
| Access requests | `CreateAccessRequest`, consent checking | 9 |
| Audit | `LogView`, `LogAccessAttempt(..., outcome="DENIED")` | 10 |
| Versioning | `CreateRecordVersion` with `parentRecordId`; status `CURRENT` → `SUPERSEDED` | 11 |
| Emergency access | Break-glass event with reason, patient-visible | 12 |
| Governance | Org join proposals and voting | 14 |

**Design rule:** security checks live **in chaincode**, not only in the
backend or UI. Even if the backend were compromised, chaincode would still
refuse a record whose signature is invalid or whose submitting org doesn't
match the doctor's org.

### 7.3 Go backend 🟡

- **Router:** `chi` (kept thin, not a full framework).
- **Validation:** `go-playground/validator` struct tags.
- **Authentication:** JWT for sessions; passwords hashed with Argon2id
  (`golang.org/x/crypto/argon2`).
- **Fabric access:** official Go **Fabric Gateway SDK**. `evaluate` for
  reads (no block created), `submit` for writes (endorse → order →
  commit, creates a block). The backend uses its **organization's** Fabric
  client identity.
- **File pipeline:** receive upload → SHA-256 of raw bytes → AES-256-GCM
  encrypt → store ciphertext in MinIO → build canonical manifest → doctor
  signs → submit `CreateRecord`.
- **Verification endpoint:** recompute hash, fetch on-chain proof, verify
  ECDSA signature, check signer's authorization at creation time, return a
  checklist result.
- **FHIR mapping:** hand-written R4 structs for `Patient`, `Observation`,
  `DiagnosticReport`, `DocumentReference` only.
- **API docs:** hand-maintained `docs/api.md` (no Swagger generation for
  now).
- **Crypto libraries:** Go standard library `crypto/*` and
  `golang.org/x/crypto` only.

### 7.4 PostgreSQL ✅ (running, empty) / 🟡 (schema)

`postgres:16-alpine`, database `healthcare_records`, port 5432, named
volume `postgres-data`. Will hold the **private, off-chain** application
data: user accounts and password hashes, patient personal details (name,
contact, etc.), mappings from real patients to pseudonymous IDs, key
metadata, FHIR data, and references to MinIO objects. Schema and migrations
arrive in Phase 4.

### 7.5 MinIO ✅ (running, no buckets) / 🟡 (usage)

S3-compatible object storage, image `quay.io/minio/minio`, S3 API on
:9000, web console on :9001, named volume `minio-data`. Will store the
actual medical files, **always encrypted with AES-256-GCM** before
upload. Buckets are created in Phase 5.

### 7.6 React frontend 🟡 (Phase 16)

Three dashboards:
- **Patient portal:** see incoming access requests, approve/deny/revoke
  consent, see the audit trail (including denied and emergency access).
- **Doctor dashboard:** upload & sign records, look up a patient by
  pseudonymous ID, request access, verify received records.
- **Admin dashboard:** manage doctors, organizations, governance votes.

Verification results are shown as a clear checklist (see §13).

### 7.7 Demo / presentation tooling ✅

- `demo/live-demo.sh` — interactive, step-by-step walkthrough of the
  running Phase 2 network for presenting: running containers, identities
  and their OUs, identical chain height/hash on every peer, committed
  chaincode, contents of a real block, a live write endorsed by Hospital A
  + B, and reading it back from the Lab's peer.
- `demo/ledger-demo.html` — "Healthchannel Explorer", a visual page for
  presenting the ledger.
- `docs/reports/phase2-system-walkthrough.pdf` — a walkthrough report of
  the Phase 2 system.

---

## 8. On-chain vs. off-chain data

This split is the core privacy decision of the project.

### On-chain (Fabric ledger) — only proofs and metadata

- SHA-256 hashes of record files
- Doctors' ECDSA signatures over record manifests
- Organization registry and doctor registry (incl. doctor public keys and
  status history)
- Patient consent decisions (signed)
- Access requests
- Record version pointers (`parentRecordId`, `CURRENT`/`SUPERSEDED`)
- Audit events: view, share, deny, emergency access
- Governance proposals/votes (Phase 14)
- Patients referenced **only by a pseudonymous ID**

### Never on-chain

- The actual files (PDFs, images, DICOM, etc.)
- Diagnoses or any clinical content
- Patient name, email, phone, address
- Passwords
- Raw Aadhaar numbers

**Why:** a blockchain is replicated to every member and cannot be deleted
from. Anything sensitive written there is permanently exposed to every
organization. Hashes reveal nothing about the file's contents but still
prove integrity.

> Note: `docs/data-model.md` (the detailed field-level data model) is
> currently an empty placeholder; exact struct/field definitions will be
> written as Phases 3–11 are implemented. Don't invent field names in a
> report — describe the entities above.

---

## 9. Cryptography used and why

| Primitive | Used for | Why this one |
|---|---|---|
| **SHA-256** | Fingerprint of the raw file bytes | Any single-bit change produces a completely different hash; collision-resistant; works identically for PDF, JPEG, DICOM or any file type because it hashes bytes, not meaning |
| **ECDSA P-256** | Doctor signatures on record manifests; patient consent signatures | Proves *who* signed and that the signed data wasn't changed; short keys/signatures; standard curve supported by Go stdlib and Fabric |
| **AES-256-GCM** | Encrypting files at rest in MinIO | Authenticated encryption: GCM gives confidentiality **and** integrity (a tampered ciphertext fails to decrypt), unlike plain AES modes like CBC |
| **Argon2id** | Password hashing | Memory-hard, current recommended password hash; resists GPU brute force |
| **JWT** | Session tokens between frontend and backend | Stateless, standard |
| **X.509 / TLS (via Fabric CA)** | Fabric node & client identities, encrypted node-to-node traffic | Fabric's native identity model (MSP) |

### How tamper detection works
1. At upload: `H1 = SHA-256(original file)` → stored on-chain.
2. At verification: `H2 = SHA-256(file received)`.
3. `H1 ≠ H2` ⇒ file was modified ⇒ **TAMPERING DETECTED**.

### How signature verification works
1. The doctor's private key signs a canonical manifest that includes the
   file hash (and record metadata).
2. The doctor's public key is registered on-chain in the doctor registry.
3. Anyone can verify the signature with the public key. A signature made
   with any other private key fails ⇒ **FORGED SIGNATURE**, even if the
   file hash matches.

---

## 10. Identity model — three separate identities

A doctor effectively has three different identities that must never be
conflated:

| Identity | What it is | Where it lives | What it proves |
|---|---|---|---|
| **Login identity** | Username + password (Argon2id hash), JWT session | PostgreSQL / backend | "This person is logged into our web app" |
| **Doctor's ECDSA signing key** | P-256 key pair; public key registered on-chain | Private key with the doctor; public key on ledger | "Dr John authored this record" |
| **Organization's Fabric identity** | X.509 cert issued by the org's Fabric CA, in its MSP | Backend's Fabric Gateway client | "Hospital A submitted this transaction" |

Chaincode derives the **organization** from the transaction's MSP identity
(which Fabric authenticates), **not** from anything written in the payload.
It then checks the doctor belongs to that organization and verifies the
doctor's signature separately.

Patients similarly have a login identity and (from Phase 8) their own
signing key pair for consent, without being Fabric nodes.

---

## 11. Security model and trust boundaries

1. **No single party controls the truth.** The ledger is replicated on
   peers run by different organizations; a write needs endorsement by a
   majority of orgs; ordering is done by a separate org.
2. **Defense in depth — chaincode enforces the rules.** The backend and UI
   do checks for usability, but chaincode independently verifies org
   identity (from MSP), doctor authorization, and signature validity. A
   forged record is rejected at registration, not just flagged later.
3. **Verify, don't trust.** A receiving hospital verifies against its own
   peer; it doesn't rely on the sender's claims.
4. **Privacy through separation.** Sensitive data off-chain and encrypted;
   only pseudonymous IDs and hashes on-chain.
5. **Cryptographic consent.** Consent is signed by the patient, not just a
   database flag.
6. **Explicit auditing of denials.** A rejected or failed Fabric
   transaction does *not* automatically create an audit event. Denied
   application-level access is recorded by a deliberate, separate
   `LogAccessAttempt(..., outcome="DENIED")` submit.
7. **Reads vs writes.** Queries (`evaluate`) never create blocks; only
   `submit` transactions do. (Verified empirically in Phase 2: block height
   matched the exact number of submits.)
8. **Historic validity.** Authorization is checked *as of creation time*,
   so revoking a doctor later doesn't invalidate their past legitimate
   signatures, while any new record they try to sign is rejected.
9. **Immutability of history.** Records are append-only; corrections are
   new versions.

### Threats addressed

| Threat | Mitigation |
|---|---|
| File edited after issue | SHA-256 mismatch against ledger |
| Record forged in a doctor's name | ECDSA verification against registered public key; chaincode rejects at creation |
| Hospital claims to be another hospital | Org derived from Fabric MSP identity, not payload |
| Revoked doctor keeps issuing records | Chaincode checks doctor status at creation |
| Insider rewrites audit log | Audit events on replicated, append-only ledger |
| Unauthorized doctor reads a record | Consent check; file not released; DENIED event logged, visible to patient |
| Storage breach of MinIO | Files encrypted with AES-256-GCM |
| Personal data leak via blockchain | No PII on-chain; pseudonymous IDs |

---

## 12. Core workflows (end to end) 🟡

### 12.1 Record creation
1. Doctor logs in (JWT).
2. Uploads a report (e.g. `blood_report.pdf`).
3. Backend computes SHA-256 of raw bytes.
4. Backend encrypts the file with AES-256-GCM, stores ciphertext in MinIO.
5. Backend builds a canonical manifest (hash + record metadata incl.
   pseudonymous patient ID, doc type, org, doctor).
6. Doctor's ECDSA key signs the manifest.
7. Backend `submit`s `CreateRecord` via Fabric Gateway using its org
   identity.
8. Chaincode checks: org from MSP, doctor registered and active for that
   org, signature valid, not a duplicate → writes record proof.
9. Peers endorse, orderer orders, all peers commit → new block.

### 12.2 Verification
1. Obtain the file (and record ID).
2. Recompute SHA-256.
3. `evaluate` the record proof from the local peer.
4. Compare hashes; verify ECDSA signature with the doctor's registered
   public key; check the doctor was authorized at creation time; check
   record status (current vs superseded).
5. Return checklist: hash matches / signature valid / signer identified /
   signer authorized at creation / record unchanged.

### 12.3 Cross-hospital sharing
1. Hospital B's doctor looks up the patient by global pseudonymous ID.
2. Submits `CreateAccessRequest` for a record type (e.g. Blood Test).
3. Patient sees the request in their portal, approves → signed consent
   recorded on-chain.
4. Hospital A sends the FHIR R4 data + exact original file **directly** to
   Hospital B (off-chain — the blockchain never carries the file).
5. Hospital B verifies independently against its own peer → AUTHENTIC.

### 12.4 Unauthorized access
1. A doctor without valid consent requests a record.
2. Backend refuses to release the file.
3. Backend explicitly submits `LogAccessAttempt(..., outcome="DENIED")`.
4. Patient portal shows the attempt (who, which org, when).

### 12.5 Correction (versioning)
1. Doctor issues a corrected record via `CreateRecordVersion` referencing
   `parentRecordId`.
2. Old version flips to `SUPERSEDED`, new one is `CURRENT` (world state
   changes) — but the old version and its full history remain in the
   ledger.

### 12.6 Emergency (break-glass) access
Doctor gives a reason, access is granted outside normal consent, an
emergency audit event is recorded, and the patient is notified.

---

## 13. Demo scenarios

These four demos are the **core deliverables** — everything else exists to
make them work and be shown live.

### Demo 1 — Live tampering detection
Upload `blood_report.pdf` → hash registered → edit `Glucose: 96 mg/dL` to
`196 mg/dL` → re-verify.
```
TAMPERING DETECTED
Expected hash: 91AF8D...
Current hash:  28BB19...
HASH MISMATCH
```

### Demo 2 — Forged signature detection
File untouched (hash matches) but signed with a key that isn't Dr John's.
```
FILE HASH MATCHES
BUT
DIGITAL SIGNATURE INVALID
CLAIMED SIGNER: DR JOHN
FORGED SIGNATURE DETECTED
```
Chaincode must also reject such a record if someone tries to register it.

### Demo 3 — Cross-hospital verification
Hospital A creates → Hospital B requests → patient consents → A sends
file + FHIR directly to B → B verifies on its own peer.
```
AUTHENTIC
Hash matches blockchain        ✓
Digital signature valid        ✓
Signer identified              ✓
Signer authorized at creation  ✓
Record unchanged               ✓

Signed by: Dr John
Organization: Hospital A
Created: <date/time>
```

### Demo 4 — Unauthorized access attempt
Doctor without consent tries to access → blocked → explicit DENIED audit
transaction → patient sees:
```
UNAUTHORIZED ACCESS ATTEMPT
Dr X
Hospital B
<time>
Access blocked.
```

### Full demo story (final walkthrough)
1. Dr John (Hospital A) uploads `blood_report.pdf`: hashed, signed,
   encrypted, committed.
2. Dr Sarah (Hospital B) looks up the patient and requests the Blood Test.
3. Patient approves in their portal; consent signed and recorded.
4. Hospital A sends ABDM-compatible FHIR R4 data + original file to B.
5. Hospital B verifies on its own peer → AUTHENTIC.
6. Glucose edited 96 → 196 → TAMPERING DETECTED.
7. Forged Dr John signature → DIGITAL SIGNATURE INVALID.
8. Unauthorized doctor → denied, `DENIED_ACCESS` logged, patient sees it.

Optional (only if time permits): 9) emergency/break-glass access;
10) V2 correction with V1 marked `SUPERSEDED`; 11) Hospital D verified via
HFR, voted in, and **really** onboarded onto the channel via a network
admin script.

### Already-demonstrable today (Phase 2)
`demo/live-demo.sh` shows a real multi-org Fabric network: 4 CAs, 1
orderer, 3 peers, 3 chaincode containers; identical chain on every peer; a
live write by Hospital A endorsed by Hospital A + B, creating a new block;
and reading the value back from the Lab's peer (which did not endorse it),
proving replication — and that the read creates no block.

---

## 14. Record lifecycle rules

- **Append-only:** records are never edited in place.
- **Corrections = new version** with `parentRecordId`; old becomes
  `SUPERSEDED`, new is `CURRENT`.
- **World state vs. ledger:** the *current status* in world state can
  change, but the ledger (transaction history) is immutable, so every
  previous state remains provable.
- **Different hashes ≠ versions:** two records with different hashes for
  the same patient/document type are *not* automatically versions of each
  other; versioning is explicit.
- **Revoked doctors:** past records signed while active remain valid;
  verification checks status at creation time.

---

## 15. Interoperability: HL7 FHIR R4 and ABDM 🟡 (Phase 13)

- **FHIR (Fast Healthcare Interoperability Resources) R4** is the HL7
  standard for exchanging healthcare data as typed JSON "resources".
- **ABDM (Ayushman Bharat Digital Mission)** is India's national digital
  health initiative; it uses FHIR R4 and has registries such as **HFR
  (Health Facility Registry)**. The project is *aligned* with ABDM
  conventions, not integrated with the live ABDM production systems.
- Scope is limited to the Blood Test / Diagnostic Report demo:
  `Patient`, `Observation` (e.g. glucose value), `DiagnosticReport`
  (groups observations), `DocumentReference` (points to the original
  file / its hash).
- **FHIR solves schema mismatch, not security.** It makes data
  understandable across systems; integrity and authenticity come from the
  blockchain + signatures.

---

## 16. Organization onboarding and governance 🟡 (Phases 14–15)

How a new hospital (e.g. Hospital D) joins:
1. **HFR registry check** — verify the facility is real (mock adapter +
   real-client interface).
2. **Governance proposal & vote** — existing members vote in chaincode.
3. **Real Fabric channel config update** — an admin script
   (`scripts/onboard-org.sh`) adds the new org's MSP to the channel
   configuration, collecting the required admin signatures.
4. **New peer joins the channel** and syncs the full ledger history.
5. **Chaincode installed/approved** for the new org.

**Key point:** the chaincode vote *authorizes* onboarding; it does not
*perform* the channel change. Changing channel membership is a network
configuration operation done by org admins. The project deliberately does
not fake this.

---

## 17. Technology stack and justification

| Layer | Choice | Why |
|---|---|---|
| Blockchain | **Hyperledger Fabric 2.5** | Permissioned (known members), identity-based accountability, no mining/gas, private channels, fast finality, enterprise/healthcare fit |
| Chaincode | **Go** (`fabric-contract-api-go`) | Fabric's native chaincode language, best supported |
| Backend | **Go** + Fabric Gateway SDK | Official SDK talks to Fabric directly — no separate bridge service; one language for chaincode + backend |
| Router | **chi** | Thin, idiomatic, standard `net/http` compatible |
| Validation | `go-playground/validator` | Declarative struct-tag validation |
| Frontend | **React** | Standard, component-based dashboards |
| Database | **PostgreSQL 16** | Reliable relational store for private app data |
| File storage | **MinIO** | S3-compatible, self-hostable, keeps big files off-chain |
| Encryption | **AES-256-GCM** | Authenticated encryption |
| Hash | **SHA-256** | Standard, collision-resistant integrity fingerprint |
| Signatures | **ECDSA P-256** | Standard, compact, stdlib-supported |
| Passwords | **Argon2id** | Modern memory-hard password hashing |
| Interop | **HL7 FHIR R4**, ABDM-aligned | Healthcare exchange standard used by India's ABDM |
| Deployment | **Docker / Docker Compose** | Reproducible multi-container setup |

### Why not Ethereum / a public chain?
Public chains expose all data to everyone, require gas fees, have
probabilistic finality and anonymous participants. Healthcare needs known,
accountable, permissioned members and no transaction fees.

### Why not just PostgreSQL?
A database has a single administrative domain: whoever controls it can
rewrite rows and logs. Fabric's ledger is independently operated and
replicated by several organizations with endorsement policies, so no single
hospital can alter history unnoticed.

### Why not store files on-chain?
Size/performance (every peer stores everything forever), and privacy
(replicated + undeletable). Hash on-chain, encrypted file off-chain gives
integrity without exposure.

### Development environment (Phase 0)
Go 1.27.1 (user-local install), Docker 29.7.2, Docker Compose v5.4.0,
Node.js v22.19.0 / npm 10.9.3, psql 14.24, Git 2.55.0, Linux. Fabric
binaries and images from the official `install-fabric.sh` (peer/orderer
2.5.x, `fabric-ca`).

---

## 18. Hyperledger Fabric concepts used

- **Peer** — node that stores the ledger + world state, runs/connects to
  chaincode, and endorses transactions.
- **Orderer** — orders endorsed transactions into blocks and distributes
  them; does not execute chaincode. Run by a separate org here so no
  hospital controls sequencing.
- **MSP (Membership Service Provider)** — defines which certificates belong
  to an organization and what role (admin/peer/client/orderer via Node
  OUs) they have.
- **Fabric CA** — issues X.509 certificates for an org (register → enroll).
- **Channel** — a private sub-ledger shared by a set of orgs
  (`healthchannel`). Controls data visibility.
- **Chaincode** — the smart contract; business logic that reads/writes
  world state. Distinct from the blockchain itself.
- **Chaincode lifecycle** — package → install (per peer) → approve (per
  org) → commit (once, when enough orgs approved).
- **CCaaS** — chaincode runs as an external service the peer connects to.
- **Endorsement** — selected peers simulate a transaction and sign the
  result; the endorsement policy (here: majority) decides how many are
  needed.
- **Execute–order–validate** — Fabric's transaction flow: endorse
  (simulate) → order → validate & commit on every peer.
- **Raft (etcdraft)** — crash-fault-tolerant ordering consensus; no
  Proof-of-Work.
- **World state vs. ledger** — world state is the current key→value
  snapshot (CouchDB/LevelDB); the ledger is the immutable chain of all
  transactions. State can change; history can't.
- **Evaluate vs. submit** — evaluate = query one peer, no block; submit =
  full endorse/order/commit flow, creates a block.
- **Fabric Gateway** — Fabric 2.4+ peer service + thin SDKs that handle
  endorsement collection and submission, replacing heavier older SDKs.
- **Block height** — number of blocks; identical on all peers when in
  sync.

---

## 19. Development methodology and phase plan

The project is built in **19 gated phases** (0–18). Each phase:
explain what/why/how-it-connects → implement → give a manual test →
**checkpoint** that must work before moving on. Architectural decisions
are logged in `docs/decisions.md` (ADR format) and implementation detail in
`CHANGELOG.md`. Code style: simple and readable over clever, no speculative
abstractions, complete runnable files.

| Phase | Scope | Status |
|---|---|---|
| 0 | Environment verification, architecture freeze | ✅ Done |
| 1 | Repo structure + Docker base infra (Postgres, MinIO) | ✅ Done |
| 2 | Basic Fabric network: 3 peer orgs + orderer org, CAs, channel, test chaincode | ✅ Done |
| 3 | Real chaincode data models: org registry, doctor registry, validation | 🟡 Next |
| 4 | Go backend skeleton: JWT + Argon2id auth, Postgres schema, Fabric Gateway wiring | 🟡 |
| 5 | File upload: SHA-256, AES-256-GCM, MinIO storage | 🟡 |
| 6 | Doctor ECDSA signing + `CreateRecord` with chaincode-side checks | 🟡 |
| 7 | Verification endpoint; Demo 1 (tamper) & Demo 2 (forgery) | 🟡 |
| 8 | Patient signing keys + consent (Grant/Deny/Revoke) | 🟡 |
| 9 | Cross-hospital access requests + sharing (Demo 3) | 🟡 |
| 10 | Audit history, `LogView`, `LogAccessAttempt` (Demo 4) | 🟡 |
| 11 | Versioning/corrections (`CreateRecordVersion`) | 🟡 |
| 12 | Emergency/break-glass access | 🟡 |
| 13 | FHIR R4 (Patient, Observation, DiagnosticReport, DocumentReference) | 🟡 |
| 14 | HFR verification adapter + org join governance | 🟡 |
| 15 | Real Fabric new-org onboarding script | 🟡 |
| 16 | React dashboards (Patient/Doctor/Admin) | 🟡 |
| 17 | Full-stack integration testing, all four demos | 🟡 |
| 18 | Documentation, architecture diagrams, viva prep | 🟡 |

---

## 20. Current implementation status (detailed)

### Phase 0 ✅
Toolchain installed/verified (see §17). Go installed user-local because
`sudo` is not available non-interactively (ADR-000).

### Phase 1 ✅ (2026-09-18)
- `docker-compose.yml` with `postgres` (16-alpine, healthcheck
  `pg_isready`) and `minio` (quay.io image, healthcheck on
  `/minio/health/live`), credentials from `.env` (template `.env.example`).
- Placeholder `backend/` and `chaincode/` directories.
- Fixed `.gitignore` that had been hiding all `.md` docs from git.
- Verified: both containers healthy; real `psql` connection; MinIO health
  endpoint reachable.

### Phase 2 ✅ (2026-09-21)
- 4 Fabric CAs (`network/docker-compose-ca.yaml`).
- `register-enroll.sh`: org admins, peer identities (MSP + TLS), orderer
  identities.
- `configtx.yaml`: 4 org definitions, `HealthcareChannel` profile,
  etcdraft orderer.
- Genesis block for `healthchannel` via `configtxgen -outputBlock`.
- `docker-compose-net.yaml`: 1 orderer + 3 peers.
- `join-channel.sh`: orderer joined via `osnadmin`, all 3 peers joined.
- `proofoflife` Go chaincode in CCaaS mode, own Dockerfile; 3 chaincode
  containers (one per org).
- `deploy-chaincode.sh`: package/install/approve (all 3 orgs)/commit.
- `smoke-test.sh`: `Put("greeting","hello from Hospital A")` endorsed by
  Hospital A + B; `Get("greeting")` from the Lab's peer returned the value.
- Verified: block height 6 = genesis + 3 approvals + 1 commit + 1 invoke,
  confirming only submits create blocks.
- Demo tooling: `demo/live-demo.sh`, `demo/ledger-demo.html`, and a Phase 2
  walkthrough PDF.

### Not yet built
Real chaincode, Go backend, database schema, file encryption pipeline,
signatures, consent, audit, versioning, FHIR, governance, frontend.

---

## 21. Architecture decisions (ADR log)

| ADR | Decision | Reason |
|---|---|---|
| 000 | Go installed user-local (`~/.local/go`) | No non-interactive sudo; no functional downside |
| 001 | Fabric CA, not `cryptogen` | Realistic identity issuance; CA is in Phase 2 scope |
| 002 | 4 orgs: 3 peer orgs + separate OrdererOrg | No single hospital controls transaction ordering |
| 003 | Single-node etcdraft orderer, no system channel | Enough to prove the pipeline; production would use 3+ Raft nodes; Fabric 2.x channel participation API |
| 004 | Chaincode-as-a-Service | Fabric 2.5's embedded Docker client fails against Docker Engine 29.x (`broken pipe`); CCaaS is the recommended modern approach and removes the peer's need for the Docker socket (smaller attack surface) |
| (stack) | Go backend using Fabric Gateway directly, no separate bridge service | Fewer moving parts; official SDK (referenced as ADR-006 in `docs/phases.md`) |

---

## 22. Problems encountered and solutions

Good material for a "challenges faced" section:

1. **`.gitignore` contained `*.md`** — all documentation silently untracked.
   Rewrote `.gitignore`.
2. **`minio/minio` Docker Hub pull denied** — switched to
   `quay.io/minio/minio`.
3. **`fabric-ca-client -M` relative paths** resolved against
   `FABRIC_CA_CLIENT_HOME` — used absolute paths.
4. **Non-idempotent CA registration** after a partial failure — reset CA
   data (deleted via a throwaway Alpine container because files were
   root-owned).
5. **`peer` CLI "core config not found"** — set `FABRIC_CFG_PATH` to a
   project-local `core.yaml`.
6. **`osnadmin` re-join returns 405 but exit 0** — harmless; scripts are
   safely re-runnable.
7. **Classic chaincode install failed (`docker.sock: broken pipe`)** —
   incompatibility between Fabric 2.5's Docker client and Docker Engine
   29.x; moved to CCaaS (ADR-004).
8. **Invoke failed: missing client MSP** — endorsing peers vs submitting
   client identity are separate settings; exported the client identity.

---

## 23. Repository structure

```
Blockchain_audit_layer/
├── CLAUDE.md                  # project rules, locked stack, architecture rules
├── CHANGELOG.md               # detailed per-phase implementation log
├── README.md
├── .env.example               # Postgres/MinIO credential template
├── docker-compose.yml         # Postgres + MinIO (Phase 1)
├── backend/                   # Go backend (Phase 4+, empty now)
├── chaincode/
│   └── proofoflife/           # throwaway Phase 2 chaincode (Go, CCaaS)
│       ├── proofoflife.go
│       ├── Dockerfile
│       └── go.mod / go.sum
├── network/
│   ├── docker-compose-ca.yaml # 4 Fabric CAs
│   ├── docker-compose-net.yaml# orderer + 3 peers
│   ├── configtx/configtx.yaml # orgs, policies, channel profile
│   ├── config/peercfg/core.yaml
│   ├── organizations/         # CA certs (generated crypto is gitignored)
│   └── scripts/
│       ├── register-enroll.sh
│       ├── join-channel.sh
│       ├── deploy-chaincode.sh
│       └── smoke-test.sh
├── demo/
│   ├── live-demo.sh           # interactive presentation of the network
│   └── ledger-demo.html       # "Healthchannel Explorer" visual
└── docs/
    ├── project-overview.md    # this file
    ├── phases.md              # 19-phase plan
    ├── decisions.md           # ADR log
    ├── demo-scenarios.md      # the four demos + full story
    ├── data-model.md          # (placeholder, to be filled)
    ├── viva-concepts.md       # concepts to explain in viva
    ├── environment-setup.md   # Phase 0 toolchain
    └── reports/phase2-system-walkthrough.pdf
```

---

## 24. How to run what exists today

```bash
# Phase 1: base infra
cp .env.example .env
docker compose up -d
docker compose ps                        # postgres + minio healthy

# Phase 2: Fabric network (from network/, Fabric binaries in fabric-samples/bin)
docker compose -f network/docker-compose-ca.yaml up -d
network/scripts/register-enroll.sh
configtxgen -profile HealthcareChannel -outputBlock \
  network/channel-artifacts/healthchannel.block -channelID healthchannel
docker compose -f network/docker-compose-net.yaml up -d
network/scripts/join-channel.sh
network/scripts/deploy-chaincode.sh
network/scripts/smoke-test.sh            # Put via A+B, Get via Lab

# Presenting
demo/live-demo.sh
```

(See `CHANGELOG.md` for exact per-step detail and env vars.)

---

## 25. Limitations, assumptions, and future scope

**Current limitations / assumptions**
- Single orderer node → no orderer fault tolerance (production: 3+ Raft
  nodes).
- One peer per org; a production org would run multiple.
- Dev-only hardcoded CA credentials (`admin:adminpw` etc.).
- Chaincode–peer link has TLS disabled (private Docker network only).
- CCaaS containers must be rebuilt/restarted manually on chaincode updates.
- Single demo document type (Blood Test / Diagnostic Report).
- ABDM *alignment*, not live ABDM/HFR integration (HFR via mock adapter +
  interface).
- Key custody for doctor/patient private keys is simplified for a demo.
- Everything runs on one machine via Docker.

**Future scope**
- Multi-node Raft ordering, multiple peers per org, Kubernetes deployment.
- Hardware-backed keys (HSM / smart cards) for doctor signatures.
- Live ABDM integration (ABHA IDs, HFR, HIE-CM consent manager).
- Private data collections for finer-grained visibility.
- More FHIR resources and document types (imaging/DICOM, prescriptions).
- Automated test suites, monitoring, and Swagger/OpenAPI docs.
- Revocation/rotation of doctor keys with key history.

---

## 26. Glossary

| Term | Meaning |
|---|---|
| ABDM | Ayushman Bharat Digital Mission — India's digital health programme |
| ABHA | ABDM health ID for patients |
| ADR | Architecture Decision Record |
| AES-256-GCM | Symmetric authenticated encryption |
| Argon2id | Memory-hard password hashing function |
| Break-glass | Emergency access that bypasses normal consent but is audited |
| CA | Certificate Authority |
| CCaaS | Chaincode-as-a-Service |
| Chaincode | Hyperledger Fabric smart contract |
| ECDSA P-256 | Elliptic-curve digital signature algorithm on NIST P-256 |
| Endorsement | Peers simulating and signing a transaction result |
| FHIR R4 | HL7 Fast Healthcare Interoperability Resources, release 4 |
| HFR | Health Facility Registry (ABDM) |
| JWT | JSON Web Token |
| MinIO | Self-hosted S3-compatible object store |
| MSP | Membership Service Provider (Fabric org identity definition) |
| Node OU | Organizational unit in a cert marking its role |
| Orderer | Fabric node that sequences transactions into blocks |
| Peer | Fabric node holding ledger/world state, endorsing transactions |
| Pseudonymous ID | Non-identifying patient identifier used on-chain |
| Raft / etcdraft | Crash-fault-tolerant consensus used by Fabric orderers |
| SHA-256 | 256-bit cryptographic hash function |
| World state | Current key/value snapshot derived from the ledger |

---

## 27. Notes for report writers

- **Be precise about status.** As of 2026-09-30, Phases 0–2 are complete:
  the Docker infra and a working 4-organization Fabric network with a test
  chaincode. Everything from Phase 3 onward (real chaincode, backend,
  cryptographic record pipeline, consent, FHIR, UI) is designed but not
  implemented. For a mid-project report, write these as "proposed
  methodology / system design"; for a final report, update this document
  first.
- **Don't invent** field-level schemas, API endpoints, performance numbers,
  or test results — none exist yet beyond what's in §20.
- **Emphasize the core idea:** data off-chain and encrypted; proof
  on-chain and shared; verification done independently by each org.
- **Good diagrams to include:** the architecture diagram (§6), the record
  creation sequence (§12.1), the verification checklist (§13), the
  on-chain/off-chain split (§8), and the Fabric network topology
  (§7.1).
- **Suggested report outline:** Abstract → Introduction & problem →
  Literature/background (blockchain in healthcare, Fabric vs Ethereum,
  FHIR/ABDM) → Objectives → System architecture → Module design →
  Security model → Implementation (per phase) → Demo scenarios/results →
  Limitations & future scope → Conclusion.
- Source documents: `CLAUDE.md`, `docs/phases.md`,
  `docs/demo-scenarios.md`, `docs/decisions.md`, `docs/viva-concepts.md`,
  `CHANGELOG.md`.
