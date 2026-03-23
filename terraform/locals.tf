locals {
  # Assign spammers to nodes (round-robin)
  spammer_to_node = {
    for i in range(var.spammer_node_count) : i => i % var.node_count
  }

  common_tags = {
    Project     = "qrl-infra"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}