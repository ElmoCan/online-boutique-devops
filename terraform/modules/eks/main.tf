variable "name" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "tags" { type = map(string) }
variable "cluster_version" { type = string }
variable "public_access_cidrs" { type = list(string) }

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name                         = var.name
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs
  cluster_endpoint_private_access      = true
  vpc_id                               = var.vpc_id
  subnet_ids                           = var.private_subnet_ids

  enable_irsa = true
  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.large"]
      subnet_ids     = var.private_subnet_ids
      network_interfaces = [{
        associate_public_ip_address = false
      }]
      min_size      = 3
      desired_size  = 3
      max_size      = 6
      capacity_type = "ON_DEMAND"
      labels        = { workload = "general" }
    }
  }
  tags = var.tags
}

output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
