#!/usr/bin/env bash
# Live walkthrough of the Phase 2 network, for presenting.
# Pauses between steps (press Enter). Steps 1-5 only read; step 6 submits
# one real transaction, so the ledger grows by one block each time you run it.
#
# Needs the network running (all CA, orderer, peer and proofoflife containers).

set -euo pipefail
cd "$(dirname "$0")/../network"

FABRIC_BIN="${FABRIC_BIN:-$(cd ../fabric-samples/bin && pwd)}"
export PATH="${FABRIC_BIN}:${PATH}"
export FABRIC_CFG_PATH="${PWD}/config/peercfg"
export CORE_PEER_TLS_ENABLED=true

CHANNEL=healthchannel
ORDERER_CA="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/tlsca/tlsca.orderer.healthcare.com-cert.pem"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Act as one org's admin — same env vars the network scripts use.
use_org() {
  local domain="$1" msp_id="$2" address="$3"
  export CORE_PEER_LOCALMSPID="${msp_id}"
  export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/organizations/peerOrganizations/${domain}/tlsca/tlsca.${domain}-cert.pem"
  export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/${domain}/users/Admin@${domain}/msp"
  export CORE_PEER_ADDRESS="${address}"
}
use_hospitala() { use_org hospitala.healthcare.com HospitalAMSP localhost:7051; }
use_hospitalb() { use_org hospitalb.healthcare.com HospitalBMSP localhost:8051; }
use_lab()       { use_org lab.healthcare.com LabMSP localhost:9051; }

step() {
  echo
  read -r -p "--- press Enter for: $1 ---"
  echo
}

show_heights() {
  for org in use_hospitala use_hospitalb use_lab; do
    "${org}"
    printf '%-13s ' "${CORE_PEER_LOCALMSPID}"
    peer channel getinfo -c "${CHANNEL}" 2>/dev/null | sed 's/Blockchain info: //' \
      | jq -c '{height, currentBlockHash}'
  done
}

step "1. The running network (4 CAs, 1 orderer, 3 peers, 3 chaincode containers)"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAMES|ca-|healthcare|proofoflife"

step "2. Identities: the role (OU) is written inside each certificate"
for who in peers/peer0.hospitala.healthcare.com users/Admin@hospitala.healthcare.com; do
  echo "${who}:"
  openssl x509 -noout -subject -issuer \
    -in "organizations/peerOrganizations/hospitala.healthcare.com/${who}/msp/signcerts/cert.pem"
  echo
done

step "3. Every peer has the same chain (same height, same latest block hash)"
show_heights

step "4. The chaincode all three orgs approved and committed"
use_hospitala
peer lifecycle chaincode querycommitted -C "${CHANNEL}" 2>/dev/null

step "5. Inside a real block (block 5: the smoke test's Put)"
peer channel fetch 5 "${TMP_DIR}/block.pb" -c "${CHANNEL}" \
  -o localhost:7050 --tls --cafile "${ORDERER_CA}" 2>/dev/null
configtxlator proto_decode --input "${TMP_DIR}/block.pb" --type common.Block > "${TMP_DIR}/block.json"
jq '.data.data[0].payload as $tx
  | $tx.data.actions[0].payload as $action
  | {
      number:        .header.number,
      previous_hash: .header.previous_hash,
      data_hash:     .header.data_hash,
      submitted_by:  $tx.header.signature_header.creator.mspid,
      call:          [$action.chaincode_proposal_payload.input.chaincode_spec.input.args[] | @base64d],
      endorsed_by:   [$action.action.endorsements[].endorser | @base64d | capture("(?<m>[A-Za-z]+MSP)").m],
      writes:        [$action.action.proposal_response_payload.extension.results.ns_rwset[]
                      | select(.namespace == "proofoflife") | .rwset.writes[]
                      | {key, value: (.value | @base64d)}]
    }' "${TMP_DIR}/block.json"

step "6. LIVE: Hospital A writes, Hospital A + B endorse, a new block is created"
KEY="demo-$(date +%H%M%S)"
VALUE="written live at $(date +%T)"
echo "Before:"
show_heights
use_hospitala
echo
echo "Submitting Put(\"${KEY}\", \"${VALUE}\") ..."
peer chaincode invoke -o localhost:7050 --tls --cafile "${ORDERER_CA}" \
  -C "${CHANNEL}" -n proofoflife --waitForEvent \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${PWD}/organizations/peerOrganizations/hospitala.healthcare.com/tlsca/tlsca.hospitala.healthcare.com-cert.pem" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "${PWD}/organizations/peerOrganizations/hospitalb.healthcare.com/tlsca/tlsca.hospitalb.healthcare.com-cert.pem" \
  -c "{\"function\":\"Put\",\"Args\":[\"${KEY}\",\"${VALUE}\"]}" 2>&1 | grep -o "Chaincode invoke successful.*" || true
echo
echo "After (height +1 on every peer, including the Lab, which did not endorse):"
show_heights

step "7. Read it back from the Lab's peer (a query: no new block)"
use_lab
echo "Lab's peer returns: $(peer chaincode query -C "${CHANNEL}" -n proofoflife -c "{\"function\":\"Get\",\"Args\":[\"${KEY}\"]}")"
show_heights
echo
echo "Done."
