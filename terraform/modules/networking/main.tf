variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = number }
variable "nat_gateway_mode" {
  type        = string
  description = "Private subnet egress mode: disabled, single, or per_az."
  validation {
    condition     = contains(["disabled", "single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be disabled, single, or per_az."
  }
}
variable "tags" { type = map(string) }

data "aws_availability_zones" "available" { state = "available" }

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zones)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # The third argument to cidrsubnet selects the /24 within the /16.
  public_subnets  = [for index in [1, 2] : cidrsubnet(var.vpc_cidr, 8, index)]
  private_subnets = [for index in [11, 12] : cidrsubnet(var.vpc_cidr, 8, index)]

  enable_nat_gateway      = var.nat_gateway_mode != "disabled"
  single_nat_gateway      = var.nat_gateway_mode == "single"
  one_nat_gateway_per_az  = var.nat_gateway_mode == "per_az"
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = false

  public_subnet_tags = {
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
  tags = var.tags
}

output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "private_subnet_arns" { value = module.vpc.private_subnet_arns }
output "public_subnet_ids" { value = module.vpc.public_subnets }
output "private_route_table_ids" { value = module.vpc.private_route_table_ids }
output "public_route_table_ids" { value = module.vpc.public_route_table_ids }
output "nat_gateway_ids" { value = module.vpc.natgw_ids }
