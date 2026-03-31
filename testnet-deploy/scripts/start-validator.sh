#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Import validator keys and start validator on all nodes.
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
  echo "==> [$((i+1))/${#NODES[@]}] Starting validator on ${NODE}..."

  echo "    Importing keystores..."
  ssh "$NODE" "sudo -u qrl validator accounts import \
    --keys-dir /data/validator/keystores \
    --wallet-dir /data/validator/wallet \
    --wallet-password-file /data/validator/keystore-password.txt \
    --account-password-file /data/validator/keystore-password.txt \
    2>/dev/null"

  echo "    Starting validator..."
  ssh "$NODE" "sudo -u qrl bash -c 'nohup validator \
    --datadir /data/validator \
    --wallet-dir /data/validator/wallet \
    --wallet-password-file /data/validator/keystore-password.txt \
    --beacon-rpc-provider 127.0.0.1:4000 \
    --chain-config-file /data/config.yml \
    --accept-terms-of-use \
    > /data/logs/validator.log 2>&1 &'"

  echo "    Done: ${NODE}"
done

echo ""
echo "==> Validators started on ${#NODES[@]} nodes."
echo ""
echo "Monitor the chain:"
echo "  ssh <node> 'curl -s http://127.0.0.1:3500/qrl/v1/beacon/headers/head | python3 -m json.tool'"
