.PHONY: preflight genesis build-upload infra-plan infra-apply deploy update stress-test collect destroy build build-tools build-node

TERRAFORM_DIR = terraform
ANSIBLE_DIR = ansible
SCRIPTS_DIR = scripts
BUILD_DIR = build

# Source repo paths (override with env vars if needed)
GO_QRL_DIR ?= $(shell cd ../go-qrl 2>/dev/null && pwd)
QRYSM_DIR ?= $(shell cd ../qrysm 2>/dev/null && pwd)

# Build all binaries (tools + node binaries)
build: build-tools build-node

# Build tools needed for genesis generation
build-tools: $(BUILD_DIR)/staking-deposit-cli $(BUILD_DIR)/qrysmctl

$(BUILD_DIR)/staking-deposit-cli:
	@mkdir -p $(BUILD_DIR)
	cd $(QRYSM_DIR) && go build -o $(CURDIR)/$(BUILD_DIR)/staking-deposit-cli ./cmd/staking-deposit-cli/deposit/
	@echo "Built: $(BUILD_DIR)/staking-deposit-cli"

$(BUILD_DIR)/qrysmctl:
	@mkdir -p $(BUILD_DIR)
	cd $(QRYSM_DIR) && go build -o $(CURDIR)/$(BUILD_DIR)/qrysmctl ./cmd/qrysmctl/
	@echo "Built: $(BUILD_DIR)/qrysmctl"

# Build node binaries for binary deploy mode
build-node: $(BUILD_DIR)/gqrl $(BUILD_DIR)/beacon-chain $(BUILD_DIR)/validator

$(BUILD_DIR)/gqrl:
	@mkdir -p $(BUILD_DIR)
	cd $(GO_QRL_DIR) && go build -o $(CURDIR)/$(BUILD_DIR)/gqrl ./cmd/gqrl/
	@echo "Built: $(BUILD_DIR)/gqrl"

$(BUILD_DIR)/beacon-chain:
	@mkdir -p $(BUILD_DIR)
	cd $(QRYSM_DIR) && go build -o $(CURDIR)/$(BUILD_DIR)/beacon-chain ./cmd/beacon-chain/
	@echo "Built: $(BUILD_DIR)/beacon-chain"

$(BUILD_DIR)/validator:
	@mkdir -p $(BUILD_DIR)
	cd $(QRYSM_DIR) && go build -o $(CURDIR)/$(BUILD_DIR)/validator ./cmd/validator/
	@echo "Built: $(BUILD_DIR)/validator"

# Preflight checks
preflight:
	$(SCRIPTS_DIR)/preflight.sh

# Build binaries and upload to S3
build-upload:
	$(SCRIPTS_DIR)/build-and-upload.sh

# Generate genesis files and upload to S3
genesis:
	$(SCRIPTS_DIR)/genesis.sh

# Preview infrastructure changes
infra-plan:
	cd $(TERRAFORM_DIR) && terraform plan

# Create/update infrastructure
infra-apply:
	cd $(TERRAFORM_DIR) && terraform apply

# Deploy all services to nodes (runs preflight first)
deploy: preflight
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/deploy.yml

# Update a specific service (usage: make update SERVICE=beacon IMAGE=theqrl/qrysm-beacon-chain:v1.2.3)
update:
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/update.yml -e "service=$(SERVICE)" -e "image=$(IMAGE)"

# Run stress test
stress-test:
	$(SCRIPTS_DIR)/stress.sh

# Collect logs and metrics
collect:
	$(SCRIPTS_DIR)/collect.sh

# Destroy all infrastructure
destroy:
	cd $(TERRAFORM_DIR) && terraform destroy