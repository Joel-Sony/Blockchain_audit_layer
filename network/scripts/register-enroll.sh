#!/usr/bin/env bash
# Phase 2, step 2: register + enroll identities against each org's CA.
#
# For each org this creates, under organizations/:
#   - the org admin's MSP (org-level identity, used to manage the org itself)
#   - peer0's MSP + TLS material (the peer's identity when it talks to others)
#   - (orderer org only) the orderer node's MSP + TLS material
#
# Must be run from the network/ directory. Requires the 4 CA containers
# (docker-compose-ca.yaml) already running.

set -euo pipefail
cd "$(dirname "$0")/.."   # always run from network/

FABRIC_BIN="$(cd ../fabric-samples/bin && pwd)"
export PATH="${FABRIC_BIN}:${PATH}"

# Node OU config: tells Fabric to read an identity's role (client/peer/admin/
# orderer) from the Organizational Unit field of its certificate, instead of
# needing separate admincerts lists. This is the modern, CA-based approach.
node_ous_config() {
  local ca_port="$1" ca_name="$2"
  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-${ca_port}-${ca_name}.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-${ca_port}-${ca_name}.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-${ca_port}-${ca_name}.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-${ca_port}-${ca_name}.pem
    OrganizationalUnitIdentifier: orderer"
}

# $1 org short name (hospitala/hospitalb/lab)  $2 domain (hospitala.healthcare.com)  $3 ca port  $4 ca name
create_peer_org() {
  local short="$1" domain="$2" port="$3" ca_name="$4"
  local org_dir="organizations/peerOrganizations/${domain}"
  local ca_cert="organizations/fabric-ca/${short}/ca-cert.pem"

  echo "== ${domain}: enrolling CA bootstrap admin =="
  mkdir -p "${org_dir}"
  export FABRIC_CA_CLIENT_HOME="${PWD}/${org_dir}"
  fabric-ca-client enroll -u "https://admin:adminpw@localhost:${port}" \
    --caname "${ca_name}" --tls.certfiles "${PWD}/${ca_cert}"

  node_ous_config "${port}" "${ca_name}" > "${org_dir}/msp/config.yaml"

  mkdir -p "${org_dir}/msp/tlscacerts" "${org_dir}/tlsca" "${org_dir}/ca"
  cp "${ca_cert}" "${org_dir}/msp/tlscacerts/ca.crt"
  cp "${ca_cert}" "${org_dir}/tlsca/tlsca.${domain}-cert.pem"
  cp "${ca_cert}" "${org_dir}/ca/ca.${domain}-cert.pem"

  echo "== ${domain}: registering peer0 and org admin =="
  fabric-ca-client register --caname "${ca_name}" --id.name peer0 --id.secret peer0pw --id.type peer --tls.certfiles "${PWD}/${ca_cert}"
  fabric-ca-client register --caname "${ca_name}" --id.name "${short}admin" --id.secret "${short}adminpw" --id.type admin --tls.certfiles "${PWD}/${ca_cert}"

  echo "== ${domain}: enrolling peer0 MSP =="
  fabric-ca-client enroll -u "https://peer0:peer0pw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/peers/peer0.${domain}/msp" --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/msp/config.yaml" "${org_dir}/peers/peer0.${domain}/msp/config.yaml"

  echo "== ${domain}: enrolling peer0 TLS cert =="
  fabric-ca-client enroll -u "https://peer0:peer0pw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/peers/peer0.${domain}/tls" --enrollment.profile tls \
    --csr.hosts "peer0.${domain}" --csr.hosts localhost --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/peers/peer0.${domain}/tls/tlscacerts/"* "${org_dir}/peers/peer0.${domain}/tls/ca.crt"
  cp "${org_dir}/peers/peer0.${domain}/tls/signcerts/"* "${org_dir}/peers/peer0.${domain}/tls/server.crt"
  cp "${org_dir}/peers/peer0.${domain}/tls/keystore/"* "${org_dir}/peers/peer0.${domain}/tls/server.key"

  echo "== ${domain}: enrolling org admin MSP =="
  fabric-ca-client enroll -u "https://${short}admin:${short}adminpw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/users/Admin@${domain}/msp" --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/msp/config.yaml" "${org_dir}/users/Admin@${domain}/msp/config.yaml"
}

create_orderer_org() {
  local domain="orderer.healthcare.com"
  local port=10054
  local ca_name="ca-orderer"
  local org_dir="organizations/ordererOrganizations/${domain}"
  local ca_cert="organizations/fabric-ca/ordererOrg/ca-cert.pem"

  echo "== ${domain}: enrolling CA bootstrap admin =="
  mkdir -p "${org_dir}"
  export FABRIC_CA_CLIENT_HOME="${PWD}/${org_dir}"
  fabric-ca-client enroll -u "https://admin:adminpw@localhost:${port}" \
    --caname "${ca_name}" --tls.certfiles "${PWD}/${ca_cert}"

  node_ous_config "${port}" "${ca_name}" > "${org_dir}/msp/config.yaml"

  mkdir -p "${org_dir}/msp/tlscacerts" "${org_dir}/tlsca"
  cp "${ca_cert}" "${org_dir}/msp/tlscacerts/tlsca.${domain}-cert.pem"
  cp "${ca_cert}" "${org_dir}/tlsca/tlsca.${domain}-cert.pem"

  echo "== ${domain}: registering orderer1 and orderer org admin =="
  fabric-ca-client register --caname "${ca_name}" --id.name orderer1 --id.secret orderer1pw --id.type orderer --tls.certfiles "${PWD}/${ca_cert}"
  fabric-ca-client register --caname "${ca_name}" --id.name ordererAdmin --id.secret ordererAdminpw --id.type admin --tls.certfiles "${PWD}/${ca_cert}"

  echo "== ${domain}: enrolling orderer1 MSP =="
  fabric-ca-client enroll -u "https://orderer1:orderer1pw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/orderers/orderer1.${domain}/msp" --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/msp/config.yaml" "${org_dir}/orderers/orderer1.${domain}/msp/config.yaml"
  mv "${org_dir}/orderers/orderer1.${domain}/msp/signcerts/cert.pem" \
     "${org_dir}/orderers/orderer1.${domain}/msp/signcerts/orderer1.${domain}-cert.pem"

  echo "== ${domain}: enrolling orderer1 TLS cert =="
  fabric-ca-client enroll -u "https://orderer1:orderer1pw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/orderers/orderer1.${domain}/tls" --enrollment.profile tls \
    --csr.hosts "orderer1.${domain}" --csr.hosts localhost --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/orderers/orderer1.${domain}/tls/tlscacerts/"* "${org_dir}/orderers/orderer1.${domain}/tls/ca.crt"
  cp "${org_dir}/orderers/orderer1.${domain}/tls/signcerts/"* "${org_dir}/orderers/orderer1.${domain}/tls/server.crt"
  cp "${org_dir}/orderers/orderer1.${domain}/tls/keystore/"* "${org_dir}/orderers/orderer1.${domain}/tls/server.key"
  mkdir -p "${org_dir}/orderers/orderer1.${domain}/msp/tlscacerts"
  cp "${org_dir}/orderers/orderer1.${domain}/tls/tlscacerts/"* "${org_dir}/orderers/orderer1.${domain}/msp/tlscacerts/tlsca.${domain}-cert.pem"

  echo "== ${domain}: enrolling orderer org admin MSP =="
  fabric-ca-client enroll -u "https://ordererAdmin:ordererAdminpw@localhost:${port}" --caname "${ca_name}" \
    -M "${PWD}/${org_dir}/users/Admin@${domain}/msp" --tls.certfiles "${PWD}/${ca_cert}"
  cp "${org_dir}/msp/config.yaml" "${org_dir}/users/Admin@${domain}/msp/config.yaml"
}

create_peer_org hospitala hospitala.healthcare.com 7054 ca-hospitala
create_peer_org hospitalb hospitalb.healthcare.com 8054 ca-hospitalb
create_peer_org lab lab.healthcare.com 9054 ca-lab
create_orderer_org

echo
echo "Done. MSP folders created under organizations/peerOrganizations/ and organizations/ordererOrganizations/"
