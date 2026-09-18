# Demo Scenarios

These four are the core deliverables — everything else in the project
exists to make these work correctly and be demonstrable live.

## Demo 1 — Live tampering detection

1. Upload a legitimate report (e.g. `blood_report.pdf`).
2. Backend computes `SHA-256(raw file bytes)`, registers hash + record
   proof on Fabric.
3. Manually edit the file afterward (e.g. change `Glucose: 96 mg/dL` to
   `Glucose: 196 mg/dL`).
4. Re-verify. New hash won't match the on-chain hash.

Expected UI:
```
TAMPERING DETECTED
Expected hash: 91AF8D...
Current hash:  28BB19...
HASH MISMATCH
```

## Demo 2 — Forged signature detection

A record claims to be signed by Dr John but was actually signed with a
different private key. Verification recomputes the hash (which matches —
the file itself wasn't touched) but fails ECDSA signature verification
against Dr John's registered public key.

Expected UI:
```
FILE HASH MATCHES
BUT
DIGITAL SIGNATURE INVALID
CLAIMED SIGNER: DR JOHN
FORGED SIGNATURE DETECTED
```

A forged record must also be rejected by chaincode if someone tries to
register it as a new transaction, not just flagged at verification time.

## Demo 3 — Cross-hospital verification

1. Hospital A creates a record for a patient.
2. Hospital B requests access; patient approves (consent signed and
   recorded on-chain).
3. Hospital A transfers the record (file + FHIR data) directly to
   Hospital B — **not** through the blockchain.
4. Hospital B independently recomputes the hash and checks Fabric on its
   own peer — it does not have to trust Hospital A's word.

Expected UI:
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

## Demo 4 — Unauthorized access attempt

An unauthorized doctor (no valid consent) tries to access a patient's
record. The file must not be released. A separate audit transaction
(`LogAccessAttempt(..., outcome="DENIED")`) is submitted explicitly — a
rejected/failed Fabric transaction does **not** automatically become an
audit event, so this has to be a deliberate second call.

Patient-facing UI:
```
UNAUTHORIZED ACCESS ATTEMPT
Dr X
Hospital B
<time>
Access blocked.
```

## Full demo story (scenes, for the final walkthrough)

1. Dr John (Hospital A) logs in, uploads `blood_report.pdf`. SHA-256
   generated, ECDSA signature generated, file encrypted, Fabric
   transaction committed.
2. Dr Sarah (Hospital B) looks up the same patient by their global
   pseudonymous ID and requests the Blood Test record.
3. Patient opens their portal, sees "Hospital B requests access to Blood
   Test," approves. Consent is signed and recorded.
4. Hospital A sends the ABDM-compatible FHIR R4 data + exact original
   file to Hospital B.
5. Hospital B verifies independently on its own peer → **AUTHENTIC**.
6. Glucose value is manually edited (96 → 196). Re-verify →
   **TAMPERING DETECTED**.
7. A forged Dr John signature is tested → **DIGITAL SIGNATURE INVALID**.
8. An unauthorized doctor tries to view the file without consent → denied,
   `DENIED_ACCESS` event logged, patient sees the attempt.

**Optional scenes** (attempt only if core scenes above are solid with time
to spare):

9. Emergency/break-glass access demonstrated.
10. Doctor corrects a record via append-only V2 versioning
    (old record flips to `SUPERSEDED`, ledger history for V1 preserved).
11. Hospital D is HFR-registry-verified, approved via consortium vote, and
    actually onboarded onto the live Fabric channel via a network-admin
    script (not faked through chaincode alone).