variable "aws_region" {
  description = "AWS region; Mumbai is ap-south-1."
  type        = string
  default     = "ap-south-1"
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
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  type        = number
  description = "Number of AZs. Production baseline uses three."
  default     = 3
  validation {
    condition     = var.availability_zones >= 2 && var.availability_zones <= 3
    error_message = "Use two or three Availability Zones."
  }
}

variable "eks_cluster_version" {
  type        = string
  description = "EKS Kubernetes version selected after checking AWS support and application compatibility. Required to avoid a stale version default."
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
  default     = "REPLACE_ME"
}

variable "github_repository" {
  type        = string
  description = "Exact GitHub repository allowed to assume the CI role. Set before deployment."
  default     = "REPLACE_ME"
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "online-boutique"
    ManagedBy = "terraform"
  }
}
