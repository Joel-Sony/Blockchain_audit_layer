#!/usr/bin/env bash
# Phase 2, step 6: deploy "proofoflife" as chaincode-as-a-service (CCaaS).
#
# Unlike classic Fabric chaincode, the peer does NOT build or run this
# chaincode's container itself (see docs/decisions.md ADR-004 for why).
# Instead:
#   - we already built `proofoflife_ccaas_image:latest` ourselves
#   - for each org, we package a small "pointer" (connection.json: just an
#     address + whether TLS is required) instead of source code
#   - install/approve/commit works exactly like classic chaincode lifecycle
#   - then we start one chaincode container per org, each its own instance,
#     so each org runs its own copy of the code it approved

set -euo pipefail
cd "$(dirname "$0")/.."   # always run from network/

FABRIC_BIN="$(cd ../fabric-samples/bin && pwd)"
export PATH="${FABRIC_BIN}:${PATH}"
export FABRIC_CFG_PATH="${PWD}/config/peercfg"
export CORE_PEER_TLS_ENABLED=true

CHANNEL_NAME=healthchannel
CC_NAME=proofoflife
CC_VERSION=1.0
CC_SEQUENCE=1
CCAAS_PORT=9999
ORDERER_CA="${PWD}/organizations/ordererOrganizations/orderer.healthcare.com/tlsca/tlsca.orderer.healthcare.com-cert.pem"

set_peer_env() {
  local domain="$1" msp_id="$2" address="$3"
  export CORE_PEER_LOCALMSPID="${msp_id}"
  export CORE_PEER_TLS_ROOTCERT_FILE="${PWD}/organizations/peerOrganizations/${domain}/tlsca/tlsca.${domain}-cert.pem"
  export CORE_PEER_MSPCONFIGPATH="${PWD}/organizations/peerOrganizations/${domain}/users/Admin@${domain}/msp"
  export CORE_PEER_ADDRESS="${address}"
}

# $1 org short name  $2 domain  $3 MSP ID  $4 peer localhost address
package_and_install() {
  local short="$1" domain="$2" msp_id="$3" peer_address="$4"
  local container_name="${CC_NAME}-${short}"
  local pkg_dir="channel-artifacts/ccaas-pkg-${short}"
  local pkg_file="channel-artifacts/${CC_NAME}-${short}.tar.gz"

  echo "-- ${domain}: packaging (points at ${container_name}:${CCAAS_PORT}) --"
  rm -rf "${pkg_dir}"
  mkdir -p "${pkg_dir}/src" "${pkg_dir}/pkg"
  cat > "${pkg_dir}/src/connection.json" <<EOF
{
  "address": "${container_name}:${CCAAS_PORT}",
  "dial_timeout": "10s",
  "tls_required": false
}
EOF
  cat > "${pkg_dir}/pkg/metadata.json" <<EOF
{
  "type": "ccaas",
  "label": "${CC_NAME}_${CC_VERSION}_${short}"
}
EOF
  tar -C "${pkg_dir}/src" -czf "${pkg_dir}/pkg/code.tar.gz" .
  tar -C "${pkg_dir}/pkg" -czf "${pkg_file}" metadata.json code.tar.gz

  set_peer_env "${domain}" "${msp_id}" "${peer_address}"
  peer lifecycle chaincode install "${pkg_file}"
}

echo "== Packaging + installing on all 3 peers =="
package_and_install hospitala hospitala.healthcare.com HospitalAMSP localhost:7051
package_and_install hospitalb hospitalb.healthcare.com HospitalBMSP localhost:8051
package_and_install lab lab.healthcare.com LabMSP localhost:9051

echo
echo "== Starting the 3 chaincode containers (one per org) =="
for short in hospitala hospitalb lab; do
  container_name="${CC_NAME}-${short}"
  pkg_file="channel-artifacts/${CC_NAME}-${short}.tar.gz"
  package_id=$(peer lifecycle chaincode calculatepackageid "${pkg_file}")
  echo "-- ${container_name}: package ID ${package_id} --"
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  docker run -d --name "${container_name}" \
    --network healthcare-fabric-net \
    -e CHAINCODE_SERVER_ADDRESS="0.0.0.0:${CCAAS_PORT}" \
    -e CHAINCODE_ID="${package_id}" \
    proofoflife_ccaas_image:latest
done

echo
echo "== Approving for all 3 orgs =="
approve() {
  local domain="$1" msp_id="$2" peer_address="$3" short="$4"
  local package_id
  package_id=$(peer lifecycle chaincode calculatepackageid "channel-artifacts/${CC_NAME}-${short}.tar.gz")
  set_peer_env "${domain}" "${msp_id}" "${peer_address}"
  peer lifecycle chaincode approveformyorg \
    -o localhost:7050 --tls --cafile "${ORDERER_CA}" \
    --channelID "${CHANNEL_NAME}" --name "${CC_NAME}" --version "${CC_VERSION}" \
    --package-id "${package_id}" --sequence "${CC_SEQUENCE}"
}
approve hospitala.healthcare.com HospitalAMSP localhost:7051 hospitala
approve hospitalb.healthcare.com HospitalBMSP localhost:8051 hospitalb
approve lab.healthcare.com LabMSP localhost:9051 lab

echo
echo "== Checking commit readiness =="
peer lifecycle chaincode checkcommitreadiness \
  -o localhost:7050 --tls --cafile "${ORDERER_CA}" \
  --channelID "${CHANNEL_NAME}" --name "${CC_NAME}" --version "${CC_VERSION}" \
  --sequence "${CC_SEQUENCE}" --output json

echo
echo "== Committing chaincode definition to the channel =="
peer lifecycle chaincode commit \
  -o localhost:7050 --tls --cafile "${ORDERER_CA}" \
  --channelID "${CHANNEL_NAME}" --name "${CC_NAME}" --version "${CC_VERSION}" --sequence "${CC_SEQUENCE}" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${PWD}/organizations/peerOrganizations/hospitala.healthcare.com/tlsca/tlsca.hospitala.healthcare.com-cert.pem" \
  --peerAddresses localhost:8051 --tlsRootCertFiles "${PWD}/organizations/peerOrganizations/hospitalb.healthcare.com/tlsca/tlsca.hospitalb.healthcare.com-cert.pem" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "${PWD}/organizations/peerOrganizations/lab.healthcare.com/tlsca/tlsca.lab.healthcare.com-cert.pem"

echo
echo "Done. '${CC_NAME}' is committed on '${CHANNEL_NAME}' and running as 3 CCaaS containers."
