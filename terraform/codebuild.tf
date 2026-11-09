resource "aws_security_group" "codebuild_deployer" {
  name        = "${local.name}-codebuild-deployer"
  description = "Network access for the private Kubernetes deploy runner."
  vpc_id      = module.networking.vpc_id
  tags        = var.tags

  egress {
    description = "Reach the private EKS endpoint and required AWS services through NAT."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "codebuild_to_eks_api" {
  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = aws_security_group.codebuild_deployer.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Private CodeBuild deploy runner to EKS Kubernetes API."
  tags                         = var.tags
}

resource "aws_iam_role" "codebuild_deployer" {
  name = "${local.name}-codebuild-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild_deployer" {
  name = "${local.name}-codebuild-deployer"
  role = aws_iam_role.codebuild_deployer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = aws_cloudwatch_log_group.codebuild_deployer.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeDhcpOptions", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterfacePermission"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*"
        Condition = {
          StringEquals = { "ec2:AuthorizedService" = "codebuild.amazonaws.com" }
          ArnEquals    = { "ec2:Subnet" = module.networking.private_subnet_arns }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "codebuild_deployer" {
  name              = "/aws/codebuild/${local.name}-deploy"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_codebuild_project" "deploy" {
  name           = "${local.name}-deploy"
  description    = "Deploy the reviewed Online Boutique manifests into the private EKS cluster."
  service_role   = aws_iam_role.codebuild_deployer.arn
  build_timeout  = 30
  queued_timeout = 30
  tags           = var.tags

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_owner}/${var.github_repository}.git"
    git_clone_depth = 1
    buildspec       = "ci/buildspec-deploy.yml"
  }

  source_version = "refs/heads/main"

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = module.eks.cluster_name
    }
    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = module.ecr.repository_url
    }
    environment_variable {
      name  = "ECR_REPOSITORY_PREFIX"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name}"
    }
  }

  vpc_config {
    vpc_id             = module.networking.vpc_id
    subnets            = module.networking.private_subnet_ids
    security_group_ids = [aws_security_group.codebuild_deployer.id]
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_deployer.name
      stream_name = "deployment"
    }
    s3_logs { status = "DISABLED" }
  }
}

output "codebuild_deployer_role_arn" { value = aws_iam_role.codebuild_deployer.arn }
