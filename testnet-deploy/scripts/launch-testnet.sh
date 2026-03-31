#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Launch a QRL testnet end-to-end.
#
# Usage:
#   ./scripts/launch-testnet.sh nodes.txt [validators] [delay]
#
# Environment:
#   EXECUTION_ADDRESS  — Prefunded address (default: Qaf84bc06703edfc371a0177ac8b482622d5ad242)
#   REUSE_KEYS         — Set to "true" to reuse existing validator keys
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INFRA_ROOT="$(dirname "$ROOT_DIR")"
GENESIS_DIR="${ROOT_DIR}/genesis-data"
BUILD_DIR="${ROOT_DIR}/build"
BOOTNODES_FILE="${ROOT_DIR}/bootnodes.txt"

NODES_FILE="${1:-}"
NUM_VALIDATORS="${2:-512}"
GENESIS_DELAY="${3:-600}"
EXECUTION_ADDRESS="${EXECUTION_ADDRESS:-Qaf84bc06703edfc371a0177ac8b482622d5ad242}"
REUSE_KEYS="${REUSE_KEYS:-false}"

if [ -z "$NODES_FILE" ] || [ ! -f "$NODES_FILE" ]; then
  echo "Usage: $0 nodes.txt [validators] [delay]"
  echo ""
  echo "  validators  Number of validators (default: 512)"
  echo "  delay       Genesis delay in seconds (default: 600)"
  echo ""
  echo "Environment variables:"
  echo "  EXECUTION_ADDRESS  Prefunded address"
  echo "  REUSE_KEYS=true    Reuse existing validator keys"
  exit 1
fi

NODES=()
while IFS= read -r line; do
  line=$(echo "$line" | xargs)
  [[ -z "$line" || "$line" == \#* ]] && continue
  NODES+=("$line")
done < "$NODES_FILE"

NUM_NODES=${#NODES[@]}

if [ "$NUM_NODES" -eq 0 ]; then
  echo "ERROR: No nodes found in ${NODES_FILE}"
  exit 1
fi

echo "==========================================="
echo "  QRL Testnet Launcher"
echo "==========================================="
echo ""
echo "  Nodes:             ${NUM_NODES}"
echo "  Validators:        ${NUM_VALIDATORS}"
echo "  Genesis delay:     ${GENESIS_DELAY}s"
echo "  Execution address: ${EXECUTION_ADDRESS}"
echo "  Reuse keys:        ${REUSE_KEYS}"
echo ""
for i in "${!NODES[@]}"; do
  echo "  Node ${i}: ${NODES[$i]}"
done
echo ""

# =======================================================
# Step 1: Build
# =======================================================
echo "==> Step 1: Building binaries..."
cd "${INFRA_ROOT}"
make build
cp -r build "${ROOT_DIR}/"
echo "    Done"

# =======================================================
# Step 2: Generate genesis
# =======================================================
echo ""
echo "==> Step 2: Generating genesis..."
cd "${INFRA_ROOT}"
GENESIS_FLAGS=""
if [ "$REUSE_KEYS" = "true" ]; then
  GENESIS_FLAGS="--reuse-keys"
fi
EXECUTION_ADDRESS="${EXECUTION_ADDRESS}" ./scripts/genesis.sh ${GENESIS_FLAGS} "${NUM_VALIDATORS}" "${NUM_NODES}" "${GENESIS_DELAY}" 2>&1 | tee "${ROOT_DIR}/genesis-output.log"

cp -r genesis-data "${ROOT_DIR}/"

# Extract and display the mnemonic
echo ""
echo "==========================================="
echo "  IMPORTANT: Save your mnemonic seed!"
echo "==========================================="
grep -A 2 -i "mnemonic" "${ROOT_DIR}/genesis-output.log" || echo "  (mnemonic not found in output — check genesis-output.log)"
echo "==========================================="
echo ""

# =======================================================
# Step 3: Deploy files to all nodes
# =======================================================
echo ""
echo "==> Step 3: Deploying to ${NUM_NODES} nodes..."
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  echo "    [$((i+1))/${NUM_NODES}] ${NODE}"

  ssh "$NODE" "id -u qrl &>/dev/null || sudo useradd -r -m -s /bin/false qrl; sudo mkdir -p /data/{execution,beacon,validator/wallet,logs}; sudo chown -R qrl:qrl /data"

  scp -q "${GENESIS_DIR}"/{jwt.hex,genesis.json,genesis.ssz,config.yml} "${NODE}:/tmp/"
  ssh "$NODE" "sudo mv /tmp/jwt.hex /tmp/genesis.json /tmp/genesis.ssz /tmp/config.yml /data/ && sudo chown qrl:qrl /data/{jwt.hex,genesis.json,genesis.ssz,config.yml}"

  scp -q "${BUILD_DIR}"/{gqrl,beacon-chain,validator} "${NODE}:/tmp/"
  ssh "$NODE" "sudo mv /tmp/gqrl /tmp/beacon-chain /tmp/validator /usr/local/bin/ && sudo chmod +x /usr/local/bin/{gqrl,beacon-chain,validator}"

  if [ -d "${GENESIS_DIR}/node-${i}" ]; then
    scp -q -r "${GENESIS_DIR}/node-${i}/keystores" "${NODE}:/tmp/keystores"
    scp -q "${GENESIS_DIR}/node-${i}/keystore-password.txt" "${NODE}:/tmp/keystore-password.txt"
    ssh "$NODE" "sudo rm -rf /data/validator/keystores; sudo mv /tmp/keystores /data/validator/keystores; sudo mv /tmp/keystore-password.txt /data/validator/keystore-password.txt; sudo chown -R qrl:qrl /data/validator"
  fi

  ssh "$NODE" "sudo -u qrl gqrl init --datadir /data/execution /data/genesis.json 2>/dev/null || true"
done
echo "    Done"

# =======================================================
# Step 4: Start gqrl on all nodes
# =======================================================
echo ""
echo "==> Step 4: Starting gqrl..."
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  IP=$(echo "$NODE" | cut -d@ -f2)

  ssh "$NODE" "sudo -u qrl bash -c 'nohup gqrl --datadir /data/execution --http --http.addr 0.0.0.0 --http.port 8545 --http.api qrl,net,web3 --authrpc.addr 0.0.0.0 --authrpc.port 8551 --authrpc.jwtsecret /data/jwt.hex --authrpc.vhosts=* --port 30303 --syncmode full --nat extip:${IP} --networkid 1337 > /data/logs/gqrl.log 2>&1 &'"

  echo "    Node ${i}: gqrl started"
done

echo "    Waiting for gqrl IPC..."
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  for attempt in $(seq 1 30); do
    if ssh "$NODE" "test -S /data/execution/gqrl.ipc" 2>/dev/null; then
      break
    fi
    sleep 2
  done
done

# =======================================================
# Step 5: Collect execution QNRs and peer nodes
# =======================================================
echo ""
echo "==> Step 5: Collecting execution QNRs and peering..."
EXEC_QNRS=()
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  QNR=""
  for attempt in $(seq 1 20); do
    QNR=$(ssh "$NODE" "sudo -u qrl gqrl attach --exec admin.nodeInfo.qnr /data/execution/gqrl.ipc 2>/dev/null" | tr -d '"' | grep -o 'qnr:[^ ]*' || true)
    if [ -n "$QNR" ]; then break; fi
    sleep 5
  done
  if [ -z "$QNR" ]; then
    echo "    ERROR: Could not get QNR from node ${i}"
    exit 1
  fi
  EXEC_QNRS+=("$QNR")
  echo "    Node ${i}: ${QNR:0:40}..."
done

for i in "${!NODES[@]}"; do
  for j in "${!NODES[@]}"; do
    if [ "$i" != "$j" ]; then
      ssh "${NODES[$i]}" "sudo -u qrl gqrl attach --exec 'admin.addPeer(\"${EXEC_QNRS[$j]}\")' /data/execution/gqrl.ipc 2>/dev/null" > /dev/null
    fi
  done
done
echo "    All nodes peered"

# =======================================================
# Step 6: Start beacon chain
# =======================================================
echo ""
echo "==> Step 6: Starting beacon chain..."

start_beacon() {
  local node="$1"
  local ip=$(echo "$node" | cut -d@ -f2)
  local bootstrap="${2:-}"
  local bootstrap_flag=""
  if [ -n "$bootstrap" ]; then
    bootstrap_flag="--bootstrap-node ${bootstrap}"
  fi

  ssh "$node" "sudo killall beacon-chain 2>/dev/null || true; sleep 2"
  ssh "$node" "sudo -u qrl bash -c 'nohup beacon-chain --datadir /data/beacon --execution-endpoint http://127.0.0.1:8551 --jwt-secret /data/jwt.hex --genesis-state /data/genesis.ssz --chain-config-file /data/config.yml --p2p-host-ip ${ip} --p2p-local-ip 0.0.0.0 --p2p-tcp-port 13000 --p2p-udp-port 12000 --rpc-host 0.0.0.0 --rpc-port 4000 --grpc-gateway-host 0.0.0.0 --grpc-gateway-port 3500 --min-sync-peers 1 --accept-terms-of-use --p2p-static-id ${bootstrap_flag} > /data/logs/beacon-chain.log 2>&1 &'"
}

get_beacon_qnr() {
  local node="$1"
  for attempt in $(seq 1 30); do
    local qnr=$(ssh "$node" "curl -sf http://127.0.0.1:3500/qrl/v1/node/identity 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"data\"][\"qnr\"])' 2>/dev/null" || true)
    if [ -n "$qnr" ]; then
      echo "$qnr"
      return 0
    fi
    sleep 5
  done
  return 1
}

# Start node 0 without bootstrap
start_beacon "${NODES[0]}"
echo "    Node 0: waiting for beacon API..."
QNR_0=$(get_beacon_qnr "${NODES[0]}")
if [ -z "$QNR_0" ]; then
  echo "    ERROR: Could not get beacon QNR from node 0"
  exit 1
fi
echo "    Node 0: ${QNR_0:0:40}..."
BEACON_QNRS=("$QNR_0")

# Start remaining nodes with node 0 as bootstrap
for i in $(seq 1 $((NUM_NODES - 1))); do
  start_beacon "${NODES[$i]}" "$QNR_0"
  echo "    Node ${i}: waiting for beacon API..."
  QNR=$(get_beacon_qnr "${NODES[$i]}")
  if [ -n "$QNR" ]; then
    echo "    Node ${i}: ${QNR:0:40}..."
    BEACON_QNRS+=("$QNR")
  else
    echo "    WARN: Could not get beacon QNR from node ${i}"
  fi
done

# Restart node 0 with all bootstrap QNRs
ALL_QNRS=$(IFS=,; echo "${BEACON_QNRS[*]:1}")
if [ -n "$ALL_QNRS" ]; then
  echo "    Restarting node 0 with all bootstrap QNRs..."
  start_beacon "${NODES[0]}" "$ALL_QNRS"
fi

# =======================================================
# Step 7: Start validators
# =======================================================
echo ""
echo "==> Step 7: Starting validators..."
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"

  ssh "$NODE" "sudo -u qrl validator accounts import --keys-dir /data/validator/keystores --wallet-dir /data/validator/wallet --wallet-password-file /data/validator/keystore-password.txt --account-password-file /data/validator/keystore-password.txt --accept-terms-of-use 2>/dev/null"

  ssh "$NODE" "sudo -u qrl bash -c 'nohup validator --datadir /data/validator --wallet-dir /data/validator/wallet --wallet-password-file /data/validator/keystore-password.txt --beacon-rpc-provider 127.0.0.1:4000 --chain-config-file /data/config.yml --accept-terms-of-use > /data/logs/validator.log 2>&1 &'"

  echo "    Node ${i}: validator started"
done

# =======================================================
# Save bootnodes
# =======================================================
echo ""
echo "==> Saving bootnodes..."
cat > "$BOOTNODES_FILE" <<EOF
# QRL Testnet Bootnodes
# Generated at $(date -u)
# Nodes: ${NUM_NODES}, Validators: ${NUM_VALIDATORS}

# Execution QNRs (for go-qrl params/bootnodes.go):
EOF
for qnr in "${EXEC_QNRS[@]}"; do
  echo "$qnr" >> "$BOOTNODES_FILE"
done

cat >> "$BOOTNODES_FILE" <<EOF

# Beacon QNRs (for qrysm --bootstrap-node):
EOF
for qnr in "${BEACON_QNRS[@]}"; do
  echo "$qnr" >> "$BOOTNODES_FILE"
done

# =======================================================
# Done
# =======================================================
echo ""
echo "==========================================="
echo "  Testnet launched!"
echo "==========================================="
echo ""
echo "  Nodes:         ${NUM_NODES}"
echo "  Validators:    ${NUM_VALIDATORS}"
echo "  Genesis time:  $(date -d "+${GENESIS_DELAY} seconds" 2>/dev/null || date -v+${GENESIS_DELAY}S)"
echo "  Bootnodes:     ${BOOTNODES_FILE}"
echo ""
echo "  Monitor:"
echo "    ssh ${NODES[0]} 'tail -f /data/logs/beacon-chain.log'"
echo "    ssh ${NODES[0]} 'tail -f /data/logs/gqrl.log'"
echo ""
echo "  Check status:"
echo "    ssh ${NODES[0]} 'curl -s http://127.0.0.1:3500/qrl/v1/beacon/headers/head | python3 -m json.tool'"
echo ""
echo "  Stop:"
echo "    ./scripts/stop-all.sh ${NODES_FILE}"
