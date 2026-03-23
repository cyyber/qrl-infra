#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Stress test orchestration
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="${ROOT_DIR}/ansible"
EPOCHS="${1:-10}"          # Number of epochs to monitor
SLOT_TIME="${2:-60}"       # Seconds per slot
SLOTS_PER_EPOCH="${3:-128}"

EPOCH_DURATION=$((SLOT_TIME * SLOTS_PER_EPOCH))
TOTAL_DURATION=$((EPOCH_DURATION * EPOCHS))

# Get first beacon node IP from inventory
BEACON_IP=$(grep -A0 '\[beacon\]' "${ANSIBLE_DIR}/inventory/hosts.ini" | head -2 | tail -1 | awk '{print $1}')

echo "==> Stress test configuration:"
echo "    Epochs: ${EPOCHS}"
echo "    Slot time: ${SLOT_TIME}s"
echo "    Slots/epoch: ${SLOTS_PER_EPOCH}"
echo "    Total duration: $((TOTAL_DURATION / 60)) minutes"
echo "    Beacon API: http://${BEACON_IP}:3500"

# Wait for chain to start producing blocks
echo "==> Waiting for chain to start..."
until curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/head" > /dev/null 2>&1; do
  echo "    Chain not ready, waiting..."
  sleep 10
done
echo "==> Chain is live"

# Wait for finalization
echo "==> Waiting for first finalization..."
until curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/finalized" > /dev/null 2>&1; do
  echo "    Not finalized yet, waiting..."
  sleep 30
done
echo "==> Chain is finalizing"

# Start spammers
echo "==> Starting transaction spammers..."
cd "${ANSIBLE_DIR}" && ansible-playbook playbooks/deploy.yml --tags spammer -l spammer

# Monitor for N epochs
echo "==> Monitoring for ${EPOCHS} epochs (${TOTAL_DURATION}s)..."
START_TIME=$(date +%s)
EPOCH=0

while [ $EPOCH -lt $EPOCHS ]; do
  HEADER=$(curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/head" | jq -r '.data.header.message')
  SLOT=$(echo "$HEADER" | jq -r '.slot')
  FINALIZED=$(curl -sf "http://${BEACON_IP}:3500/qrl/v1/beacon/headers/finalized" | jq -r '.data.header.message.slot')

  echo "    [$(date +%H:%M:%S)] Slot: ${SLOT} | Finalized: ${FINALIZED} | Epoch: $((SLOT / SLOTS_PER_EPOCH))"
  sleep "${SLOT_TIME}"
  EPOCH=$(( ($(date +%s) - START_TIME) / EPOCH_DURATION ))
done

# Collect results
echo "==> Collecting logs and metrics..."
cd "${ANSIBLE_DIR}" && ansible-playbook playbooks/collect.yml

echo "==> Stress test complete. Results in ${ROOT_DIR}/collected/"