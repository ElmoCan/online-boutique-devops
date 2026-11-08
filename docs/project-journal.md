# Online Boutique DevOps project journal

**Last updated:** 2026-11-08

**Repository:** [`ElmoCan/online-boutique-devops`](https://github.com/ElmoCan/online-boutique-devops)
**Purpose:** Keep a chronological record of decisions, implementation, verification, blockers, and fixes. This journal distinguishes work committed in the repository from work reported by the project owner and from future plans.

## Project goal and working rules

Build a production-oriented DevOps implementation around Google's Online Boutique while keeping Google's source repository unchanged. The application source of truth is [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo); this repository holds project documentation and DevOps configuration.

The work has moved through two scopes:

1. **Local development:** run the upstream application on OrbStack Kubernetes, add local Prometheus/Grafana, and document the workflow.
2. **AWS preparation:** inspect AWS read-only, plan a VPC, and prepare Terraform without provisioning resources.

Safety decisions carried through the work:

- Do not modify Google's upstream source.
- Keep local and cloud configurations in the DevOps repository.
- Use OrbStack port-forwarding for local access; do not expose the local app or Grafana publicly.
- Do not perform AWS provisioning without a separate approval. No `terraform apply` has been run and no AWS resources have been created or modified.
- Do not store AWS credentials, Grafana passwords, or other secrets in Git.
- Keep the load generator off by default on the resource-constrained local ARM64 cluster.

## Timeline

### 1. Project and repository setup

- The project began with Google Online Boutique as the application workload and `ElmoCan/online-boutique-devops` as the separate DevOps repository.
- The initial AWS design work was framed around EKS, ECR, IAM, GitHub Actions OIDC, AWS Load Balancer Controller, and Prometheus/Grafana. Early architecture material used Mumbai (`ap-south-1`); the later AWS milestone explicitly changed the working region to N. Virginia (`us-east-1`). The current Terraform default is `us-east-1`.
- Initial architecture and implementation planning, including a Terraform scaffold, were committed to the repository. PR #1 was merged. The architecture and implementation plan remain useful as the broader roadmap, but the actual current VPC implementation is on the newer `feature/aws-vpc-networking` branch.

### 2. Upstream application inspection

- The upstream repository was inspected at commit `c7cb6d5bfd6ea3aed768634ebbcb98cb7a523712`; the local Kubernetes branch pins this commit as the `application/upstream` Git submodule.
- Inspection covered the microservice architecture, source tree, per-service Dockerfiles, release Kubernetes manifests, Skaffold, Kustomize, Helm, and Google Cloud-specific deployment material.
- Findings recorded in the architecture docs: services communicate primarily over gRPC; Redis backs the cart service; the release manifest is the appropriate prebuilt-image deployment path; the standard manifests are Skaffold build inputs; the Helm chart is marked experimental; and upstream Google Terraform/GKE configuration is not reusable as AWS infrastructure.
- Skaffold advertises multi-platform builds, but that does not guarantee every published release image has an ARM64 variant. The local deployment therefore favored upstream release images and local compatibility handling over recreating upstream code or maintaining custom Dockerfiles.

### 3. Local OrbStack environment and application deployment

- Local machine context: Apple Silicon MacBook with OrbStack, Docker, and a single-node local Kubernetes cluster. The Docker engine was reported as 29.4.0 on Linux/ARM64, with 8 CPUs and about 7.8 GiB available to the Docker VM. The active Docker/Kubernetes context is `orbstack`.
- Initial Docker inspection hit a sandbox restriction on the OrbStack socket. Read/connect access was granted for inspection; subsequent Docker checks worked. No existing containers, images, volumes, or contexts were deleted or changed as part of that check.
- Initially, `kubectl` could not connect because the OrbStack Kubernetes API refused the connection. The owner later enabled Kubernetes in OrbStack. Subsequent user-provided health checks reported Kubernetes 1.34.8+orb1, a Ready node, and system components including CoreDNS and Local Path Provisioner. OrbStack settings were not changed by the agent.
- Local deployment work was recorded in commit `2b9644f` on `milestone-2/local-kubernetes`. It uses upstream release manifests from the pinned submodule and a small root Kustomize overlay. The overlay sets namespace `online-boutique`, disables the optional load generator, uses `IfNotPresent` for locally loaded upstream images, and changes `frontend-external` to `ClusterIP` so access remains local through port-forwarding.
- The pinned upstream v0.10.7 app images were identified as Linux/AMD64 while OrbStack's node is ARM64. The project used upstream images with local AMD64 emulation rather than maintaining replacement application Dockerfiles. The product catalog image was verified running under OrbStack emulation. The load generator was disabled because synthetic load under emulation caused the cart service to miss its 1-second readiness probe.
- The intended local access path is `kubectl port-forward -n online-boutique svc/frontend 8080:80`, then `http://localhost:8080`. At the start of Milestone 3, the project owner reported that the application was running successfully. That owner-reported milestone is recorded here; consult the active OrbStack cluster for its current state.
- The Git worktree used for later AWS work contains an untracked `application/upstream` directory. It has been left untouched and unstaged on the AWS branch; the pinned submodule is recorded on the local Kubernetes branch.

### 4. Local monitoring

- Monitoring configuration was committed as `f09e715` on `feature/local-prometheus-grafana`; PR #2, “Add local Prometheus and Grafana monitoring,” is open and reported mergeable as of this journal update.
- The documented install uses the official `prometheus-community/kube-prometheus-stack` chart version **93.1.0**, in namespace `monitoring`, with single replicas, three-day Prometheus retention, conservative resource settings, and OrbStack `local-path` PVCs (Prometheus 5 GiB, Grafana 1 GiB, Alertmanager 1 GiB).
- Grafana is kept as a ClusterIP service and accessed with port-forwarding on `localhost:3000`. The admin password is held in a Kubernetes Secret; the password value is not stored in the repository.
- OrbStack-specific scrape overrides disable etcd, controller-manager, scheduler, and kube-proxy targets that are not exposed as normal targets by this single-node control plane. The documented active targets include the API server, CoreDNS, kubelet/cAdvisor, node exporter, kube-state-metrics, and monitoring stack.
- A local dashboard covers node/pod CPU and memory, restarts, deployment availability, namespace use, and container readiness. The monitoring docs report 13 Prometheus targets up.
- **Known limitation:** Online Boutique has OpenTelemetry tracing instrumentation but no verified Prometheus `/metrics` endpoint. No application ServiceMonitor is configured. The OrbStack kubelet/cAdvisor endpoint responds but does not expose `container_cpu_usage_seconds_total` or `container_memory_working_set_bytes`; pod/namespace actual-usage panels therefore lack data. Node metrics and kube-state metrics (such as restarts, readiness, and deployment availability) are available. OrbStack's Metrics API is unavailable, so `kubectl top` cannot be used.
- **ARM64 issue and workaround:** the pinned Prometheus Operator and config-reloader image versions were documented without ARM64 variants. A helper script imports those two pinned official images as AMD64 for OrbStack emulation; the remaining chart images use native ARM64 variants. This workaround is for local development.

### 5. AWS Milestone 1: read-only inspection and VPC plan

- AWS profile: `devops-practice`; project region: `us-east-1`. AWS CLI authentication and identity were checked without displaying access keys or session tokens. Read-only inventory and IAM permission simulation were performed; no AWS configuration was changed.
- The account inventory recorded one existing default VPC (`172.31.0.0/16`) with six `/20` subnets, an Internet Gateway, and no NAT Gateways or allocated Elastic IPs. The proposed `10.0.0.0/16` did not overlap the VPC/subnets inspected in that account and region. Corporate, VPN, peered, and other networks outside that inventory still need checking before deployment.
- Inspection found the current identity had broad permissions. The plan recommends using a dedicated, narrowly scoped role with short-lived credentials for future deployment rather than relying on broad user access.
- The initial plan is documented in [`aws-milestone-1-vpc-plan.md`](aws-milestone-1-vpc-plan.md). It records the two-AZ CIDR layout, security boundaries, NAT tradeoffs, account findings, and estimated costs. PR #3 was opened for that plan and later updated to include the implementation.

### 6. AWS VPC Terraform preparation

- Work is on `feature/aws-vpc-networking`; PR #3 is open, targets `main`, and is reported mergeable. GitHub reported no status checks on the Terraform implementation commit.
- Existing scaffold review found three mismatches: region defaulted to `ap-south-1`, subnet math produced different CIDRs and defaulted to three AZs, and NAT was enabled per AZ automatically. These were corrected in the feature branch.
- Current Terraform defaults: region `us-east-1`, VPC `10.0.0.0/16`, two AZs, and NAT mode `disabled`. Subnets are public `10.0.1.0/24`, `10.0.2.0/24` and private `10.0.11.0/24`, `10.0.12.0/24`. Public and private subnets get the AWS Load Balancer Controller role tags and the cluster discovery tag. Public IPv4 auto-assignment is off.
- NAT mode validates `disabled`, `single`, or `per_az`. The disabled default creates no NAT Gateway, Elastic IP, or private default internet-egress route. EKS managed node groups explicitly use only private subnet IDs and disable public IP association.
- Root outputs now expose the VPC ID, public/private subnet IDs, route table IDs, NAT Gateway IDs, plus the scaffold's ECR and EKS outputs. A provider lock file and [`../terraform/README.md`](../terraform/README.md) were added.
- **State decision:** there is no remote backend and no backend infrastructure. Local state files remain ignored by Git. A shared encrypted/versioned/locked remote state design must be separately selected and provisioned before collaborative deployment.
- Terraform initialization first failed because the shell could not resolve/download the Terraform Registry. Network access was granted for dependency retrieval, after which `terraform init -backend=false` succeeded and produced the committed provider lock file.
- Validation passed: `terraform fmt -check -recursive` and `terraform validate`. A networking-only plan ran with refresh disabled and `-target=module.networking`; it planned 17 additions for the new VPC/network layer, showed all four CIDRs in `us-east-1a/b`, and showed no NAT Gateway or Elastic IP. It did not include the existing default VPC. The plan is deliberately scoped and is not a full EKS/ECR/IAM plan.
- Gitleaks is not installed in the local environment. A targeted scan for common AWS keys, GitHub tokens, private-key blocks, and `aws_secret_access_key` patterns found no likely credential matches in the changed implementation files. No credentials were committed.
- Shell Git push authentication was unavailable in the local execution environment. The Terraform branch update was completed through the connected GitHub integration with an expected-head check and `force=false`; a fetch then succeeded and local/remote trees matched. The journal update was also pushed through the integration. A later fetch attempt hit a temporary GitHub DNS failure, so the local remote-tracking ref may lag; the local documentation tree matches the tree SHA returned for the remote commit. PR #3 was updated with scope, validation, and safety notes.
- No `terraform apply` was run. The Terraform plan can include default network ACL, route table, and security group management for the **new** VPC; this is distinct from changing the account's existing default VPC.

## Issues encountered and resolutions

| Issue | Resolution / current status |
| --- | --- |
| OrbStack Docker socket was blocked by the execution sandbox | Obtained read/connect access for read-only checks; verified engine availability without changing Docker resources. |
| Kubernetes API initially refused connections | Owner started Kubernetes in OrbStack; later health checks reported the API and node healthy. No cluster restart or settings change was performed by the agent. |
| ARM64 local node and AMD64 upstream application images | Reused Google's published release images with OrbStack emulation; kept upstream code/manifests intact. Load generator remains disabled because it caused cart probe failures under emulation. |
| Custom image/build approach was taking too long | Returned to upstream release manifests/images and kept only a small local Kustomize overlay. |
| Some monitoring images lacked ARM64 variants | Documented a helper for the two pinned official images that need AMD64 emulation; other images use ARM64 variants. |
| Application metrics are absent in the local Prometheus path | Did not invent metrics or claim application scraping; documented actual target/query limitations and available node/kube-state metrics. |
| Initial Terraform scaffold did not match the requested region/CIDRs/NAT safety | Updated defaults, exact subnet indexes, two-AZ validation, and explicit validated NAT modes with disabled as default. |
| Terraform Registry DNS/network access failed during init | Network access was granted for dependency retrieval; initialization and validation then succeeded. |
| `jq` and Gitleaks were unavailable | Used Python to inspect the saved plan JSON; ran a targeted credential-pattern scan as a Gitleaks fallback. |
| Shell Git push had no HTTPS username/credential available | Used the connected GitHub integration for a fast-forward-only ref update, then fetched and compared the local/remote tree. |
| A later Git fetch could not resolve `github.com` | Confirmed the pushed commit and open PR through the GitHub integration; the local and remote tree SHA matched. Local origin tracking may need a fetch when DNS is available again. |

## Current status and next work

### Completed or recorded

- Upstream application inspection and local deployment configuration on the local Kubernetes branch.
- Owner-reported successful local application availability at the start of monitoring work.
- Local monitoring configuration and documented target/metric limitations on its feature branch.
- AWS read-only inspection and VPC architecture document.
- VPC Terraform preparation, provider lock file, README, formatting/validation, and scoped non-applying plan on `feature/aws-vpc-networking`.
- PR #1 merged; PR #2 and PR #3 open at the time of this update.

### Still pending

- Review/merge PR #2 (local monitoring) and PR #3 (VPC planning and Terraform preparation) through the repository's normal review/check policy.
- Recheck local OrbStack cluster and application state when resuming local work; the journal records the earlier reported status, not a live health check.
- Review and approve the VPC plan and costs before any provisioning. Confirm CIDR compatibility with networks not visible in the account inventory.
- Choose the exact AZs if deterministic cross-account placement is required.
- Design and separately approve shared Terraform state, EKS access/security, least-privilege deployment role, cost controls, and required private-subnet egress/endpoints.
- Run a full Terraform plan only after all required EKS/OIDC inputs are deliberately set. Any `terraform apply` remains a separate approval step.

## Related documentation and implementation

- [AWS architecture](architecture.md)
- [Implementation roadmap](implementation-plan.md)
- [AWS VPC inspection and plan](aws-milestone-1-vpc-plan.md)
- [Terraform usage, inputs, outputs, costs, and state](../terraform/README.md)
- [Local Kubernetes deployment commit](https://github.com/ElmoCan/online-boutique-devops/commit/2b9644f)
- [Local monitoring PR #2](https://github.com/ElmoCan/online-boutique-devops/pull/2)
- [AWS VPC preparation PR #3](https://github.com/ElmoCan/online-boutique-devops/pull/3)
