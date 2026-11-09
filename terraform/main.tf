locals {
  name = "${var.project_name}-${var.environment}"
  upstream_image_names = toset([
    for match in regexall("(?m)^\\s*- image:\\s*([A-Za-z0-9_-]+)", file("${path.root}/../application/upstream/skaffold.yaml")) : match[0]
  ])
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
  source      = "./modules/ecr"
  name        = local.name
  image_names = local.upstream_image_names
  tags        = var.tags
}

module "eks" {
  source                  = "./modules/eks"
  name                    = local.name
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  tags                    = var.tags
  cluster_version         = var.eks_cluster_version
  public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  node_instance_type      = var.eks_node_instance_type
  cluster_access_role_arn = aws_iam_role.codebuild_deployer.arn
}

module "github_oidc" {
  source                = "./modules/github_oidc"
  name                  = local.name
  github_owner          = var.github_owner
  github_owner_id       = var.github_owner_id
  github_repository     = var.github_repository
  github_repository_id  = var.github_repository_id
  ecr_repository_arns   = concat([module.ecr.repository_arn], values(module.ecr.image_repository_arns))
  eks_cluster_arn       = module.eks.cluster_arn
  codebuild_project_arn = aws_codebuild_project.deploy.arn
  tags                  = var.tags
}

module "aws_load_balancer_controller" {
  source            = "./modules/aws_load_balancer_controller"
  name              = local.name
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  tags              = var.tags
}

output "ecr_repository_url" { value = module.ecr.repository_url }
output "ecr_default_repo" { value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name}" }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_arn" { value = module.eks.cluster_arn }
output "aws_load_balancer_controller_role_arn" { value = module.aws_load_balancer_controller.role_arn }
output "vpc_id" { value = module.networking.vpc_id }
output "public_subnet_ids" { value = module.networking.public_subnet_ids }
output "private_subnet_ids" { value = module.networking.private_subnet_ids }
output "public_route_table_ids" { value = module.networking.public_route_table_ids }
output "private_route_table_ids" { value = module.networking.private_route_table_ids }
output "nat_gateway_ids" { value = module.networking.nat_gateway_ids }
output "codebuild_deploy_project_name" { value = aws_codebuild_project.deploy.name }
