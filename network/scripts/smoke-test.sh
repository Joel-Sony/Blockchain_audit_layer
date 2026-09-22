#!/usr/bin/env bash
# Phase 2, step 7: the actual end-to-end proof.
#
# Submits one write (Put), endorsed by 2 of the 3 orgs (this channel's
# default endorsement policy is "majority of channel members"), then reads
# it back via the THIRD org's peer — one that did not endorse the write —
# to prove the result really replicated across the shared channel, not
# just written locally to one peer.

set -euo pipefail
cd "$(dirname "$0")/.."   # always run from network/

FABRIC_BIN="$(cd ../fabric-samples/bin && pwd)"
export PATH="${FABRIC_BIN}:${PATH}"
export FABRIC_CFG_PATH="${PWD}/config/peercfg"
export CORE_PEER_TLS_ENABLED=true

CHANNEL_NAME=healthchannel
CC_NAME=proofoflife
ORDERER_CA="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/tlsca/tlsca.orderer.healthcare.com-cert.pem"
HOSPITALA_TLSCA="${PWD}/organizations/peerOrganizations/hospitala.healthcare.com/tlsca/tlsca.hospitala.healthcare.com-cert.pem"
HOSPITALB_TLSCA="${PWD}/organizations/peerOrganizations/hospitalb.healthcare.com/tlsca/tlsca.hospitalb.healthcare.com-cert.pem"

echo "== Submitting Put(\"greeting\", \"hello from Hospital A\") =="
echo "   endorsed by Hospital A + Hospital B; this creates a new block"
export CORE_PEER_LOCALMSPID=HospitalAMSP
export CORE_PEER_TLS_ROOTCERT_FILE="${HOSPITALA_TLSCA}"
export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/hospitala.healthcare.com/users/Admin@hospitala.healthcare.com/msp"
export CORE_PEER_ADDRESS=localhost:7051
peer chaincode invoke \
  -o localhost:7050 --tls --cafile "${ORDERER_CA}" \
  -C "${CHANNEL_NAME}" -n "${CC_NAME}" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${HOSPITALA_TLSCA}" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "${HOSPITALB_TLSCA}" \
  -c '{"function":"Put","Args":["greeting","hello from Hospital A"]}'

echo
echo "waiting 3s for the block to commit on all peers..."
sleep 3

echo
echo "== Querying Get(\"greeting\") via the Lab's peer (did NOT endorse the write) =="
echo "   this is an 'evaluate' — reads local world state, creates no block"
export CORE_PEER_LOCALMSPID=LabMSP
export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/organizations/peerOrganizations/lab.healthcare.com/tlsca/tlsca.lab.healthcare.com-cert.pem"
export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/lab.healthcare.com/users/Admin@lab.healthcare.com/msp"
export CORE_PEER_ADDRESS=localhost:9051
RESULT=$(peer chaincode query -C "${CHANNEL_NAME}" -n "${CC_NAME}" -c '{"function":"Get","Args":["greeting"]}')

echo "Lab's peer returned: ${RESULT}"
if [ "${RESULT}" = "hello from Hospital A" ]; then
  echo
  echo "SUCCESS: the write made by Hospital A replicated to the Lab's peer."
else
  echo
  echo "UNEXPECTED RESULT — investigate before treating Phase 2 as done."
  exit 1
fi
