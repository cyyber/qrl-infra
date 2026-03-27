#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Build QRL binaries from source and upload to S3
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${ROOT_DIR}/build"

# Source repos (adjust paths if needed)
GO_QRL_DIR="${GO_QRL_DIR:-$(cd "${ROOT_DIR}/../go-qrl" 2>/dev/null && pwd || echo "")}"
QRYSM_DIR="${QRYSM_DIR:-$(cd "${ROOT_DIR}/../qrysm" 2>/dev/null && pwd || echo "")}"
TX_SPAMMER_DIR="${TX_SPAMMER_DIR:-$(cd "${ROOT_DIR}/../qrl-tx-spammer" 2>/dev/null && pwd || echo "")}"

# S3 bucket from Terraform output
S3_BUCKET="${S3_BUCKET:-$(cd "${ROOT_DIR}/terraform" && terraform output -raw s3_bucket 2>/dev/null || echo "")}"

if [ -z "$S3_BUCKET" ]; then
  echo "ERROR: S3_BUCKET not set and could not read from terraform output."
  echo "Usage: S3_BUCKET=your-bucket ./scripts/build-and-upload.sh"
  echo "   or: run 'terraform apply' first"
  exit 1
fi

mkdir -p "${BUILD_DIR}"

# Target: Linux amd64 (EC2 instances)
export GOOS=linux
export GOARCH=amd64
export CGO_ENABLED=1

echo "==> Building for ${GOOS}/${GOARCH}"

# -------------------------------------------------------
# Build go-qrl (gqrl)
# -------------------------------------------------------
if [ -n "$GO_QRL_DIR" ] && [ -d "$GO_QRL_DIR" ]; then
  echo "==> Building gqrl from ${GO_QRL_DIR}..."
  cd "$GO_QRL_DIR"
  go build -o "${BUILD_DIR}/gqrl" ./cmd/gqrl/
  echo "    Built: ${BUILD_DIR}/gqrl"
else
  echo "SKIP: go-qrl not found at ${GO_QRL_DIR:-../go-qrl}"
fi

# -------------------------------------------------------
# Build qrysm (beacon-chain, validator, qrysmctl, staking-deposit-cli)
# -------------------------------------------------------
if [ -n "$QRYSM_DIR" ] && [ -d "$QRYSM_DIR" ]; then
  echo "==> Building beacon-chain from ${QRYSM_DIR}..."
  cd "$QRYSM_DIR"
  go build -o "${BUILD_DIR}/beacon-chain" ./cmd/beacon-chain/
  echo "    Built: ${BUILD_DIR}/beacon-chain"

  echo "==> Building validator from ${QRYSM_DIR}..."
  go build -o "${BUILD_DIR}/validator" ./cmd/validator/
  echo "    Built: ${BUILD_DIR}/validator"

  echo "==> Building qrysmctl from ${QRYSM_DIR}..."
  go build -o "${BUILD_DIR}/qrysmctl" ./cmd/qrysmctl/
  echo "    Built: ${BUILD_DIR}/qrysmctl"

  echo "==> Building staking-deposit-cli from ${QRYSM_DIR}..."
  go build -o "${BUILD_DIR}/staking-deposit-cli" ./cmd/staking-deposit-cli/deposit/
  echo "    Built: ${BUILD_DIR}/staking-deposit-cli"
else
  echo "SKIP: qrysm not found at ${QRYSM_DIR:-../qrysm}"
fi

# -------------------------------------------------------
# Build qrl-tx-spammer
# -------------------------------------------------------
if [ -n "$TX_SPAMMER_DIR" ] && [ -d "$TX_SPAMMER_DIR" ]; then
  echo "==> Building tx-spammer from ${TX_SPAMMER_DIR}..."
  cd "$TX_SPAMMER_DIR"
  go build -o "${BUILD_DIR}/tx-spammer" ./cmd/tx-spammer/
  echo "    Built: ${BUILD_DIR}/tx-spammer"
else
  echo "SKIP: qrl-tx-spammer not found at ${TX_SPAMMER_DIR:-../qrl-tx-spammer}"
fi

# -------------------------------------------------------
# Upload to S3
# -------------------------------------------------------
echo ""
echo "==> Uploading binaries to s3://${S3_BUCKET}/binaries/"

for binary in gqrl beacon-chain validator qrysmctl staking-deposit-cli tx-spammer; do
  if [ -f "${BUILD_DIR}/${binary}" ]; then
    aws s3 cp "${BUILD_DIR}/${binary}" "s3://${S3_BUCKET}/binaries/${binary}"
    echo "    Uploaded: ${binary}"
  fi
done

# -------------------------------------------------------
# Update ansible group_vars with binary URLs
# -------------------------------------------------------
ALL_YML="${ROOT_DIR}/ansible/group_vars/all.yml"

BASE_URL="s3://${S3_BUCKET}/binaries"

sed -i "s|^gqrl_binary_url:.*|gqrl_binary_url: \"${BASE_URL}/gqrl\"|" "${ALL_YML}"
sed -i "s|^beacon_binary_url:.*|beacon_binary_url: \"${BASE_URL}/beacon-chain\"|" "${ALL_YML}"
sed -i "s|^validator_binary_url:.*|validator_binary_url: \"${BASE_URL}/validator\"|" "${ALL_YML}"
sed -i "s|^spammer_binary_url:.*|spammer_binary_url: \"${BASE_URL}/tx-spammer\"|" "${ALL_YML}"

echo ""
echo "==> Updated ${ALL_YML} with binary URLs:"
echo "    ${BASE_URL}/gqrl"
echo "    ${BASE_URL}/beacon-chain"
echo "    ${BASE_URL}/validator"
echo "    ${BASE_URL}/tx-spammer"