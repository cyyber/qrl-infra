#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Start beacon-chain on all nodes.
# First node starts without bootstrap, collects its QNR,
# then remaining nodes start with bootstrap.
# Finally restarts first node with all QNRs.
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
NODES_FILE="${1:-}"
BOOTNODES_FILE="${ROOT_DIR}/bootnodes.txt"

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

start_beacon() {
  local node="$1"
  local ip=$(echo "$node" | cut -d@ -f2)
  local bootstrap="${2:-}"
  local bootstrap_flag=""

  if [ -n "$bootstrap" ]; then
    bootstrap_flag="--bootstrap-node ${bootstrap}"
  fi

  ssh "$node" "sudo pkill -f 'beacon-chain --datadir' 2>/dev/null || true; sleep 2"
  ssh "$node" "sudo -u qrl bash -c 'nohup beacon-chain \
    --datadir /data/beacon \
    --execution-endpoint http://127.0.0.1:8551 \
    --jwt-secret /data/jwt.hex \
    --genesis-state /data/genesis.ssz \
    --chain-config-file /data/config.yml \
    --p2p-host-ip ${ip} \
    --p2p-tcp-port 13000 \
    --p2p-udp-port 12000 \
    --rpc-host 0.0.0.0 --rpc-port 4000 \
    --grpc-gateway-host 0.0.0.0 --grpc-gateway-port 3500 \
    --min-sync-peers 1 \
    --accept-terms-of-use \
    --p2p-static-id \
    ${bootstrap_flag} \
    > /data/logs/beacon-chain.log 2>&1 &'"
}

get_beacon_qnr() {
  local node="$1"
  local ip=$(echo "$node" | cut -d@ -f2)
  local qnr=""
  for attempt in $(seq 1 30); do
    qnr=$(ssh "$node" "curl -sf http://127.0.0.1:3500/qrl/v1/node/identity 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"data\"][\"qnr\"])' 2>/dev/null" || true)
    if [ -n "$qnr" ]; then
      echo "$qnr"
      return 0
    fi
    sleep 5
  done
  echo ""
  return 1
}

# Step 1: Start first node without bootstrap
echo "==> Starting beacon on node 0 (no bootstrap)..."
start_beacon "${NODES[0]}"

echo "    Waiting for beacon API..."
QNR_0=$(get_beacon_qnr "${NODES[0]}")
if [ -z "$QNR_0" ]; then
  echo "ERROR: Could not get QNR from node 0"
  exit 1
fi
echo "    Node 0 QNR: ${QNR_0:0:40}..."

BEACON_QNRS=("$QNR_0")

# Step 2: Start remaining nodes with node 0 as bootstrap
for i in $(seq 1 $((${#NODES[@]} - 1))); do
  echo ""
  echo "==> Starting beacon on node ${i} (bootstrap: node 0)..."
  start_beacon "${NODES[$i]}" "$QNR_0"

  echo "    Waiting for beacon API..."
  QNR=$(get_beacon_qnr "${NODES[$i]}")
  if [ -z "$QNR" ]; then
    echo "WARN: Could not get QNR from node ${i}"
  else
    echo "    Node ${i} QNR: ${QNR:0:40}..."
    BEACON_QNRS+=("$QNR")
  fi
done

# Step 3: Restart node 0 with all QNRs
ALL_QNRS=$(IFS=,; echo "${BEACON_QNRS[*]:1}")
if [ -n "$ALL_QNRS" ]; then
  echo ""
  echo "==> Restarting node 0 with all bootstrap QNRs..."
  start_beacon "${NODES[0]}" "$ALL_QNRS"
  echo "    Done"
fi

# Save beacon QNRs to bootnodes file
echo "" >> "$BOOTNODES_FILE"
echo "# Beacon QNRs (for qrysm --bootstrap-node):" >> "$BOOTNODES_FILE"
for i in "${!BEACON_QNRS[@]}"; do
  echo "${BEACON_QNRS[$i]}" >> "$BOOTNODES_FILE"
done

echo ""
echo "==> Beacon started on ${#NODES[@]} nodes."
echo "==> Beacon QNRs appended to ${BOOTNODES_FILE}"
echo ""
echo "Next: import keys and start validators:"
echo "    ./scripts/start-validator.sh ${NODES_FILE}"
