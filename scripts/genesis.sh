#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Generate validator keys and genesis files for QRL network
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
OUTPUT_DIR="${ROOT_DIR}/genesis-data"

# Use local build/ binaries if available, fall back to PATH
if [ -x "${BUILD_DIR}/staking-deposit-cli" ]; then
  export PATH="${BUILD_DIR}:${PATH}"
fi
if [ -x "${BUILD_DIR}/qrysmctl" ]; then
  export PATH="${BUILD_DIR}:${PATH}"
fi
REUSE_KEYS=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --reuse-keys) REUSE_KEYS=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

NUM_VALIDATORS="${1:-2000}"
NUM_NODES="${2:-2}"
GENESIS_DELAY="${3:-600}"  # seconds from now
EXECUTION_ADDRESS="${EXECUTION_ADDRESS:-Qaf84bc06703edfc371a0177ac8b482622d5ad242}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-testpassword123}"

echo "==> Configuration:"
echo "    Validators: ${NUM_VALIDATORS}"
echo "    Nodes: ${NUM_NODES}"
echo "    Genesis delay: ${GENESIS_DELAY}s"
echo "    Execution address: ${EXECUTION_ADDRESS}"
echo "    Reuse keys: ${REUSE_KEYS}"

mkdir -p "${OUTPUT_DIR}"

# -------------------------------------------------------
# Step 1: Generate JWT secret
# -------------------------------------------------------
if [ ! -f "${OUTPUT_DIR}/jwt.hex" ]; then
  openssl rand -hex 32 > "${OUTPUT_DIR}/jwt.hex"
  echo "==> Generated JWT secret"
fi

# -------------------------------------------------------
# Step 2: Generate validator keys using staking-deposit-cli
# -------------------------------------------------------
if [ "$REUSE_KEYS" = true ]; then
  # Verify existing keys exist
  if ! ls "${OUTPUT_DIR}/validator_keys/deposit_data-"*.json &>/dev/null; then
    echo "FAIL: --reuse-keys specified but no existing keys found in ${OUTPUT_DIR}/validator_keys/"
    echo "      Run without --reuse-keys first to generate keys."
    exit 1
  fi
  EXISTING_COUNT=$(ls "${OUTPUT_DIR}/validator_keys/keystore-"*.json 2>/dev/null | wc -l)
  echo "==> Reusing ${EXISTING_COUNT} existing validator keystores"
else
  echo "==> Generating ${NUM_VALIDATORS} validator keys..."

  # Write keystore password to file
  echo -n "${KEYSTORE_PASSWORD}" > "${OUTPUT_DIR}/keystore-password.txt"

  staking-deposit-cli new-seed \
    --num-validators "${NUM_VALIDATORS}" \
    --folder "${OUTPUT_DIR}/validator_keys" \
    --chain-name testnet \
    --execution-address "${EXECUTION_ADDRESS}" \
    --keystore-password-file "${OUTPUT_DIR}/keystore-password.txt"

  echo "==> Generated ${NUM_VALIDATORS} validator keystores"
fi

# -------------------------------------------------------
# Step 3: Generate genesis using deposit data
# -------------------------------------------------------
DEPOSIT_FILE=$(ls "${OUTPUT_DIR}/validator_keys/deposit_data-"*.json | head -1)

echo "==> Generating genesis from deposit data: ${DEPOSIT_FILE}"

qrysmctl testnet generate-genesis \
  --deposit-json-file "${DEPOSIT_FILE}" \
  --genesis-time-delay "${GENESIS_DELAY}" \
  --output-ssz "${OUTPUT_DIR}/genesis.ssz" \
  --gqrl-genesis-json-out "${OUTPUT_DIR}/genesis.json"

echo "==> Genesis files generated"

# -------------------------------------------------------
# Step 4: Split keystores across nodes
# -------------------------------------------------------
echo "==> Splitting keystores across ${NUM_NODES} nodes..."

VALIDATORS_PER_NODE=$(( (NUM_VALIDATORS + NUM_NODES - 1) / NUM_NODES ))
KEYSTORE_FILES=("${OUTPUT_DIR}/validator_keys/keystore-"*.json)
TOTAL_KEYSTORES=${#KEYSTORE_FILES[@]}

for (( node=0; node<NUM_NODES; node++ )); do
  NODE_DIR="${OUTPUT_DIR}/node-${node}/keystores"
  mkdir -p "${NODE_DIR}"

  START=$(( node * VALIDATORS_PER_NODE ))
  END=$(( START + VALIDATORS_PER_NODE ))
  if [ ${END} -gt ${TOTAL_KEYSTORES} ]; then
    END=${TOTAL_KEYSTORES}
  fi

  for (( i=START; i<END; i++ )); do
    cp "${KEYSTORE_FILES[$i]}" "${NODE_DIR}/"
  done

  # Copy password file to each node directory
  cp "${OUTPUT_DIR}/keystore-password.txt" "${OUTPUT_DIR}/node-${node}/keystore-password.txt"

  COUNT=$(( END - START ))
  echo "    Node ${node}: ${COUNT} keystores (indices ${START}-$((END-1)))"
done

# -------------------------------------------------------
# Step 5: Copy files for Ansible distribution
# -------------------------------------------------------
ANSIBLE_FILES="${ROOT_DIR}/ansible/roles/common/files"
cp "${OUTPUT_DIR}/jwt.hex" "${ANSIBLE_FILES}/jwt.hex"
cp "${OUTPUT_DIR}/genesis.json" "${ANSIBLE_FILES}/genesis.json"
cp "${OUTPUT_DIR}/genesis.ssz" "${ANSIBLE_FILES}/genesis.ssz"
echo "==> Copied genesis files to ${ANSIBLE_FILES}/"

# -------------------------------------------------------
# Step 6: Upload to S3 if bucket name is provided
# -------------------------------------------------------
S3_BUCKET="${S3_BUCKET:-}"
if [ -n "${S3_BUCKET}" ]; then
  aws s3 cp "${OUTPUT_DIR}/genesis.ssz" "s3://${S3_BUCKET}/genesis/genesis.ssz"
  aws s3 cp "${OUTPUT_DIR}/genesis.json" "s3://${S3_BUCKET}/genesis/genesis.json"
  aws s3 cp "${OUTPUT_DIR}/jwt.hex" "s3://${S3_BUCKET}/genesis/jwt.hex"

  # Upload per-node keystores
  for (( node=0; node<NUM_NODES; node++ )); do
    aws s3 cp "${OUTPUT_DIR}/node-${node}/" "s3://${S3_BUCKET}/keystores/node-${node}/" --recursive
  done

  echo "==> Uploaded to s3://${S3_BUCKET}/"
fi

echo ""
echo "==> Done!"
echo "    Genesis files: ${OUTPUT_DIR}/"
echo "    Per-node keystores: ${OUTPUT_DIR}/node-{0..${NUM_NODES}}/"
echo "    Chain starts at: $(date -d "+${GENESIS_DELAY} seconds" 2>/dev/null || date -v+${GENESIS_DELAY}S)"
if [ "$REUSE_KEYS" = false ]; then
  echo ""
  echo "    IMPORTANT: Save the mnemonic printed above! You need it to regenerate keys."
  echo "    To regenerate genesis with the same keys later, run:"
  echo "    ./scripts/genesis.sh --reuse-keys ${NUM_VALIDATORS} ${NUM_NODES} <delay>"
fi