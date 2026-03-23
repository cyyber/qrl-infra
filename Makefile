.PHONY: preflight genesis build-upload infra-plan infra-apply deploy update stress-test collect destroy

TERRAFORM_DIR = terraform
ANSIBLE_DIR = ansible
SCRIPTS_DIR = scripts

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