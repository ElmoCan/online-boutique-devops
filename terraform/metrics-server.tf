# Metrics Server provides the resource metrics API required by Kubernetes HPA.
# Version compatibility was checked against EKS 1.36 via describe-addon-versions.
resource "aws_eks_addon" "metrics_server" {
  cluster_name  = module.eks.cluster_name
  addon_name    = "metrics-server"
  addon_version = var.metrics_server_addon_version

  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = var.tags
}
