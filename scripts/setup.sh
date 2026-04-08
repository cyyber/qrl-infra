#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# One-shot setup: build, genesis, infra, upload, deploy
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REUSE_KEYS="${REUSE_KEYS:-false}"
ENABLE_SPAMMER="${ENABLE_SPAMMER:-true}"
SPAMMER_ADDRESS="${SPAMMER_ADDRESS:-Qaf84bc06703edfc371a0177ac8b482622d5ad242}"
QRYSM_DIR="${QRYSM_DIR:-$(cd "${ROOT_DIR}/../qrysm" 2>/dev/null && pwd || echo "")}"
SSH_KEY_FILE="${TF_VAR_ssh_public_key_path:-}"
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --reuse-keys) REUSE_KEYS=true; shift ;;
    --no-spammer) ENABLE_SPAMMER=false; shift ;;
    --spammer) ENABLE_SPAMMER=true; shift ;;
    --ssh-key-file) SSH_KEY_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

NUM_VALIDATORS="${1:-128}"
NUM_NODES="${2:-2}"
GENESIS_DELAY="${3:-600}"

if [ "$ENABLE_SPAMMER" = true ]; then
  SPAMMER_COUNT=1
else
  SPAMMER_COUNT=0
fi

if [ -z "$SSH_KEY_FILE" ]; then
  echo "ERROR: SSH public key file not set."
  echo "Usage: ./scripts/setup.sh --ssh-key-file ~/.ssh/id_rsa.pub [--no-spammer] [validators] [nodes] [delay]"
  exit 1
fi

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo "ERROR: SSH public key file not found: ${SSH_KEY_FILE}"
  exit 1
fi

export TF_VAR_ssh_public_key_path="${SSH_KEY_FILE}"

echo "==> Setup configuration:"
echo "    Validators: ${NUM_VALIDATORS}"
echo "    Nodes: ${NUM_NODES}"
echo "    Genesis delay: ${GENESIS_DELAY}s"
echo "    SSH key file: ${SSH_KEY_FILE}"
echo "    Reuse keys: ${REUSE_KEYS}"
echo "    Spammer: ${ENABLE_SPAMMER}"
if [ "$ENABLE_SPAMMER" = true ]; then
  echo "    Spammer address: ${SPAMMER_ADDRESS}"
fi
echo ""

# -------------------------------------------------------
# Patch qrysm's hardcoded prefund address with the spammer's address so that
# the qrysmctl built in Step 1 bakes the right prefund into genesis.{json,ssz}
# in a single shot. The patch is reverted right after the build so the user's
# qrysm checkout is left clean. A trap restores the file even if the build
# fails or the script is interrupted between patch and restore.
# -------------------------------------------------------
QRYSM_GENESIS_FILE=""
QRYSM_BAK=""
restore_qrysm_genesis() {
  if [ -n "${QRYSM_BAK}" ] && [ -f "${QRYSM_BAK}" ]; then
    mv "${QRYSM_BAK}" "${QRYSM_GENESIS_FILE}"
    echo "==> Restored ${QRYSM_GENESIS_FILE}"
    QRYSM_BAK=""
  fi
}
trap restore_qrysm_genesis EXIT

if [ "$ENABLE_SPAMMER" = true ]; then
  if [ -z "${QRYSM_DIR}" ] || [ ! -d "${QRYSM_DIR}" ]; then
    echo "ERROR: QRYSM_DIR not found. Set QRYSM_DIR to your qrysm checkout (default: ../qrysm)."
    exit 1
  fi
  QRYSM_GENESIS_FILE="${QRYSM_DIR}/runtime/interop/genesis.go"
  if [ ! -f "${QRYSM_GENESIS_FILE}" ]; then
    echo "ERROR: ${QRYSM_GENESIS_FILE} not found."
    exit 1
  fi
  if ! grep -q '^var defaultTestAccountAddress, _ = common\.NewAddressFromString(' "${QRYSM_GENESIS_FILE}"; then
    echo "ERROR: defaultTestAccountAddress declaration not found in ${QRYSM_GENESIS_FILE}."
    echo "       Has the qrysm source layout changed? Update setup.sh to match."
    exit 1
  fi
  QRYSM_BAK="${QRYSM_GENESIS_FILE}.spammer-bak"
  cp "${QRYSM_GENESIS_FILE}" "${QRYSM_BAK}"
  sed -i 's|^var defaultTestAccountAddress, _ = common\.NewAddressFromString(".*")|var defaultTestAccountAddress, _ = common.NewAddressFromString("'"${SPAMMER_ADDRESS}"'")|' "${QRYSM_GENESIS_FILE}"
  echo "==> Patched qrysm prefund address to ${SPAMMER_ADDRESS}"
fi

# -------------------------------------------------------
# Step 1: Build binaries
# -------------------------------------------------------
echo "==> Step 1: Building binaries..."
cd "${ROOT_DIR}"
make build

# qrysm patch is only needed for the build above; revert it now so the
# remainder of the run (and the user's working tree) sees the original.
restore_qrysm_genesis

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
  -var="node_count=${NUM_NODES}" \
  -var="spammer_node_count=${SPAMMER_COUNT}"

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
