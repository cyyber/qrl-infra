#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Deploy testnet genesis files, binaries, and keystores
# to a list of nodes, then start services.
#
# Usage:
#   ./scripts/deploy.sh nodes.txt
#
# nodes.txt format (one per line):
#   ubuntu@54.123.45.67
#   ubuntu@18.234.56.78
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
GENESIS_DIR="${ROOT_DIR}/genesis-data"
BUILD_DIR="${ROOT_DIR}/build"
NODES_FILE="${1:-}"

if [ -z "$NODES_FILE" ] || [ ! -f "$NODES_FILE" ]; then
  echo "Usage: $0 nodes.txt"
  exit 1
fi

NODES=()
while IFS= read -r line; do
  line=$(echo "$line" | xargs)
  [[ -z "$line" || "$line" == \#* ]] && continue
  NODES+=("$line")
done < "$NODES_FILE"

if [ ${#NODES[@]} -eq 0 ]; then
  echo "ERROR: No nodes found in ${NODES_FILE}"
  exit 1
fi

echo "==> Deploying to ${#NODES[@]} nodes"

# Verify local files
for f in jwt.hex genesis.json genesis.ssz config.yml; do
  if [ ! -f "${GENESIS_DIR}/$f" ]; then
    echo "ERROR: ${GENESIS_DIR}/$f not found. Run ./scripts/genesis.sh first."
    exit 1
  fi
done

for f in gqrl beacon-chain validator; do
  if [ ! -f "${BUILD_DIR}/$f" ]; then
    echo "ERROR: ${BUILD_DIR}/$f not found. Run make build first."
    exit 1
  fi
done

for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  echo ""
  echo "==> [$((i+1))/${#NODES[@]}] ${NODE}"

  echo "    Creating directories and qrl user..."
  ssh "$NODE" "id -u qrl &>/dev/null || sudo useradd -r -s /bin/false qrl; sudo mkdir -p /data/{execution,beacon,validator/wallet,logs}; sudo chown -R qrl:qrl /data"

  echo "    Copying genesis files..."
  scp -q "${GENESIS_DIR}"/{jwt.hex,genesis.json,genesis.ssz,config.yml} "${NODE}:/tmp/"
  ssh "$NODE" "sudo mv /tmp/jwt.hex /tmp/genesis.json /tmp/genesis.ssz /tmp/config.yml /data/ && sudo chown qrl:qrl /data/{jwt.hex,genesis.json,genesis.ssz,config.yml}"

  echo "    Copying binaries..."
  scp -q "${BUILD_DIR}"/{gqrl,beacon-chain,validator} "${NODE}:/tmp/"
  ssh "$NODE" "sudo mv /tmp/gqrl /tmp/beacon-chain /tmp/validator /usr/local/bin/ && sudo chmod +x /usr/local/bin/{gqrl,beacon-chain,validator}"

  if [ -d "${GENESIS_DIR}/node-${i}" ]; then
    echo "    Copying keystores (node ${i})..."
    scp -q -r "${GENESIS_DIR}/node-${i}/keystores" "${NODE}:/tmp/keystores"
    scp -q "${GENESIS_DIR}/node-${i}/keystore-password.txt" "${NODE}:/tmp/keystore-password.txt"
    ssh "$NODE" "sudo rm -rf /data/validator/keystores; sudo mv /tmp/keystores /data/validator/keystores; sudo mv /tmp/keystore-password.txt /data/validator/keystore-password.txt; sudo chown -R qrl:qrl /data/validator"
  else
    echo "    WARN: No keystores for node ${i}"
  fi

  echo "    Initializing gqrl..."
  ssh "$NODE" "sudo -u qrl gqrl init --datadir /data/execution /data/genesis.json 2>/dev/null || true"

  echo "    Done: ${NODE}"
done

echo ""
echo "==> All ${#NODES[@]} nodes deployed."
echo ""
echo "Next steps:"
echo "  1. Start gqrl on all nodes        — ./scripts/start-gqrl.sh nodes.txt"
echo "  2. Collect and share bootnodes     — ./scripts/collect-bootnodes.sh nodes.txt"
echo "  3. Start beacon on all nodes       — ./scripts/start-beacon.sh nodes.txt"
echo "  4. Import keys and start validator — ./scripts/start-validator.sh nodes.txt"
