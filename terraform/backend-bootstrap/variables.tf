variable "aws_region" {
  description = "Region containing the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name, supplied only during a separately approved bootstrap."
  type        = string
  nullable    = false
}

variable "tags" {
  type = map(string)
  default = {
    Project   = "online-boutique"
    ManagedBy = "terraform"
    Purpose   = "terraform-state"
  }
}
