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
# IAM role for EC2 instances to read S3 (global)
# -------------------------------------------------------
resource "aws_iam_role" "node" {
  name = "qrl-${var.environment}-node-role-${random_id.bucket_suffix.hex}"

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
  name = "qrl-${var.environment}-s3-read-${random_id.bucket_suffix.hex}"
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
  name = "qrl-${var.environment}-node-profile-${random_id.bucket_suffix.hex}"
  role = aws_iam_role.node.name
}

# -------------------------------------------------------
# Region modules: one per supported region
# Each is enabled only if the region is in var.regions
# -------------------------------------------------------

module "region_eu_north_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "eu-north-1") ? 1 : 0
  providers = { aws = aws.eu_north_1 }

  region                    = "eu-north-1"
  region_index              = index(var.regions, "eu-north-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "eu-north-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_us_east_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "us-east-1") ? 1 : 0
  providers = { aws = aws.us_east_1 }

  region                    = "us-east-1"
  region_index              = index(var.regions, "us-east-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "us-east-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_us_east_2" {
  source    = "./modules/region"
  count     = contains(var.regions, "us-east-2") ? 1 : 0
  providers = { aws = aws.us_east_2 }

  region                    = "us-east-2"
  region_index              = index(var.regions, "us-east-2")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "us-east-2", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_us_west_2" {
  source    = "./modules/region"
  count     = contains(var.regions, "us-west-2") ? 1 : 0
  providers = { aws = aws.us_west_2 }

  region                    = "us-west-2"
  region_index              = index(var.regions, "us-west-2")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "us-west-2", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_eu_west_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "eu-west-1") ? 1 : 0
  providers = { aws = aws.eu_west_1 }

  region                    = "eu-west-1"
  region_index              = index(var.regions, "eu-west-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "eu-west-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_eu_central_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "eu-central-1") ? 1 : 0
  providers = { aws = aws.eu_central_1 }

  region                    = "eu-central-1"
  region_index              = index(var.regions, "eu-central-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "eu-central-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_ap_southeast_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "ap-southeast-1") ? 1 : 0
  providers = { aws = aws.ap_southeast_1 }

  region                    = "ap-southeast-1"
  region_index              = index(var.regions, "ap-southeast-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "ap-southeast-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_ap_northeast_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "ap-northeast-1") ? 1 : 0
  providers = { aws = aws.ap_northeast_1 }

  region                    = "ap-northeast-1"
  region_index              = index(var.regions, "ap-northeast-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "ap-northeast-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_ap_south_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "ap-south-1") ? 1 : 0
  providers = { aws = aws.ap_south_1 }

  region                    = "ap-south-1"
  region_index              = index(var.regions, "ap-south-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "ap-south-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

module "region_sa_east_1" {
  source    = "./modules/region"
  count     = contains(var.regions, "sa-east-1") ? 1 : 0
  providers = { aws = aws.sa_east_1 }

  region                    = "sa-east-1"
  region_index              = index(var.regions, "sa-east-1")
  environment               = var.environment
  node_count                = lookup(local.region_node_counts, "sa-east-1", 0)
  node_instance_type        = var.node_instance_type
  ebs_volume_size           = var.ebs_volume_size
  ssh_key_name              = var.ssh_key_name
  ssh_public_key_material   = local.ssh_public_key_material
  iam_instance_profile_name = aws_iam_instance_profile.node.name
  s3_bucket_id              = aws_s3_bucket.artifacts.id
  common_tags               = local.common_tags
  deploy_mode               = var.deploy_mode
}

# -------------------------------------------------------
# Primary region: Spammer
# -------------------------------------------------------
resource "aws_security_group" "spammer" {
  name_prefix = "qrl-${var.environment}-spammer-"
  vpc_id      = local.primary.vpc_id
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

resource "aws_instance" "spammer" {
  count                  = var.spammer_node_count
  ami                    = local.primary.ami_id
  instance_type          = var.spammer_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = local.primary.subnet_id
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
# Primary region: Monitoring
# -------------------------------------------------------
resource "aws_security_group" "monitoring" {
  name_prefix = "qrl-${var.environment}-monitoring-"
  vpc_id      = local.primary.vpc_id
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

resource "aws_instance" "monitoring" {
  ami                    = local.primary.ami_id
  instance_type          = var.monitoring_instance_type
  key_name               = var.ssh_key_name
  subnet_id              = local.primary.subnet_id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/cloud-init.sh", {
    role      = "monitoring"
    s3_bucket = aws_s3_bucket.artifacts.id
    data_dir  = "/data"
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.common_tags, {
    Name = "qrl-${var.environment}-monitoring"
    Role = "monitoring"
  })
}
