#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# Preflight checks — verify all required files and tools
# -------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ERRORS=0

check_file() {
  if [ ! -f "$1" ]; then
    echo "FAIL: $1 not found — $2"
    ERRORS=$((ERRORS + 1))
  else
    echo "  OK: $1"
  fi
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "FAIL: '$1' not installed — $2"
    ERRORS=$((ERRORS + 1))
  else
    echo "  OK: $1 ($(command -v "$1"))"
  fi
}

echo "==> Checking required tools..."
check_command terraform "https://www.terraform.io/downloads"
check_command ansible-playbook "sudo apt install ansible"
check_command aws "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install"
check_command jq "sudo apt install jq"

echo ""
echo "==> Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
  echo "  OK: AWS credentials configured"
else
  echo "FAIL: AWS credentials not configured — run 'aws configure'"
  ERRORS=$((ERRORS + 1))
fi

echo ""
echo "==> Checking SSH key..."
PEM_FILE=$(grep 'private_key_file' "${ROOT_DIR}/ansible/ansible.cfg" | awk -F= '{print $2}' | xargs)
PEM_FILE="${PEM_FILE/#\~/$HOME}"
check_file "$PEM_FILE" "SSH key for Ansible — copy your .pem file to this path"

if [ -f "$PEM_FILE" ]; then
  PERMS=$(stat -c "%a" "$PEM_FILE" 2>/dev/null || stat -f "%OLp" "$PEM_FILE")
  if [ "$PERMS" != "600" ]; then
    echo "FAIL: $PEM_FILE has permissions $PERMS, expected 600 — run 'chmod 600 $PEM_FILE'"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""
echo "==> Checking SSH public key for EC2..."
SSH_PUB_KEY="${TF_VAR_ssh_public_key_path:-}"
if [ -z "$SSH_PUB_KEY" ]; then
  for f in "${ROOT_DIR}"/terraform/terraform.tfvars "${ROOT_DIR}"/terraform/*.auto.tfvars; do
    if [ -f "$f" ]; then
      val=$(grep -E '^\s*ssh_public_key_path\s*=' "$f" 2>/dev/null | head -1 | sed 's/.*=\s*"\?\([^"]*\)"\?.*/\1/')
      if [ -n "$val" ]; then
        SSH_PUB_KEY="${val/#\~/$HOME}"
        break
      fi
    fi
  done
fi

if [ -n "$SSH_PUB_KEY" ]; then
  if [ -f "$SSH_PUB_KEY" ]; then
    echo "  OK: SSH public key found at ${SSH_PUB_KEY}"
  else
    echo "FAIL: SSH public key not found at ${SSH_PUB_KEY}"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "WARN: ssh_public_key_path not set — pass --ssh-key-file to setup.sh or set TF_VAR_ssh_public_key_path"
fi

echo ""
echo "==> Checking genesis files..."
check_file "${ROOT_DIR}/ansible/roles/common/files/genesis.json" "Run ./scripts/genesis.sh first"
check_file "${ROOT_DIR}/ansible/roles/common/files/genesis.ssz" "Run ./scripts/genesis.sh first"
check_file "${ROOT_DIR}/ansible/roles/common/files/jwt.hex" "Run ./scripts/genesis.sh first"

echo ""
echo "==> Checking Ansible inventory..."
check_file "${ROOT_DIR}/ansible/inventory/hosts.ini" "Run 'cd terraform && terraform apply' first"

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found. Fix them before deploying."
  exit 1
else
  echo "ALL CHECKS PASSED"
fi