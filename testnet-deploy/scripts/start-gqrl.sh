#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Start gqrl on all nodes.
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

for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  IP=$(echo "$NODE" | cut -d@ -f2)

  echo "==> Starting gqrl on ${NODE} (extip: ${IP})..."
  ssh "$NODE" "sudo -u qrl bash -c 'nohup gqrl --datadir /data/execution --http --http.addr 0.0.0.0 --http.port 8545 --http.api qrl,net,web3 --authrpc.addr 0.0.0.0 --authrpc.port 8551 --authrpc.jwtsecret /data/jwt.hex --authrpc.vhosts=* --port 30303 --syncmode full --nat extip:${IP} --networkid 1337 > /data/logs/gqrl.log 2>&1 &'"

  echo "    Started gqrl on ${NODE}"
done

echo ""
echo "==> gqrl started on ${#NODES[@]} nodes. Wait a few seconds then run:"
echo "    ./scripts/collect-bootnodes.sh ${NODES_FILE}"
