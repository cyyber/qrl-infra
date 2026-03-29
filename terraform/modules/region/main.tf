# -------------------------------------------------------
# Per-region infrastructure: VPC, SG, EC2 nodes, EBS
# -------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -------------------------------------------------------
# AMI lookup (AMI IDs are region-specific)
# -------------------------------------------------------
data "aws_ami" "ubuntu" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami      = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
  vpc_cidr = "10.${var.region_index}.0.0/16"
}

# -------------------------------------------------------
# SSH Key (import into this region)
# -------------------------------------------------------
resource "aws_key_pair" "deployer" {
  count      = var.ssh_public_key_material != "" ? 1 : 0
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key_material
  tags       = var.common_tags
}

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-vpc" })
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(local.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags                    = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-subnet" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-igw" })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-rt" })
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# -------------------------------------------------------
# Security Group: QRL Node
# -------------------------------------------------------
resource "aws_security_group" "node" {
  name_prefix = "qrl-${var.environment}-node-"
  vpc_id      = aws_vpc.main.id
  description = "QRL node (execution + beacon + validator)"

  # Execution P2P
  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Execution HTTP RPC
  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Execution Metrics
  ingress {
    from_port   = 6060
    to_port     = 6060
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Beacon libp2p
  ingress {
    from_port   = 13000
    to_port     = 13000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Beacon discv5
  ingress {
    from_port   = 12000
    to_port     = 12000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Beacon API / gRPC gateway
  ingress {
    from_port   = 3500
    to_port     = 3500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Beacon Monitoring
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Validator Monitoring
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-node-sg" })
}

# -------------------------------------------------------
# EC2 Instances: QRL Nodes
# -------------------------------------------------------
resource "aws_instance" "node" {
  count                  = var.node_count
  ami                    = local.ami
  instance_type          = var.node_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = var.iam_instance_profile_name

  user_data = templatefile("${path.module}/../../templates/cloud-init.sh", {
    role      = "node"
    s3_bucket = var.s3_bucket_id
    data_dir  = "/data"
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(var.common_tags, {
    Name   = "qrl-${var.environment}-${var.region}-node-${count.index}"
    Role   = "node"
    Region = var.region
  })

  depends_on = [aws_key_pair.deployer]
}

resource "aws_ebs_volume" "node_data" {
  count             = var.node_count
  availability_zone = aws_subnet.main.availability_zone
  size              = var.ebs_volume_size
  type              = "gp3"
  tags              = merge(var.common_tags, { Name = "qrl-${var.environment}-${var.region}-node-data-${count.index}" })
}

resource "aws_volume_attachment" "node_data" {
  count       = var.node_count
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.node_data[count.index].id
  instance_id = aws_instance.node[count.index].id
}
