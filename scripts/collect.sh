#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Collect logs, metrics, and chain state from all nodes
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${ROOT_DIR}/collected/${TIMESTAMP}"

mkdir -p "${OUTPUT_DIR}"

echo "==> Collecting data to ${OUTPUT_DIR}/"

# Run Ansible collection playbook
cd "${ANSIBLE_DIR}" && ansible-playbook playbooks/collect.yml

# Move collected data to timestamped directory
if [ -d "${ROOT_DIR}/collected" ]; then
  find "${ROOT_DIR}/collected" -maxdepth 1 -mindepth 1 -not -name "${TIMESTAMP}" -exec mv {} "${OUTPUT_DIR}/" \; 2>/dev/null || true
fi

# Get beacon API snapshot if available
BEACON_IP=$(grep -A1 '\[node\]' "${ANSIBLE_DIR}/inventory/hosts.ini" | tail -1 | awk '{print $1}')

if curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/head" > /dev/null 2>&1; then
  echo "==> Capturing chain state snapshot..."
  curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/head" | jq . > "${OUTPUT_DIR}/head.json"
  curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/finalized" | jq . > "${OUTPUT_DIR}/finalized.json"
  curl -sf "http://${BEACON_IP}:3500/qrl/v1/node/peers" | jq . > "${OUTPUT_DIR}/peers.json"
  curl -sf "http://${BEACON_IP}:3500/qrl/v1/node/syncing" | jq . > "${OUTPUT_DIR}/syncing.json"
fi

# Create summary
echo "==> Generating summary..."
cat > "${OUTPUT_DIR}/summary.txt" <<SUMMARY
QRL Infrastructure Data Collection
Date: $(date)
Directory: ${OUTPUT_DIR}

Node counts:
  Nodes (exec+beacon+validator): $(grep -c '^\[node\]' "${ANSIBLE_DIR}/inventory/hosts.ini" >/dev/null && grep -A999 '^\[node\]' "${ANSIBLE_DIR}/inventory/hosts.ini" | tail -n+2 | grep -c '^[0-9]' || echo 0)
  Spammer:   $(grep -A999 '^\[spammer\]' "${ANSIBLE_DIR}/inventory/hosts.ini" | tail -n+2 | grep -c '^[0-9]' || echo 0)
SUMMARY

echo "==> Collection complete: ${OUTPUT_DIR}/"