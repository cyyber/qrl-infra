
# qrl-infra

Infrastructure tooling for deploying and managing QRL networks (stress test, testnet, mainnet) on AWS. Supports single-region and multi-region deployments.

Deploys [go-qrl](https://github.com/theQRL/go-qrl) (execution layer) and [qrysm](https://github.com/theQRL/qrysm) (beacon chain + validators) across multiple EC2 instances with monitoring.

## Architecture

Each node runs all three services on the same machine:

```
┌─────────────────────────────────────┐
│           EC2 Instance (x N)        │
│                                     │
│  ┌───────────┐  ┌───────────────┐   │
│  │  go-qrl   │──│  qrysm beacon │   │
│  │  (exec)   │  │   (consensus) │   │
│  └───────────┘  └───────┬───────┘   │
│                         │           │
│                 ┌───────┴───────┐   │
│                 │ qrysm validator│   │
│                 └───────────────┘   │
└─────────────────────────────────────┘
         │ P2P                │ P2P
         ▼                    ▼
   Other nodes ...    Other nodes ...

┌─────────────┐              ┌─────────────┐
│  TX Spammer  │              │  Monitoring  │
│(tx-spammer)  │              │  Prometheus  │
└─────────────┘              │  + Grafana   │
                             └─────────────┘
```

- Execution, beacon, and validator communicate via `localhost`
- P2P traffic between nodes goes over the public internet
- **Terraform** creates AWS infrastructure (VPC, EC2, S3, security groups) across one or more regions
- **Ansible** manages software on the instances (deploy, update, collect logs)
- Each service supports **Docker** or **bare binary** deployment via `deploy_mode`
- Nodes auto-distribute equally across configured regions

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.12
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Go](https://go.dev/dl/) >= 1.21 (to build binaries from source)
- [go-qrl](https://github.com/theQRL/go-qrl), [qrysm](https://github.com/theQRL/qrysm), and [qrl-tx-spammer](https://github.com/theQRL/qrl-tx-spammer) source repos as siblings (e.g. `../go-qrl`, `../qrysm`, `../qrl-tx-spammer`)
- An EC2 key pair in your target AWS region(s)

## Quick Start

### One command setup

```bash
# Build, genesis, infra, upload, deploy — all in one
SSH_KEY_NAME=your-key ./scripts/setup.sh 512 2 600
#                                        ^^^  ^  ^^^
#                                   validators nodes delay(s)

# Without transaction spammer
SSH_KEY_NAME=your-key ./scripts/setup.sh --no-spammer 512 2 600

# Restart network with same keys (skips key generation)
SSH_KEY_NAME=your-key ./scripts/setup.sh --reuse-keys 512 2 600
```

### Step by step

#### 1. Build tools

```bash
# Build staking-deposit-cli and qrysmctl (needed for genesis)
make build-tools

# Build all binaries including gqrl, beacon-chain, validator (needed for binary deploy mode)
make build
```

#### 2. Generate genesis

```bash
# 512 validators, 2 nodes, 10-minute delay before chain starts
./scripts/genesis.sh 512 2 600

# Reuse existing keys, only regenerate genesis with a new start time (fast)
./scripts/genesis.sh --reuse-keys 512 2 600

# Or with S3 upload
S3_BUCKET=your-bucket ./scripts/genesis.sh 512 2 600
```

#### 3. Configure infrastructure

Edit `terraform/terraform.tfvars`:

```hcl
regions = [
  "eu-north-1",
  # "us-east-1",      # uncomment for multi-region
  # "ap-southeast-1",
]

node_count         = 2
node_instance_type = "m5.2xlarge"
```

#### 4. Create infrastructure

```bash
cd terraform
terraform init
terraform apply -var="ssh_key_name=your-key"
```

This creates EC2 instances across all configured regions and auto-generates the Ansible inventory at `ansible/inventory/hosts.ini`.

#### 5. Upload binaries to S3

```bash
./scripts/build-and-upload.sh
```

#### 6. Deploy services

```bash
make deploy
```

### 7. Run stress test

```bash
# Monitor for 10 epochs
make stress-test

# Custom: 5 epochs, 60s slots, 128 slots/epoch
./scripts/stress.sh 5 60 128
```

### 8. Collect results

```bash
make collect
```

### 9. Tear down

```bash
make destroy
```

## Multi-region deployment

Deploy nodes across multiple AWS regions for real-world network latency testing.

### Configuration

Edit `terraform/terraform.tfvars`:

```hcl
# 200 nodes across 4 regions (50 per region, auto-distributed)
regions = [
  "eu-north-1",
  "us-east-1",
  "us-west-2",
  "ap-southeast-1",
]

node_count = 200
```

### Supported regions

| Region | Location |
|--------|----------|
| `eu-north-1` | Stockholm |
| `us-east-1` | N. Virginia |
| `us-east-2` | Ohio |
| `us-west-2` | Oregon |
| `eu-west-1` | Ireland |
| `eu-central-1` | Frankfurt |
| `ap-southeast-1` | Singapore |
| `ap-northeast-1` | Tokyo |
| `ap-south-1` | Mumbai |
| `sa-east-1` | Sao Paulo |

### How it works

- Nodes are auto-distributed equally across regions (e.g. 200 nodes / 4 regions = 50 each)
- The first region in the list is the **primary region** (hosts S3, IAM, monitoring, spammer)
- Each region gets its own VPC, subnet, and security groups
- P2P traffic goes over the public internet between regions
- No VPC peering needed

### SSH keys for multi-region

EC2 key pairs are region-specific. Either create the key in each region manually, or auto-import:

```hcl
# In terraform.tfvars:
ssh_public_key_path = "~/.ssh/id_rsa.pub"
```

### Typical inter-region latencies

| Route | RTT |
|-------|-----|
| eu-north-1 <-> eu-west-1 | ~30ms |
| eu-north-1 <-> us-east-1 | ~90ms |
| us-east-1 <-> us-west-2 | ~65ms |
| us-east-1 <-> ap-southeast-1 | ~230ms |
| eu-west-1 <-> ap-northeast-1 | ~250ms |

## Transaction spammer

The [qrl-tx-spammer](https://github.com/theQRL/qrl-tx-spammer) generates transaction load for stress testing.

### Configuration

Edit `ansible/group_vars/spammer.yml`:

```yaml
spammer_scenario: "eoatx"
spammer_throughput: 100    # transactions per slot (60s)
spammer_wallet_seed: "..."  # pre-funded genesis account seed
```

### Available scenarios

| Scenario | Description |
|----------|-------------|
| `eoatx` | Simple value transfers between wallets |
| `deploytx` | Contract deployments |
| `gasburnertx` | Gas-burning contract calls |
| `sqrctx` | SQR contract transactions |
| `wallets` | Wallet creation and management |

### Disabling the spammer

```bash
# Via setup script
SSH_KEY_NAME=your-key ./scripts/setup.sh --no-spammer 512 2 600

# Via terraform
terraform apply -var="spammer_node_count=0"
```

## Updating nodes

After fixing a bug and building a new image, roll it out without losing chain state:

```bash
# Update beacon on all nodes (one at a time, rolling)
make update SERVICE=beacon IMAGE=theqrl/qrysm-beacon-chain:v1.2.4

# Update execution layer
make update SERVICE=execution IMAGE=theqrl/go-qrl:v1.0.1

# Update only the first 5 nodes
cd ansible && ansible-playbook playbooks/update.yml -l "node[0:4]" -e "service=beacon" -e "image=theqrl/qrysm-beacon-chain:v1.2.4"
```

## Deploy modes

Set globally in `ansible/group_vars/all.yml` or per-host in the inventory:

| Mode | How it runs | Best for |
|------|------------|----------|
| `docker` | Docker containers with mounted volumes | Easy rollout, isolation |
| `binary` | Systemd services with direct binaries | Performance, debugging with `dlv` |

```bash
# Deploy with binary mode
cd ansible && ansible-playbook playbooks/deploy.yml -e "deploy_mode=binary"
```

## Configuration

### Terraform (`terraform/terraform.tfvars`)

| Variable | Default | Description |
|----------|---------|-------------|
| `regions` | `["eu-north-1"]` | AWS regions to deploy into |
| `node_count` | 2 | Total nodes (auto-distributed across regions) |
| `spammer_node_count` | 1 | Transaction spammer nodes (primary region) |
| `node_instance_type` | m5.2xlarge | EC2 instance type for nodes |
| `deploy_mode` | binary | `docker` or `binary` |
| `ebs_volume_size` | 100 | GB per data volume |
| `ssh_public_key_path` | (empty) | Path to SSH public key for multi-region import |

### Ansible variables (`ansible/group_vars/`)

- `all.yml` -- Docker images, binary URLs, paths, localhost endpoints
- `node.yml` -- Ports, bootnodes, extra flags for all three services
- `spammer.yml` -- Scenario, throughput, wallet seed, refill settings

## Monitoring

Prometheus + Grafana are deployed to a dedicated monitoring instance in the primary region.

- **Grafana**: `http://<monitoring-ip>:3000` (admin/admin)
- **Prometheus**: `http://<monitoring-ip>:9090`

The pre-configured dashboard tracks:
- Head slot & finality delay
- Attestation counts
- Peer counts (beacon + execution)
- TX pool size & block gas used

## Validator recommendations

With QRL's `SLOTS_PER_EPOCH=128`, use enough validators for stable consensus:

| Validators | Committee size | Stability |
|------------|---------------|-----------|
| 128 | 1 | Minimum, slow start |
| 256 | 2 | Better |
| 512 | 4 | Good |
| 1024+ | 8+ | Excellent |

## Project structure

```
qrl-infra/
├── terraform/                 # AWS infrastructure
│   ├── terraform.tfvars       # User configuration (regions, counts, etc.)
│   ├── main.tf                # S3, IAM, region modules, spammer, monitoring
│   ├── variables.tf           # Variable definitions
│   ├── versions.tf            # Provider aliases (10 regions)
│   ├── locals.tf              # Auto-distribution logic
│   ├── outputs.tf             # IPs + auto-generated Ansible inventory
│   ├── modules/
│   │   └── region/            # Per-region: VPC, SG, EC2 nodes, EBS
│   └── templates/
│       ├── cloud-init.sh      # Instance bootstrap (Docker, volumes, sysctl)
│       └── inventory.tpl      # Ansible inventory template
├── ansible/                   # Service management
│   ├── playbooks/
│   │   ├── deploy.yml         # Full deployment
│   │   ├── update.yml         # Rolling updates
│   │   └── collect.yml        # Log/metric collection
│   ├── roles/
│   │   ├── common/            # JWT, genesis, base packages
│   │   ├── execution/         # go-qrl (docker.yml + binary.yml)
│   │   ├── beacon/            # qrysm beacon (docker.yml + binary.yml)
│   │   ├── validator/         # qrysm validator (docker.yml + binary.yml)
│   │   ├── spammer/           # qrl-tx-spammer (docker.yml + binary.yml)
│   │   └── monitoring/        # Prometheus + Grafana
│   └── group_vars/            # Per-group configuration
├── build/                     # Built binaries (git-ignored)
├── scripts/
│   ├── setup.sh               # One-command setup (build + genesis + infra + deploy)
│   ├── genesis.sh             # Genesis generation + S3 upload
│   ├── build-and-upload.sh    # Build binaries + upload to S3
│   ├── stress.sh              # Stress test orchestration
│   └── collect.sh             # Log/metric collection
└── monitoring/
    ├── prometheus/             # Scrape configs + alerts
    └── grafana/                # Dashboards + provisioning
```
