locals {
  # -------------------------------------------------------
  # Node distribution across regions
  # -------------------------------------------------------
  region_count = length(var.regions)
  base_count   = floor(var.node_count / local.region_count)
  remainder    = var.node_count % local.region_count

  # First `remainder` regions get base_count + 1, rest get base_count
  region_node_counts = {
    for idx, region in var.regions :
    region => local.base_count + (idx < local.remainder ? 1 : 0)
  }

  primary_region = var.regions[0]

  ssh_key_name            = var.ssh_key_name != "" ? var.ssh_key_name : "qrl-${var.environment}"
  ssh_public_key_material = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : ""

  common_tags = {
    Project     = "qrl-infra"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # -------------------------------------------------------
  # Aggregate outputs from all active region modules
  # -------------------------------------------------------
  region_outputs = {
    for region in var.regions : region => (
      region == "eu-north-1"      ? module.region_eu_north_1[0] :
      region == "us-east-1"       ? module.region_us_east_1[0] :
      region == "us-east-2"       ? module.region_us_east_2[0] :
      region == "us-west-1"       ? module.region_us_west_1[0] :
      region == "us-west-2"       ? module.region_us_west_2[0] :
      region == "eu-west-1"       ? module.region_eu_west_1[0] :
      region == "eu-central-1"    ? module.region_eu_central_1[0] :
      region == "ap-southeast-1"  ? module.region_ap_southeast_1[0] :
      region == "ap-southeast-2"  ? module.region_ap_southeast_2[0] :
      region == "ap-northeast-1"  ? module.region_ap_northeast_1[0] :
      region == "ap-south-1"      ? module.region_ap_south_1[0] :
      region == "sa-east-1"       ? module.region_sa_east_1[0] :
      null
    )
  }

  primary = local.region_outputs[local.primary_region]

  # All nodes across all regions (ordered by region, then index)
  all_node_instances = flatten([
    for region in var.regions : local.region_outputs[region].node_instances
  ])

  all_node_public_ips  = [for n in local.all_node_instances : n.public_ip]
  all_node_private_ips = [for n in local.all_node_instances : n.private_ip]

  # Spammer targets primary-region nodes (same VPC, can use private IPs)
  primary_node_private_ips = local.primary.node_private_ips
  primary_node_count       = local.region_node_counts[local.primary_region]

  spammer_to_node = {
    for i in range(var.spammer_node_count) : i => i % local.primary_node_count
  }
}
