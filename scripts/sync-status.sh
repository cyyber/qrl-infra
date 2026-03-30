#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Query the sync collector on the monitoring node
# for aggregated block status across all nodes.
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory/hosts.ini"

if [ ! -f "$INVENTORY" ]; then
  echo "ERROR: Inventory not found at ${INVENTORY}"
  exit 1
fi

MONITORING_IP=$(sed -n '/^\[monitoring\]/,/^\[/p' "$INVENTORY" | grep '^[0-9]' | awk '{print $1}')

if [ -z "$MONITORING_IP" ]; then
  echo "ERROR: Could not find monitoring node IP in inventory"
  exit 1
fi

COLLECTOR_URL="http://${MONITORING_IP}:9100/status"

echo "==> Querying sync collector at ${COLLECTOR_URL}"
echo ""

RESPONSE=$(curl -sf --max-time 10 "$COLLECTOR_URL") || {
  echo "ERROR: Could not reach sync collector at ${COLLECTOR_URL}"
  exit 1
}

# Pretty print the aggregated status
echo "$RESPONSE" | jq -r '
  "===========================================",
  "  BLOCK STATUS",
  "===========================================",
  "",
  (.blocks[] |
    "  Block \(.block_number) (\(.block_hash[:10])...\(.block_hash[-8:])): \(.node_count) nodes",
    "    First seen: \(.first_seen) by \(.first_seen_by)",
    "    Last seen:  \(.last_seen) by \(.last_seen_by)",
    "    Propagation: \(.propagation_secs)s",
    ""
  ),
  "",
  "===========================================",
  "  SUMMARY",
  "===========================================",
  "",
  "  Reporting:    \(.total_reporting)",
  "  Stale:        \(.total_stale)",
  "  Unique blocks: \(.blocks | length)",
  "",
  (if .blocks | length <= 1 and .total_stale == 0 and .total_reporting > 0 then
    "  Status: ALL NODES IN SYNC"
  elif .total_stale > 0 then
    "  Status: \(.total_stale) NODES STALE (no report in 30s)"
  else
    ""
  end)
'