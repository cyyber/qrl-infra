output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_id" {
  value = aws_subnet.main.id
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

output "ami_id" {
  value = local.ami
}

output "node_public_ips" {
  value = aws_instance.node[*].public_ip
}

output "node_private_ips" {
  value = aws_instance.node[*].private_ip
}

output "node_instances" {
  description = "Node instance details with region annotation"
  value = [
    for i, inst in aws_instance.node : {
      public_ip  = inst.public_ip
      private_ip = inst.private_ip
      region     = var.region
    }
  ]
}
