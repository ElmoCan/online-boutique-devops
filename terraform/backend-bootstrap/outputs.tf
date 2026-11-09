output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "Bucket name to place in the separately reviewed S3 backend configuration."
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "Limit backend IAM access to this bucket and the project state key."
}
