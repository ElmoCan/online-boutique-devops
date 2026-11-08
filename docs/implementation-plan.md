# Online Boutique AWS implementation plan

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
5. Produce a reviewed cost estimate in AWS Pricing Calculator using `ap-south-1` rates, expected NAT bytes, EBS, logs, public IPv4, ALB LCUs, data transfer, taxes, and environment uptime.

## Phase 2 — explicit approval gate

Present the final Terraform plan, cost estimate, risk notes, and resource list for user approval. No infrastructure creation before approval.

## Phase 3 — infrastructure and platform

After approval: establish remote state and locking; deploy network, ECR, EKS and IAM; configure restricted EKS access; install AWS Load Balancer Controller; verify ALB discovery; configure TLS/WAF if approved; install Prometheus/Grafana with auth and persistence; add budgets and alarms.

## Phase 4 — CI/CD and application

After GitHub repository/branch/environment are known: configure GitHub Actions OIDC; build and scan images; push immutable SHA tags to ECR; deploy via Helm/Kustomize; implement rolling rollback, health checks, and smoke checks; run baseline and load-generator tests.

## Phase 5 — operations and handoff

Document SLOs, dashboard/alerts, incident steps, patch/upgrade cadence, image retention, backup/restore, cost review, and teardown procedure. Confirm production readiness gaps and ownership.

## Current blockers and approvals needed

- **Target repository:** `ElmoCan/online-boutique-devops` is public and accessible with admin/push permission. Its only pre-existing file is `README.md`; leave it unchanged. Proposed docs and infrastructure scaffolding go on `milestone-1/architecture-and-plan`.

- **Local clone:** read-only GitHub file/tree reads work and upstream was inspected at commit `c7cb6d5bfd6ea3aed768634ebbcb98cb7a523712`. `git clone` still fails because `github.com` does not resolve from this shell.
- **Docker:** CLI is installed, but the selected OrbStack daemon socket `/Users/yusufchoudhari/.orbstack/run/docker.sock` is missing. Start the daemon and retry; local builds are unverified.
- **AWS connectivity:** read-only `sts:GetCallerIdentity` at `ap-south-1` could not reach `sts.ap-south-1.amazonaws.com`; account identity and AWS authentication are unverified. Configured CLI region remains `us-east-1`; it was not changed. AWS config was not modified.
- **Approval still required before any resource creation:** approve final architecture, NAT policy, CIDR, node shape/count, exposure/TLS controls, budget ceiling, and exact Terraform plan. No apply has been run.
