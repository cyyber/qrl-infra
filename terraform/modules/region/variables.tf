variable "region" {
  description = "AWS region name"
  type        = string
}

variable "region_index" {
  description = "Index of this region in the regions list (for CIDR calculation)"
  type        = number
}

variable "environment" {
  type = string
}

variable "node_count" {
  description = "Number of nodes to deploy in this region"
  type        = number
}

variable "node_instance_type" {
  type    = string
  default = "m5.2xlarge"
}

variable "ebs_volume_size" {
  type    = number
  default = 100
}

variable "ssh_key_name" {
  type = string
}

variable "ssh_public_key_material" {
  description = "SSH public key content for importing into this region. Empty = key already exists."
  type        = string
  default     = ""
}

variable "iam_instance_profile_name" {
  type = string
}

variable "s3_bucket_id" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "ami_id" {
  description = "AMI ID override. Empty = auto-select Ubuntu 22.04."
  type        = string
  default     = ""
}

variable "deploy_mode" {
  type    = string
  default = "binary"
}
