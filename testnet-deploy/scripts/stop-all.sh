#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Stop all services on all nodes.
# -------------------------------------------------------

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

for NODE in "${NODES[@]}"; do
  echo "==> Stopping services on ${NODE}..."
  ssh "$NODE" "sudo killall validator beacon-chain gqrl 2>/dev/null; sleep 3; sudo killall -9 validator beacon-chain gqrl 2>/dev/null" || true
  echo "    Done"
done

echo ""
echo "==> All services stopped on ${#NODES[@]} nodes."
