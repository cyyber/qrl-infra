#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Stop all services and clean chain data on all nodes.
# Binaries and genesis files are preserved.
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
  echo "==> Cleaning ${NODE}..."
  ssh "$NODE" "sudo killall validator beacon-chain gqrl 2>/dev/null; sleep 3; sudo killall -9 validator beacon-chain gqrl 2>/dev/null; sleep 1; sudo rm -rf /data/execution /data/beacon /data/validator/wallet /data/validator/validator.db /data/logs/*" || true
  echo "    Done"
done

echo ""
echo "==> Cleaned ${#NODES[@]} nodes. Ready to redeploy."
