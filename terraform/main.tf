locals {
  name = "${var.project_name}-${var.environment}"
}

module "networking" {
  source             = "./modules/networking"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  nat_gateway_mode   = var.nat_gateway_mode
  tags               = var.tags
}

module "ecr" {
  source = "./modules/ecr"
  name   = local.name
  tags   = var.tags
}

module "eks" {
  source              = "./modules/eks"
  name                = local.name
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  tags                = var.tags
  cluster_version     = var.eks_cluster_version
  public_access_cidrs = var.cluster_endpoint_public_access_cidrs
}

module "github_oidc" {
  source             = "./modules/github_oidc"
  name               = local.name
  github_owner       = var.github_owner
  github_repository  = var.github_repository
  ecr_repository_arn = module.ecr.repository_arn
  eks_cluster_name   = module.eks.cluster_name
  tags               = var.tags
}

output "ecr_repository_url" { value = module.ecr.repository_url }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.networking.vpc_id }
output "public_subnet_ids" { value = module.networking.public_subnet_ids }
output "private_subnet_ids" { value = module.networking.private_subnet_ids }
output "public_route_table_ids" { value = module.networking.public_route_table_ids }
output "private_route_table_ids" { value = module.networking.private_route_table_ids }
output "nat_gateway_ids" { value = module.networking.nat_gateway_ids }
