output "vpc_id" {
  value = aws_vpc.main.id
}

output "s3_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "node_ips" {
  value = aws_instance.node[*].public_ip
}

output "node_private_ips" {
  value = aws_instance.node[*].private_ip
}

output "spammer_ips" {
  value = aws_instance.spammer[*].public_ip
}

output "monitoring_ip" {
  value = aws_instance.monitoring.public_ip
}

# -------------------------------------------------------
# Generate Ansible inventory from Terraform outputs
# -------------------------------------------------------
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content  = templatefile("${path.module}/templates/inventory.tpl", {
    node_hosts       = aws_instance.node
    spammer_hosts    = aws_instance.spammer
    monitoring_host  = aws_instance.monitoring
    node_private_ips = aws_instance.node[*].private_ip
    spammer_to_node  = local.spammer_to_node
    deploy_mode      = var.deploy_mode
  })
}