
# qrl-infra

Infrastructure tooling for deploying and managing QRL networks (stress test, testnet, mainnet) on AWS.

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
│  (tx-fuzz)   │              │  Prometheus  │
│  x 5-10      │              │  + Grafana   │
└─────────────┘              └─────────────┘
```

- Execution, beacon, and validator communicate via `localhost`
- P2P traffic between nodes goes over the network
- **Terraform** creates AWS infrastructure (VPC, EC2, S3, security groups)
- **Ansible** manages software on the instances (deploy, update, collect logs)
- Each service supports **Docker** or **bare binary** deployment via `deploy_mode`

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.12
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [qrysmctl](https://github.com/theQRL/qrysm) for genesis generation
- An EC2 key pair in your target AWS region

## Quick Start

### 1. Generate genesis

```bash
# 2000 validators, 10-minute delay before chain starts
./scripts/genesis.sh 2000 600

# Or with S3 upload
S3_BUCKET=your-bucket ./scripts/genesis.sh 2000 600
```

### 2. Create infrastructure

```bash
cd terraform
terraform init
terraform apply -var="ssh_key_name=your-key"
```

This creates all EC2 instances and auto-generates the Ansible inventory at `ansible/inventory/hosts.ini`.

### 3. Deploy services

```bash
make deploy
```

### 4. Run stress test

```bash
# Monitor for 10 epochs
make stress-test

# Custom: 5 epochs, 60s slots, 128 slots/epoch
./scripts/stress.sh 5 60 128
```

### 5. Collect results

```bash
make collect
```

### 6. Tear down

```bash
make destroy
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

### Terraform variables (`terraform/variables.tf`)

| Variable | Default | Description |
|----------|---------|-------------|
| `node_count` | 20 | Number of nodes (each runs execution + beacon + validator) |
| `total_validators` | 2000 | Total validators (split across nodes) |
| `spammer_node_count` | 5 | Transaction spammer nodes |
| `node_instance_type` | m5.2xlarge | EC2 instance type for nodes |
| `deploy_mode` | docker | `docker` or `binary` |
| `ebs_volume_size` | 100 | GB per data volume |

### Ansible variables (`ansible/group_vars/`)

- `all.yml` — Docker images, binary URLs, paths, localhost endpoints
- `node.yml` — Ports, bootnodes, extra flags for all three services
- `spammer.yml` — TX count, accounts, seed

## Monitoring

Prometheus + Grafana are deployed to a dedicated monitoring instance.

- **Grafana**: `http://<monitoring-ip>:3000` (admin/admin)
- **Prometheus**: `http://<monitoring-ip>:9090`

The pre-configured dashboard tracks:
- Head slot & finality delay
- Missed slots rate
- Attestation counts
- Peer counts (beacon + execution)
- TX pool size & block gas used

## Project structure

```
qrl-infra/
├── terraform/              # AWS infrastructure
│   ├── main.tf             # VPC, SGs, EC2 instances, S3
│   ├── variables.tf        # Configurable parameters
│   ├── outputs.tf          # IPs + auto-generated Ansible inventory
│   └── templates/
│       ├── cloud-init.sh   # Instance bootstrap (Docker, volumes, sysctl)
│       └── inventory.tpl   # Ansible inventory template
├── ansible/                # Service management
│   ├── playbooks/
│   │   ├── deploy.yml      # Full deployment
│   │   ├── update.yml      # Rolling updates
│   │   └── collect.yml     # Log/metric collection
│   ├── roles/
│   │   ├── common/         # JWT, genesis, base packages
│   │   ├── execution/      # go-qrl (docker.yml + binary.yml)
│   │   ├── beacon/         # qrysm beacon (docker.yml + binary.yml)
│   │   ├── validator/      # qrysm validator (docker.yml + binary.yml)
│   │   ├── spammer/        # tx-fuzz (docker.yml + binary.yml)
│   │   └── monitoring/     # Prometheus + Grafana
│   └── group_vars/         # Per-group configuration
├── scripts/
│   ├── genesis.sh          # Genesis generation + S3 upload
│   ├── stress.sh           # Stress test orchestration
│   └── collect.sh          # Log/metric collection
└── monitoring/
    ├── prometheus/          # Scrape configs + alerts
    └── grafana/             # Dashboards + provisioning
```