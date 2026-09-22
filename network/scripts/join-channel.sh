#!/usr/bin/env bash
# Phase 2, step 5: join the orderer and all 3 peers to "healthchannel".
#
# The genesis block (Step 3) only exists on disk so far — nothing has used
# it yet. This script is what actually makes it the starting point of a
# real, running channel: first the orderer is told "start serving this
# channel," then each peer is told "download that channel's blocks and
# start tracking its world state."

set -euo pipefail
cd "$(dirname "$0")/.."   # always run from network/

FABRIC_BIN="$(cd ../fabric-samples/bin && pwd)"
export PATH="${FABRIC_BIN}:${PATH}"

CHANNEL_NAME=healthchannel
BLOCKFILE="${PWD}/channel-artifacts/${CHANNEL_NAME}.block"

echo "== Joining the orderer to ${CHANNEL_NAME} =="
# osnadmin talks to the orderer's admin API (port 7053), authenticating with
# mTLS. The client cert here is the orderer node's own TLS cert — the admin
# API is configured (ORDERER_ADMIN_TLS_CLIENTROOTCAS) to trust anything
# signed by the orderer org's CA, which this cert is.
ORDERER_CA="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/tlsca/tlsca.orderer.healthcare.com-cert.pem"
ORDERER_ADMIN_TLS_CERT="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/orderers/orderer1.orderer.healthcare.com/tls/server.crt"
ORDERER_ADMIN_TLS_KEY="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/orderers/orderer1.orderer.healthcare.com/tls/server.key"

osnadmin channel join \
  --channelID "${CHANNEL_NAME}" \
  --config-block "${BLOCKFILE}" \
  -o localhost:7053 \
  --ca-file "${ORDERER_CA}" \
  --client-cert "${ORDERER_ADMIN_TLS_CERT}" \
  --client-key "${ORDERER_ADMIN_TLS_KEY}"

echo
echo "== Joining peer0 for each org =="

# $1 = org short name  $2 = domain  $3 = MSP ID  $4 = peer's host:port on localhost
join_peer() {
  local short="$1" domain="$2" msp_id="$3" address="$4"
  echo "-- ${domain} --"
  export FABRIC_CFG_PATH="${PWD}/config/peercfg"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_LOCALMSPID="${msp_id}"
  export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/organizations/peerOrganizations/${domain}/tlsca/tlsca.${domain}-cert.pem"
  export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/${domain}/users/Admin@${domain}/msp"
  export CORE_PEER_ADDRESS="${address}"
  peer channel join -b "${BLOCKFILE}"
}

join_peer hospitala hospitala.healthcare.com HospitalAMSP localhost:7051
join_peer hospitalb hospitalb.healthcare.com HospitalBMSP localhost:8051
join_peer lab lab.healthcare.com LabMSP localhost:9051

echo
echo "Done. All 3 peers and the orderer are now on '${CHANNEL_NAME}'."
