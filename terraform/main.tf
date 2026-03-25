# -------------------------------------------------------
# Data: latest Ubuntu 22.04 AMI
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
  ami = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu[0].id
}

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "qrl-${var.environment}-vpc" })
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags                    = merge(local.common_tags, { Name = "qrl-${var.environment}-subnet" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "qrl-${var.environment}-igw" })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "qrl-${var.environment}-rt" })
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# -------------------------------------------------------
# S3 bucket for genesis artifacts and binaries
# -------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "qrl-${var.environment}-artifacts-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags          = local.common_tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# -------------------------------------------------------
# IAM role for EC2 instances to read S3
# -------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "qrl-${var.environment}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "node_s3" {
  name = "qrl-${var.environment}-s3-read"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "qrl-${var.environment}-node-profile"
  role = aws_iam_role.node.name
}

# -------------------------------------------------------
# Security Group: QRL Node (execution + beacon + validator)
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

  # Execution HTTP RPC (VPC only)
  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Execution Auth/Engine API (localhost only, same machine)
  # No ingress needed — beacon connects via 127.0.0.1

  # Execution Metrics (VPC only)
  ingress {
    from_port   = 6060
    to_port     = 6060
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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

  # Beacon API / gRPC gateway (VPC only)
  ingress {
    from_port   = 3500
    to_port     = 3500
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Beacon gRPC (localhost only for validator, no ingress needed)

  # Beacon Monitoring (VPC only)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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

  tags = merge(local.common_tags, { Name = "qrl-${var.environment}-node-sg" })
}

# -------------------------------------------------------
# Security Group: Spammer
# -------------------------------------------------------
resource "aws_security_group" "spammer" {
  name_prefix = "qrl-${var.environment}-spammer-"
  vpc_id      = aws_vpc.main.id
  description = "Transaction spammer nodes"

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

  tags = merge(local.common_tags, { Name = "qrl-${var.environment}-spammer-sg" })
}

# -------------------------------------------------------
# Security Group: Monitoring
# -------------------------------------------------------
resource "aws_security_group" "monitoring" {
  name_prefix = "qrl-${var.environment}-monitoring-"
  vpc_id      = aws_vpc.main.id
  description = "Monitoring stack (Prometheus + Grafana)"

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  tags = merge(local.common_tags, { Name = "qrl-${var.environment}-monitoring-sg" })
}

# -------------------------------------------------------
# EC2 Instances: QRL Nodes (execution + beacon + validator)
# -------------------------------------------------------
resource "aws_instance" "node" {
  count                  = var.node_count
  ami                    = local.ami
  instance_type          = var.node_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/cloud-init.sh", {
    role      = "node"
    s3_bucket = aws_s3_bucket.artifacts.id
    data_dir  = "/data"
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "qrl-${var.environment}-node-${count.index}"
    Role = "node"
  })
}

resource "aws_ebs_volume" "node_data" {
  count             = var.node_count
  availability_zone = aws_subnet.main.availability_zone
  size              = var.ebs_volume_size
  type              = "gp3"
  tags              = merge(local.common_tags, { Name = "qrl-${var.environment}-node-data-${count.index}" })
}

resource "aws_volume_attachment" "node_data" {
  count       = var.node_count
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.node_data[count.index].id
  instance_id = aws_instance.node[count.index].id
}

# -------------------------------------------------------
# EC2 Instances: Spammer Nodes
# -------------------------------------------------------
resource "aws_instance" "spammer" {
  count                  = var.spammer_node_count
  ami                    = local.ami
  instance_type          = var.spammer_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.spammer.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/cloud-init.sh", {
    role      = "spammer"
    s3_bucket = aws_s3_bucket.artifacts.id
    data_dir  = "/data"
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "qrl-${var.environment}-spammer-${count.index}"
    Role = "spammer"
  })
}

# -------------------------------------------------------
# EC2 Instance: Monitoring
# -------------------------------------------------------
resource "aws_instance" "monitoring" {
  ami                    = local.ami
  instance_type          = var.monitoring_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/cloud-init.sh", {
    role      = "monitoring"
    s3_bucket = aws_s3_bucket.artifacts.id
    data_dir  = "/data"
  })

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "qrl-${var.environment}-monitoring"
    Role = "monitoring"
  })
}