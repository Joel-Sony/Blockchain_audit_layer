# Viva / Exam Concepts

Checklist of things to actually understand, not just have working code
for. Explain these as they come up naturally in the relevant phase —
don't front-load all of them at once.

## Fabric fundamentals
- What is a peer? An orderer? An MSP? Fabric CA?
- What is a channel, and why does it matter for healthcare (data
  visibility between orgs)?
- What is chaincode, and how is it different from "the blockchain" itself?
- What is endorsement? What is consensus, and why does Fabric use
  crash/Byzantine-fault-tolerant ordering instead of Proof-of-Work?
- What is world state vs. blockchain (transaction) history? Why can world
  state change (e.g. a record's status flips to `SUPERSEDED`) while the
  ledger itself stays immutable?
- What is Fabric Gateway, and what problem does it solve compared to
  older Fabric SDKs?
- What is a transaction proposal? What's the difference between
  **evaluate** (query, no block created) and **submit** (write,
  endorsed/ordered/committed)?
- How does a new peer synchronize old ledger history when it joins?
- What happens if one peer goes offline — does the network stop?

## Why these specific technology choices
- Why Fabric instead of a public chain like Ethereum? (permissioned
  membership, no mining/gas, identity-based accountability)
- Why doesn't PostgreSQL alone provide the same trust model? (single
  administrative domain vs. independently-operated replicated ledger)
- Why Go for chaincode and backend? (native chaincode language, official
  Gateway SDK removes the need for a separate bridge service)
- Why SHA-256 for integrity? Why does hashing work identically regardless
  of file type (PDF, JPEG, DICOM, ...)?
- What does an ECDSA digital signature actually prove, and how does
  public/private key verification work?
- Why AES-256-GCM specifically (vs. plain AES)? What does the "GCM" part add?
- Why MinIO instead of storing files on-chain?
- Why FHIR? What problem is schema mismatch, and how does FHIR solve it
  without being a security mechanism itself?

## Identity and trust boundaries
- Why don't patients or doctors run Fabric peers?
- Why are a doctor's login identity, their ECDSA signing key, and their
  organization's Fabric identity three genuinely different things?
- Why does patient consent use a real cryptographic signature instead of
  just "the backend says they clicked approve"? Does having a signing key
  make the patient a Fabric node? (No — explain why.)
- Why must critical checks (org identity, doctor authorization, signature
  validity) live in chaincode and not only in the Go backend or React?

## Lifecycle questions
- Why can a *revoked* doctor's old, legitimately-signed records remain
  valid? What's actually being checked at verification time?
- Why can't an incorrect record simply be edited? Why create a new
  version instead?
- Why don't two records with different hashes for the same patient/doc
  type automatically become "versions" of each other?
- Why doesn't a rejected/failed Fabric transaction automatically produce
  an audit event for a denied access attempt?

## Organization onboarding
- How does a new hospital actually join the network? Walk through:
  HFR registry check → governance vote → real Fabric channel
  configuration update → peer joins channel → chaincode installed/approved
  for the new org.
- Why doesn't the governance vote itself perform the Fabric channel change?