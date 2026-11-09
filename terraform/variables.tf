variable "aws_region" {
  description = "AWS region for the project."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short project identifier used in resource names."
  default     = "online-boutique"
}

variable "environment" {
  type        = string
  description = "Environment name."
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 range. Must not overlap connected networks."
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  type        = number
  description = "Number of Availability Zones for the VPC. This implementation uses two."
  default     = 2
  validation {
    condition     = var.availability_zones == 2
    error_message = "This VPC implementation requires exactly two Availability Zones."
  }
}

variable "nat_gateway_mode" {
  type        = string
  description = "Private subnet egress mode: disabled, single NAT Gateway, or one NAT Gateway per AZ."
  default     = "disabled"
  validation {
    condition     = contains(["disabled", "single", "per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode must be disabled, single, or per_az."
  }
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version selected after checking AWS support and application compatibility. Required to avoid a stale version default."
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for private EKS worker nodes. c7i-flex.large was previously verified in this account."
  type        = string
  default     = "c7i-flex.large"
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "Trusted IPv4 CIDRs allowed to reach the public EKS API endpoint. Do not use 0.0.0.0/0."
  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide one or more trusted CIDRs and do not expose the EKS API to the entire internet."
  }
}

variable "github_owner" {
  type        = string
  description = "GitHub owner or organization allowed to assume the CI role. Set before deployment."
  default     = "ElmoCan"
}

variable "github_owner_id" {
  type        = string
  description = "Immutable GitHub numeric owner ID used in GitHub OIDC subject claims."
  default     = "135598223"
}

variable "github_repository" {
  type        = string
  description = "Exact GitHub repository allowed to assume the CI role. Set before deployment."
  default     = "online-boutique-devops"
}

variable "github_repository_id" {
  type        = string
  description = "Immutable GitHub numeric repository ID used in GitHub OIDC subject claims."
  default     = "1450199615"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}
