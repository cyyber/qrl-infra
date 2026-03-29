# QRL Infrastructure Configuration
# Edit these values and run: terraform apply

# -------------------------------------------------------
# Regions: uncomment to deploy nodes across multiple regions.
# First region is primary (hosts S3, IAM, monitoring, spammer).
# Nodes are auto-distributed equally across all listed regions.
# -------------------------------------------------------
regions = [
  "eu-north-1",
  # "us-east-1",
  # "us-west-2",
  # "ap-southeast-1",
  # "ap-northeast-1",
  # "eu-west-1",
  # "eu-central-1",
  # "us-east-2",
  # "ap-south-1",
  # "sa-east-1",
]

# -------------------------------------------------------
# SSH: key must exist in each region, or set ssh_public_key_path
# to auto-import it.
# -------------------------------------------------------
# ssh_key_name        = "your-key-name"
# ssh_public_key_path = "~/.ssh/id_rsa.pub"

# -------------------------------------------------------
# Nodes
# -------------------------------------------------------
node_count         = 2
node_instance_type = "m5.2xlarge"
ebs_volume_size    = 100
deploy_mode        = "binary"

# -------------------------------------------------------
# Spammer (deployed in primary region only)
# -------------------------------------------------------
spammer_node_count    = 1
spammer_instance_type = "t3.medium"

# -------------------------------------------------------
# Monitoring (deployed in primary region only)
# -------------------------------------------------------
monitoring_instance_type = "m5.large"

environment = "stresstest"
