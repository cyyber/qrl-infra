variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Environment name (stresstest, testnet, mainnet)"
  type        = string
  default     = "stresstest"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
}

variable "node_count" {
  description = "Number of nodes (each runs execution + beacon + validator)"
  type        = number
  default     = 2
}

variable "spammer_node_count" {
  description = "Number of transaction spammer nodes"
  type        = number
  default     = 5
}

variable "node_instance_type" {
  description = "EC2 instance type for nodes (runs execution + beacon + validator)"
  type        = string
  default     = "m5.2xlarge"
}

variable "spammer_instance_type" {
  description = "EC2 instance type for spammer nodes"
  type        = string
  default     = "t3.medium"
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for monitoring node"
  type        = string
  default     = "m5.large"
}

variable "ebs_volume_size" {
  description = "EBS volume size in GB for chain data"
  type        = number
  default     = 100
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04). Leave empty to auto-select latest."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "deploy_mode" {
  description = "Deployment mode: docker or binary"
  type        = string
  default     = "docker"

  validation {
    condition     = contains(["docker", "binary"], var.deploy_mode)
    error_message = "deploy_mode must be 'docker' or 'binary'."
  }
}