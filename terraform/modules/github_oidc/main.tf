variable "name" { type = string }
variable "github_owner" { type = string }
variable "github_owner_id" { type = string }
variable "github_repository" { type = string }
variable "github_repository_id" { type = string }
variable "ecr_repository_arns" { type = list(string) }
variable "eks_cluster_arn" { type = string }
variable "codebuild_project_arn" { type = string }
variable "tags" { type = map(string) }

locals {
  # GitHub's immutable default sub format includes owner/repo names and IDs.
  github_actions_oidc_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repository}@${var.github_repository_id}:ref:refs/heads/main"
}

# Register GitHub's OIDC issuer once per AWS account. Import/reuse an existing
# provider instead of creating a duplicate when one is already present.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # AWS handles current thumbprint validation for the issuer. Verify this
  # behavior against the selected AWS provider/API version before deployment.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

resource "aws_iam_role" "github_actions" {
  name = "${var.name}-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow", Principal = { Federated = aws_iam_openid_connect_provider.github.arn },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub" = local.github_actions_oidc_subject
      } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_policy" "github_deploy" {
  name = "${var.name}-github-deploy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arns },
      { Effect = "Allow", Action = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"], Resource = var.codebuild_project_arn }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_deploy.arn
}

output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
