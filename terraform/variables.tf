variable "regions" {
  description = "List of AWS regions to deploy nodes into. First region is primary (hosts S3, IAM, monitoring, spammer)."
  type        = list(string)
  default     = ["eu-north-1"]

  validation {
    condition = alltrue([
      for r in var.regions : contains([
        "eu-north-1", "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-central-1", "ap-southeast-1", "ap-southeast-2",
        "ap-northeast-1", "ap-south-1", "sa-east-1",
      ], r)
    ])
    error_message = "Each region must be one of: eu-north-1, us-east-1, us-east-2, us-west-1, us-west-2, eu-west-1, eu-central-1, ap-southeast-1, ap-southeast-2, ap-northeast-1, ap-south-1, sa-east-1."
  }
}

variable "environment" {
  description = "Environment name (stresstest, testnet, mainnet)"
  type        = string
  default     = "stresstest"
}

variable "ssh_key_name" {
  description = "Name to register the EC2 key pair under. Auto-generated from environment if not set."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for importing into all regions. Leave empty to use existing key_name in each region."
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Total number of nodes. Auto-distributed equally across regions."
  type        = number
  default     = 2
}

variable "spammer_node_count" {
  description = "Number of transaction spammer nodes (deployed in primary region)"
  type        = number
  default     = 1
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

variable "deploy_mode" {
  description = "Deployment mode: docker or binary"
  type        = string
  default     = "binary"

  validation {
    condition     = contains(["docker", "binary"], var.deploy_mode)
    error_message = "deploy_mode must be 'docker' or 'binary'."
  }
}
