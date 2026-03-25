#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# One-shot setup: build, genesis, infra, upload, deploy
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REUSE_KEYS="${REUSE_KEYS:-false}"
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --reuse-keys) REUSE_KEYS=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

NUM_VALIDATORS="${1:-128}"
NUM_NODES="${2:-2}"
GENESIS_DELAY="${3:-600}"
SSH_KEY_NAME="${SSH_KEY_NAME:-${TF_VAR_ssh_key_name:-}}"
export TF_VAR_ssh_key_name="${SSH_KEY_NAME}"

if [ -z "$SSH_KEY_NAME" ]; then
  echo "ERROR: SSH_KEY_NAME not set."
  echo "Usage: SSH_KEY_NAME=your-key ./scripts/setup.sh [validators] [nodes] [delay]"
  echo "   or: export TF_VAR_ssh_key_name=your-key"
  exit 1
fi

echo "==> Setup configuration:"
echo "    Validators: ${NUM_VALIDATORS}"
echo "    Nodes: ${NUM_NODES}"
echo "    Genesis delay: ${GENESIS_DELAY}s"
echo "    SSH key: ${SSH_KEY_NAME}"
echo "    Reuse keys: ${REUSE_KEYS}"
echo ""

# -------------------------------------------------------
# Step 1: Build binaries
# -------------------------------------------------------
echo "==> Step 1: Building binaries..."
cd "${ROOT_DIR}"
make build

# -------------------------------------------------------
# Step 2: Generate genesis
# -------------------------------------------------------
echo ""
echo "==> Step 2: Generating genesis..."
if [ "$REUSE_KEYS" = true ]; then
  "${SCRIPT_DIR}/genesis.sh" --reuse-keys "${NUM_VALIDATORS}" "${NUM_NODES}" "${GENESIS_DELAY}"
else
  "${SCRIPT_DIR}/genesis.sh" "${NUM_VALIDATORS}" "${NUM_NODES}" "${GENESIS_DELAY}"
fi

# -------------------------------------------------------
# Step 3: Create infrastructure
# -------------------------------------------------------
echo ""
echo "==> Step 3: Creating infrastructure..."
cd "${ROOT_DIR}/terraform"
terraform init -input=false
terraform apply -auto-approve \
  -var="ssh_key_name=${SSH_KEY_NAME}" \
  -var="node_count=${NUM_NODES}"

# -------------------------------------------------------
# Step 4: Upload binaries to S3
# -------------------------------------------------------
echo ""
echo "==> Step 4: Uploading binaries to S3..."
cd "${ROOT_DIR}"
"${SCRIPT_DIR}/build-and-upload.sh"

# -------------------------------------------------------
# Step 5: Deploy services
# -------------------------------------------------------
echo ""
echo "==> Step 5: Deploying services..."
cd "${ROOT_DIR}"
make deploy

echo ""
echo "==> Setup complete!"
echo "    Nodes: ${NUM_NODES}"
echo "    Validators: ${NUM_VALIDATORS}"
echo "    Tear down with: make destroy"
