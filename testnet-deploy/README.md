# Testnet Deploy

Manual testnet deployment tool for launching a QRL testnet and collecting bootnode QNRs to embed into go-qrl and qrysm.

## Prerequisites

- 2+ machines with static public IPs (EC2, VPS, etc.)
- SSH access to all machines (`ssh user@ip` without password prompt)
- Ports open on all machines: 30303 (TCP+UDP), 13000 (TCP), 12000 (UDP)
- Built binaries: `gqrl`, `beacon-chain`, `validator` in `build/`
- Generated genesis data in `genesis-data/`

## Quick Start

### 1. Create nodes file

```bash
cp nodes.txt.example nodes.txt
```

Edit `nodes.txt` with your machine addresses:

```
ubuntu@54.123.45.67
ubuntu@18.234.56.78
```

Node order matters — node 0 gets `genesis-data/node-0/` keystores, node 1 gets `genesis-data/node-1/`, etc.

### 2. Launch (one command)

```bash
./scripts/launch-testnet.sh nodes.txt 512 600
#                                     ^^^  ^^^
#                                validators delay(s)
```

This builds binaries, generates genesis, deploys to all nodes, starts all services, and saves bootnode QNRs to `bootnodes.txt`.

Options via environment variables:

```bash
# Custom execution address (prefunded in genesis):
EXECUTION_ADDRESS=Q<your_address> ./scripts/launch-testnet.sh nodes.txt 512 600

# Reuse existing validator keys:
REUSE_KEYS=true ./scripts/launch-testnet.sh nodes.txt 512 600
```

If `EXECUTION_ADDRESS` is not set, it defaults to `Qaf84bc06703edfc371a0177ac8b482622d5ad242`. This address is:
- Prefunded with QRL in the genesis block
- Used as the validator withdrawal address
- Used by the transaction spammer (if enabled)

Make sure you have the private key for this address.

The mnemonic seed is displayed during launch and saved to `genesis-output.log`. Save it to regenerate keys later.

### 3. Verify

Wait for genesis time, then check:

```bash
# Beacon head slot
ssh ubuntu@<node-ip> "curl -s http://127.0.0.1:3500/qrl/v1/beacon/headers/head | python3 -m json.tool"

# Execution block number
ssh ubuntu@<node-ip> "curl -s -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"qrl_blockNumber\",\"params\":[],\"id\":1}'"

# Peer count
ssh ubuntu@<node-ip> "curl -s http://127.0.0.1:3500/qrl/v1/node/peers | python3 -c 'import sys,json; print(len(json.load(sys.stdin)[\"data\"]))'"
```

## Collecting Bootnodes for Embedding

After the chain is producing blocks, `bootnodes.txt` is generated automatically by `collect-bootnodes.sh` and `start-beacon.sh`. It contains:

```
# Execution QNRs (for go-qrl --bootnodes):
qnr:-KO4Q...
qnr:-KO4Q...

# Beacon QNRs (for qrysm --bootstrap-node):
qnr:-Me4Q...
qnr:-Me4Q...
```

### Embed into go-qrl

Add execution QNRs to `params/bootnodes.go`:

```go
var TestnetBootnodes = []string{
    "qnr:...",
    "qnr:...",
}
```

### Embed into qrysm

Add beacon QNRs and genesis data to the config package.

## Scripts Reference

| Script | Description |
|--------|-------------|
| `launch-testnet.sh` | All-in-one: build, genesis, deploy, start everything |
| `deploy.sh` | Copy genesis, binaries, keystores to all nodes |
| `start-gqrl.sh` | Start gqrl on all nodes |
| `collect-bootnodes.sh` | Collect execution QNRs, peer nodes, save to bootnodes.txt |
| `start-beacon.sh` | Start beacon with automatic bootstrap exchange |
| `start-validator.sh` | Import keys and start validators |
| `stop-all.sh` | Stop all services on all nodes |

## Directory Structure

```
testnet-deploy/
├── README.md
├── nodes.txt.example       # Example nodes file
├── nodes.txt                # Your nodes (gitignored)
├── bootnodes.txt            # Generated bootnode QNRs for embedding
├── scripts/
│   ├── launch-testnet.sh       # All-in-one launcher
│   ├── deploy.sh
│   ├── start-gqrl.sh
│   ├── collect-bootnodes.sh
│   ├── start-beacon.sh
│   ├── start-validator.sh
│   └── stop-all.sh
├── genesis-output.log           # Mnemonic and genesis output (generated)
├── genesis-data/            # Copied from qrl-infra root
│   ├── jwt.hex
│   ├── genesis.json
│   ├── genesis.ssz
│   ├── config.yml
│   ├── node-0/keystores/
│   └── node-1/keystores/
└── build/                   # Copied from qrl-infra root
    ├── gqrl
    ├── beacon-chain
    └── validator
```

## Ports

| Port | Protocol | Service |
|------|----------|---------|
| 30303 | TCP+UDP | gqrl P2P |
| 13000 | TCP | beacon libp2p |
| 12000 | UDP | beacon discovery |
| 8545 | TCP | gqrl RPC (optional, for debugging) |
| 3500 | TCP | beacon API (optional, for debugging) |
| 4000 | TCP | beacon gRPC (localhost only, for validator) |

## Stopping the Testnet

```bash
./scripts/stop-all.sh nodes.txt
```

## Restarting with New Genesis

```bash
# Stop everything
./scripts/stop-all.sh nodes.txt

# Clean data on all nodes
for node in $(grep -v '^#' nodes.txt); do
  ssh "$node" "sudo rm -rf /data/execution /data/beacon /data/validator/wallet"
done

# Relaunch
./scripts/launch-testnet.sh nodes.txt 512 600

# Or reuse existing validator keys:
REUSE_KEYS=true ./scripts/launch-testnet.sh nodes.txt 512 600
```
