#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Collect execution QNRs from all nodes, add them as peers,
# then output the bootnode list for embedding.
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

echo "==> Collecting execution QNRs..."
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

echo ""
echo "==> Adding execution peers..."
for i in "${!NODES[@]}"; do
  for j in "${!NODES[@]}"; do
    if [ "$i" != "$j" ]; then
      ssh "${NODES[$i]}" "sudo -u qrl gqrl attach --exec 'admin.addPeer(\"${EXEC_QNRS[$j]}\")' /data/execution/gqrl.ipc 2>/dev/null" > /dev/null
    fi
  done
  echo "    Node ${i}: peered"
done

# Save for embedding
echo "# Execution bootnodes" > "$BOOTNODES_FILE"
echo "# Generated at $(date -u)" >> "$BOOTNODES_FILE"
echo "" >> "$BOOTNODES_FILE"
echo "# Execution QNRs (for go-qrl --bootnodes):" >> "$BOOTNODES_FILE"
for i in "${!EXEC_QNRS[@]}"; do
  echo "${EXEC_QNRS[$i]}" >> "$BOOTNODES_FILE"
done

echo ""
echo "==> Execution QNRs saved to ${BOOTNODES_FILE}"
echo ""
echo "Next: start beacon on all nodes:"
echo "    ./scripts/start-beacon.sh ${NODES_FILE}"
