variable "name" { type = string }
variable "cluster_name" { type = string }
variable "oidc_provider_arn" { type = string }
variable "tags" { type = map(string) }

data "aws_iam_openid_connect_provider" "eks" {
  arn = var.oidc_provider_arn
}

locals {
  oidc_issuer             = replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")
  service_account_subject = "system:serviceaccount:kube-system:aws-load-balancer-controller"
}

resource "aws_iam_role" "controller" {
  name = "${var.name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = local.service_account_subject
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "controller" {
  name        = "${var.name}-aws-lbc-v3-6-2"
  description = "AWS Load Balancer Controller v3.6.2 policy for cluster ${var.cluster_name}."
  policy      = file("${path.module}/iam-policy-v3.6.2.json")
  tags        = var.tags
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}

output "role_arn" {
  value = aws_iam_role.controller.arn
}
