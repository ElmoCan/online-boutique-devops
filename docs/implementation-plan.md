# Online Boutique implementation roadmap

> **Progress note (2026-11-08):** This roadmap began as an AWS-only plan. The project later completed local OrbStack application and monitoring work, then resumed AWS read-only inspection and VPC Terraform preparation in `us-east-1`. The current history, solved issues, branch/PR status, and remaining work are tracked in the [project journal](project-journal.md). Milestone instructions and current configuration in the VPC plan and Terraform README supersede older assumptions in this initial roadmap.

## Phase 0 — environment and source baseline

1. Restore outbound DNS/network access to GitHub; clone upstream into `work/microservices-demo/` at reviewed commit `c7cb6d5bfd6ea3aed768634ebbcb98cb7a523712` or a tagged release.
2. Record commit, license, README/development guide, service inventory, image build contexts, Dockerfiles, ports, health checks, dependencies, resource requests, and external network calls.
3. Review `release/kubernetes-manifests.yaml`, `kubernetes-manifests/`, `helm-chart/`, `kustomize/`, `istio-manifests/`, `terraform/`, and Skaffold/CI files. Keep source tree unmodified; place AWS adaptations in the separate implementation workspace.
4. Start the Docker daemon (OrbStack currently selected but its socket is absent); verify `docker info`, then build a representative image and the full image set locally. Record build time, architecture, disk use, and any cross-platform image requirements.
5. Re-run read-only AWS identity and region checks when the STS endpoint is reachable. Confirm account, quotas, EKS versions, AZs, ACM/DNS ownership, and existing GitHub OIDC provider without changing account state.

**Exit criteria:** local source clone and Docker build report checked in; AWS account/region confirmed; architecture and monthly budget approved.

## Phase 1 — design and Terraform preparation (current)

1. Agree VPC CIDR, 2-vs-3 AZ policy, NAT count, endpoint strategy, node sizing, API endpoint CIDRs, domain/TLS, observability retention, and teardown policy.
2. Review `outputs/online-boutique-devops/terraform/`; fill GitHub trust values and EKS version only after repo/default branch and release compatibility are known.
3. Add AWS Load Balancer Controller IAM policy/Helm release, monitoring chart configuration, namespace-scoped EKS access entries for the CI role, storage, encryption, security groups, budgets/alerts, and state backend design.
4. Perform static review and `terraform fmt`, `init`, `validate`, and `plan` only after approval to prepare/check a plan. These commands do not create resources; do not run `apply` without explicit approval.
5. Produce a reviewed cost estimate in AWS Pricing Calculator using `us-east-1` rates, expected NAT bytes, EBS, logs, public IPv4, ALB LCUs, data transfer, taxes, and environment uptime. The current network-only NAT estimate is in the VPC plan; whole-platform pricing remains future work.

## Phase 2 — explicit approval gate

Present the final Terraform plan, cost estimate, risk notes, and resource list for user approval. No infrastructure creation before approval.

## Phase 3 — infrastructure and platform

After approval: establish remote state and locking; deploy network, ECR, EKS and IAM; configure restricted EKS access; install AWS Load Balancer Controller; verify ALB discovery; configure TLS/WAF if approved; install Prometheus/Grafana with auth and persistence; add budgets and alarms.

## Phase 4 — CI/CD and application

After GitHub repository/branch/environment are known: configure GitHub Actions OIDC; build and scan images; push immutable SHA tags to ECR; deploy via Helm/Kustomize; implement rolling rollback, health checks, and smoke checks; run baseline and load-generator tests.

## Phase 5 — operations and handoff

Document SLOs, dashboard/alerts, incident steps, patch/upgrade cadence, image retention, backup/restore, cost review, and teardown procedure. Confirm production readiness gaps and ownership.

## Current status and approvals needed

- **Repository and PRs:** PR #1 (initial architecture and Terraform scaffold) is merged. PR #2 (local Prometheus/Grafana) is open. PR #3 now contains the AWS VPC plan and Terraform preparation and is open. See the [project journal](project-journal.md) for current branch heads and scope.
- **Upstream and local application:** upstream commit `c7cb6d5bfd6ea3aed768634ebbcb98cb7a523712` is pinned in the local Kubernetes branch. OrbStack Docker access was verified; the owner later reported the Kubernetes API healthy and the application running. Recheck the cluster before resuming local operations.
- **Monitoring:** local monitoring configuration documents kube-prometheus-stack `93.1.0`, dashboards, and actual metrics limitations. The owner-provided Grafana password is stored only in the Kubernetes Secret and is not in Git.
- **AWS:** read-only identity, networking, quota, and permission inspection succeeded for `us-east-1`. No AWS configuration or resources were changed.
- **Terraform:** `terraform init -backend=false`, formatting, validation, and a scoped, refresh-disabled networking plan succeeded. The default NAT mode is disabled. The plan showed no NAT Gateway or Elastic IP and no changes to the existing default VPC. No `terraform apply` has run.
- **Still requires review/approval before provisioning:** validate CIDR overlap with networks outside the inspected AWS account, decide whether/when to enable NAT, agree on AZ selection and full-platform costs, design shared remote state, finish EKS/IAM/CI security review, and review a complete plan. Cloud resource creation remains a separate approval step.
