output "s3_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "node_ips" {
  description = "All node public IPs across all regions"
  value       = local.all_node_public_ips
}

output "node_private_ips" {
  description = "All node private IPs across all regions"
  value       = local.all_node_private_ips
}

output "spammer_ips" {
  value = aws_instance.spammer[*].public_ip
}

output "monitoring_ip" {
  value = aws_instance.monitoring.public_ip
}

output "regions" {
  description = "Active regions and their node counts"
  value       = local.region_node_counts
}

# -------------------------------------------------------
# Generate Ansible inventory from Terraform outputs
# -------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content  = templatefile("${path.module}/templates/inventory.tpl", {
    node_hosts               = local.all_node_instances
    spammer_hosts            = aws_instance.spammer
    monitoring_host          = aws_instance.monitoring
    primary_node_private_ips = local.primary_node_private_ips
    spammer_to_node          = local.spammer_to_node
    deploy_mode              = var.deploy_mode
  })
}
