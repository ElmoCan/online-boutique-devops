# Online Boutique DevOps project journal

**Last updated:** 2026-11-09

**Repository:** [`ElmoCan/online-boutique-devops`](https://github.com/ElmoCan/online-boutique-devops)
**Purpose:** Keep a chronological record of decisions, implementation, verification, blockers, and fixes. This journal distinguishes work committed in the repository from work reported by the project owner and from future plans.

## Project goal and working rules

Build a production-oriented DevOps implementation around Google's Online Boutique while keeping Google's source repository unchanged. The application source of truth is [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo); this repository holds project documentation and DevOps configuration.

The work has moved through three scopes:

1. **Local development:** run the upstream application on OrbStack Kubernetes, add local Prometheus/Grafana, and document the workflow.
2. **AWS preparation and teardown:** inspect AWS, design the platform, deploy the approved learning environment, then destroy project resources while preserving state and project artifacts.
3. **AWS redeployment:** rebuild the approved EKS environment and prepare an upstream-based CI/CD deployment path.

Safety decisions carried through the work:

- Do not modify Google's upstream source.
- Keep local and cloud configurations in the DevOps repository.
- Use OrbStack port-forwarding for local access; do not expose the local app or Grafana publicly.
- Provisioning is performed only after explicit project-owner approval. The former learning environment was destroyed; a later approved redeployment is now live.
- Do not store AWS credentials, Grafana passwords, or other secrets in Git.
- Keep the load generator off by default on the resource-constrained local ARM64 cluster.

## Current status snapshot — 2026-11-09

- The previous AWS learning environment was destroyed in the documented teardown milestone (61 Terraform resources). The project VPC, EKS cluster, NAT Gateway, ECR, and related resources were subsequently recreated after the owner asked to continue deployment. The original default VPC and unrelated S3 bucket remain out of scope.
- Current approved platform: EKS `online-boutique-dev` in `us-east-1`, Kubernetes 1.36, three private `c7i-flex.large` workers across two AZs, project VPC `10.0.0.0/16`, one NAT Gateway, and a restricted public EKS endpoint. The cluster and workers were observed ACTIVE/Ready during this implementation. OrbStack was not modified.
- The EKS node group, VPC, ECR repositories, GitHub OIDC role, CodeBuild private deploy runner, EBS CSI, and AWS Load Balancer Controller 3.6.2 are provisioned. Controller pods are Ready. The dedicated `online-boutique` namespace and deployer RBAC are present.
- Google Online Boutique v0.10.7 is deployed in namespace `online-boutique`. The post-merge pipeline completed successfully (GitHub Actions run `42616144276`); the rollout previously verified 12/12 Deployments, 13/13 Pods Ready, and frontend 2/2. The active public ALB currently has two healthy IP targets and returned HTTP 200 for `/` during the 2026-11-09 review.
- Current read-only AWS inspection found EKS `online-boutique-dev` ACTIVE on Kubernetes 1.36, its managed node group ACTIVE at 3 desired `c7i-flex.large` workers (min 3, max 6), one available NAT Gateway, and an active internet-facing ALB in both public subnets. Worker instances have private addresses. The EKS public API allowlist is restricted to a single `/32`; its value is intentionally not recorded here.
- The only public application entry point is the ALB on HTTP/80. Its security group permits internet traffic on TCP/80, as expected for the current public storefront. There is no HTTPS listener; adding HTTPS still requires an owner-provided domain and ACM certificate. OrbStack was not modified.
- PR #9 fixed the CodeBuild CloudWatch log-stream permissions. A full Terraform plan after the policy update reported `No changes`; its saved plan remains outside Git. No AWS credentials, OIDC tokens, kubeconfig contents, or public API `/32` value are stored in Git.

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

- Monitoring configuration was committed as `f09e715` on `feature/local-prometheus-grafana`. The owner reviewed and merged PR #2, “Add local Prometheus and Grafana monitoring,” on 2026-11-08 (merge commit `8092c395d9a947221bc68acc6d670f3a86d821be`).
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
- The initial plan is documented in [`aws-milestone-1-vpc-plan.md`](aws-milestone-1-vpc-plan.md). It records the two-AZ CIDR layout, security boundaries, NAT tradeoffs, account findings, and estimated costs. PR #3 was opened for that plan, expanded to include the implementation, reviewed and merged by the owner on 2026-11-08 (merge commit `ebd564cb530672bcc4e9f973104b1e80f455b610`).

### 6. AWS VPC Terraform preparation

- Work is on `feature/aws-vpc-networking`; PR #3 was merged into `main` after owner review. GitHub reported no status checks on the Terraform implementation commit.
- Existing scaffold review found three mismatches: region defaulted to `ap-south-1`, subnet math produced different CIDRs and defaulted to three AZs, and NAT was enabled per AZ automatically. These were corrected in the feature branch.
- Current Terraform defaults: region `us-east-1`, VPC `10.0.0.0/16`, two AZs, and NAT mode `disabled`. Subnets are public `10.0.1.0/24`, `10.0.2.0/24` and private `10.0.11.0/24`, `10.0.12.0/24`. Public and private subnets get the AWS Load Balancer Controller role tags and the cluster discovery tag. Public IPv4 auto-assignment is off.
- NAT mode validates `disabled`, `single`, or `per_az`. The disabled default creates no NAT Gateway, Elastic IP, or private default internet-egress route. EKS managed node groups explicitly use only private subnet IDs and disable public IP association.
- Root outputs now expose the VPC ID, public/private subnet IDs, route table IDs, NAT Gateway IDs, plus the scaffold's ECR and EKS outputs. A provider lock file and [`../terraform/README.md`](../terraform/README.md) were added.
- **State decision:** there is no remote backend and no backend infrastructure. Local state files remain ignored by Git. A shared encrypted/versioned/locked remote state design must be separately selected and provisioned before collaborative deployment.
- Terraform initialization first failed because the shell could not resolve/download the Terraform Registry. Network access was granted for dependency retrieval, after which `terraform init -backend=false` succeeded and produced the committed provider lock file.
- Validation passed: `terraform fmt -check -recursive` and `terraform validate`. A networking-only plan ran with refresh disabled and `-target=module.networking`; it planned 17 additions for the new VPC/network layer, showed all four CIDRs in `us-east-1a/b`, and showed no NAT Gateway or Elastic IP. It did not include the existing default VPC. The plan is deliberately scoped and is not a full EKS/ECR/IAM plan.
- Gitleaks is not installed in the local environment. A targeted scan for common AWS keys, GitHub tokens, private-key blocks, and `aws_secret_access_key` patterns found no likely credential matches in the changed implementation files. No credentials were committed.
- Shell Git push authentication was unavailable in the local execution environment. The Terraform branch update was completed through the connected GitHub integration with an expected-head check and `force=false`; a fetch then succeeded and local/remote trees matched. The journal was pushed to the same feature branch after PR #3 had merged, so those follow-up journal corrections are not part of merge commit `ebd564cb530672bcc4e9f973104b1e80f455b610`; they are being submitted separately for review. A later fetch attempt hit a temporary GitHub DNS failure, so the local remote-tracking ref may lag; the local documentation tree matches the tree SHA returned for the remote commit.
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
| A later Git fetch could not resolve `github.com` | Confirmed the pushed commit through the GitHub integration; the local documentation tree matched the returned remote tree SHA. Local origin tracking may need a fetch when DNS is available again. |

## Current status and next work — 2026-11-09

### Completed or recorded

- Upstream application inspection and local deployment configuration on the local Kubernetes branch.
- Owner-reported successful local application availability at the start of monitoring work.
- Local monitoring configuration and documented target/metric limitations on its feature branch.
- AWS read-only inspection and VPC architecture document.
- VPC Terraform preparation, remote state, and approved AWS deployment; PRs #1, #2, #3, and #9 are merged.
- AWS application rollout and public HTTP access through the ALB. The CloudWatch log-stream IAM correction and post-merge deployment run are recorded below.

### Still pending

- Recheck Kubernetes objects when the workstation can resolve/reach the EKS API. During this review, `kubectl` could not resolve the API hostname, so pod, Service, HPA, and live image-tag inspection could not be repeated from this machine.
- Obtain an owner-provided domain before preparing ACM and HTTPS. The storefront remains publicly reachable over HTTP until that is approved and implemented.
- Add a documented rollback runbook and decide how failed multi-service rollouts should be recovered.
- Review event/path filtering so documentation-only main-branch changes do not rebuild every application image and redeploy the workload.
- Evaluate workload HPA and node autoscaling separately; the managed node group has 3/3/6 min/desired/max bounds, but the repository does not configure an HPA or autoscaler controller.

## Related documentation and implementation

- [AWS architecture](architecture.md)
- [Implementation roadmap](implementation-plan.md)
- [AWS VPC inspection and plan](aws-milestone-1-vpc-plan.md)
- [Terraform usage, inputs, outputs, costs, and state](../terraform/README.md)
- [Local Kubernetes deployment commit](https://github.com/ElmoCan/online-boutique-devops/commit/2b9644f)
- [Local monitoring PR #2](https://github.com/ElmoCan/online-boutique-devops/pull/2)
- [AWS VPC preparation PR #3](https://github.com/ElmoCan/online-boutique-devops/pull/3)

### 6. AWS Milestone 5: ALB Ingress preparation (2026-11-08)

- Read-only AWS checks confirmed the `online-boutique-dev` EKS control plane is
  ACTIVE on Kubernetes 1.36, the managed node group is ACTIVE with three
  healthy `c7i-flex.large` EC2 instances, and the two public ALB subnets have
  the required discovery tags and Internet Gateway route. Nodes remain in the
  two private subnets with public IP assignment disabled and use the existing
  single NAT Gateway for egress.
- The local workstation could not reach the EKS Kubernetes API because its
  current egress address is outside the API endpoint's restricted `/32`.
  Therefore application Services, pods, Kubernetes node readiness, and any
  current Ingress could not be verified live. No EKS endpoint CIDR was changed.
- The public upstream Online Boutique v0.10.7 release manifest contains both
  `frontend` (`ClusterIP`) and `frontend-external` (`LoadBalancer`). A new
  Kustomize overlay keeps the latter private, adds an IP-target ALB Ingress,
  sets two frontend replicas with zone/host spread, and adds a frontend PDB.
  The upstream source remains unchanged.
- AWS Load Balancer Controller chart/controller v3.6.2 and an ALB-focused
  subset of its version-matched IAM policy were prepared for an IRSA-only role.
  The subset removes unused WAF, Shield, Cognito, and legacy IAM certificate
  actions. The role trust is
  restricted to the EKS OIDC provider, audience `sts.amazonaws.com`, and the
  `kube-system/aws-load-balancer-controller` ServiceAccount. No permissions
  were added to worker nodes or GitHub Actions.
- The live GitHub Actions trust still uses the old name-based `sub`; the local
  Terraform configuration now prepares the official immutable GitHub subject
  using owner ID `135598223` and repository ID `1450199615`, restricted to
  `main`. The existing role audience is already `sts.amazonaws.com`; the live
  trust remains unchanged until reviewed Terraform is applied.
- Read-only Route 53 and ACM queries returned no hosted zones or certificates
  in `us-east-1`. Ingress preparation is HTTP-only; HTTPS redirect remains
  pending a domain controlled by the project owner and a validated ACM public
  certificate.
- The account's Free Tier usage endpoint is readable, but the installed AWS
  CLI does not expose the account-plan-state operation. Free-plan eligibility
  and credit balance remain unverified. No ALB cost is assumed to be free.
- No EKS managed add-ons were returned by `aws eks list-addons`. The worker role
  includes the VPC CNI policy, but the live `aws-node` DaemonSet and Pod IP
  behavior still need verification because the EKS Kubernetes API is outside
  the workstation's current allowed `/32`.
- Local validation passed Terraform formatting, `terraform validate`, Kustomize
  rendering (37 objects, all 12 Services ClusterIP), and AWS IAM Access
  Analyzer validation of the controller policy (no findings). Helm is not
  installed, so chart rendering was not run. Access Analyzer in this account
  rejected `TRUST_POLICY` as an unsupported policy type; the proposed trust
  document was checked as parsed JSON with the exact audience and ServiceAccount
  subject. Terraform state and saved plans were preserved.
- Local preparation is documented in
  [AWS Milestone 5](aws-milestone-5-alb-ingress.md). No AWS resource, ALB,
  controller, or Kubernetes object was created. No plan was generated/applied,
  and no changes were pushed or merged.

### 7. AWS learning environment shutdown (2026-11-09)

- Verified `aws sts get-caller-identity --profile devops-practice` as account
  `471623014584` in `us-east-1`. The first Terraform refresh used the machine's
  default AWS identity instead of this profile and was denied on IAM OIDC reads;
  no plan was produced from that attempt. Set `AWS_PROFILE=devops-practice` for
  the subsequent Terraform plan/apply and confirmed Terraform's caller was the
  verified project account.
- Refreshed a full, untargeted destroy plan from the local Terraform state using
  the live EKS 1.36 version and current endpoint CIDR. Plan was complete and
  applyable: 61 deletes, zero additions, zero changes, zero drift. It targeted
  only the Online Boutique VPC (`vpc-0ca73856f4cd0179f`), EKS cluster
  `online-boutique-dev`, node group, project IAM/OIDC, KMS, CloudWatch, ECR and
  associated networking resources. It contained no ALB/load balancer, no AWS
  Load Balancer Controller resources, and no account default VPC. The project's
  GitHub OIDC provider was trusted by only the project GitHub Actions role.
- Before apply, copied both exact Terraform state files to the restricted local
  archive directory
  `/Users/yusufchoudhari/Documents/Codex/.online-boutique-state-preserved.vatF1o`
  (directory mode 0700; files mode 0600). The original pre-destroy state SHA256
  is `12d653663b50b51a85c9e50167e3e13f94815a4796e1ea964c3425535adbf499`; the
  prior backup SHA256 is
  `535e8c4ba10af7b83ed1a9ac024caa4b3f1f48f104e9e63074c0847ecda1e3ef`.
- Applied the reviewed saved plan. Terraform completed successfully with 0
  additions, 0 changes and 61 deletions. EKS node group deletion took about
  eight minutes; the EKS control plane then completed deletion. The NAT
  Gateway and EIP, project VPC/subnets/routes/Internet Gateway, ECR repository,
  project IAM roles/policies/OIDC providers, EKS security groups, and EKS
  CloudWatch log group were removed.
- Post-destroy checks confirmed there are no EKS clusters, no project VPC (the
  account default VPC remains), no ALB/NLB, no ECR repository, no project IAM
  roles/OIDC providers, no project log group, no EIP allocation, and no active
  NAT Gateway. All three worker instances are terminated; their three 20 GiB
  root volumes, node ENIs and project security groups are absent. A tag-index
  query briefly continued to return stale deleted-resource entries, so direct
  service lookups by resource IDs were used to verify deletion.
- The customer-managed KMS key is `PendingDeletion` until 2026-12-09. The
  project S3 bucket `devops-endpoint-lab-12` was not in Terraform state and was
  deliberately left untouched; it may continue to incur storage/request
  charges. Service-linked roles and unrelated account resources were not
  deleted. No public load balancer existed or was created.
- Terraform now has an empty local state (zero managed objects); its backup
  contains the pre-destroy state. The exact prior state and backup remain in
  the protected archive above. Repository source, upstream application files,
  manifests, documentation and all pre-existing uncommitted Milestone 5 changes
  were preserved. Nothing was committed or pushed. The saved applied plan and
  its readable report remain outside Git under `/private/tmp/ob-dev-destroy.vvjjsd/`.

### 8. Approved AWS platform redeployment and CI/CD preparation (2026-11-09)

- After the owner resumed deployment, bootstrapped the project's encrypted,
  versioned S3 Terraform state bucket with public access blocked and TLS-only
  access. Root Terraform now uses S3 native state locking. The bootstrap state
  and prior destroy-state archive remain preserved.
- A fresh full Terraform plan created the approved platform; apply completed
  with 78 additions, zero changes and zero deletions. The project VPC,
  two-AZ public/private subnets, one NAT Gateway, EKS 1.36, three private
  `c7i-flex.large` workers, IAM/OIDC, ECR, EBS CSI and private CodeBuild deploy
  runner are active. A follow-up plan created 12 service ECR repositories and
  lifecycle policies and updated two CI/IAM resources. No default-VPC changes.
- Verified all three EKS nodes Ready, EBS CSI ACTIVE, core system pods Running,
  private-only node addressing, and project subnet tags for the load balancer
  controller. Existing public API access remains constrained to the operator's
  `/32`; that value is not committed.
- Installed AWS Load Balancer Controller chart/application version 3.6.2 using
  its dedicated IRSA role. Both replicas are Ready. The dedicated namespace,
  namespace-scoped deployer RBAC and frontend Ingress/PDB overlays are prepared;
  no application deployment or ALB exists yet.
- Added GitHub Actions workflows for upstream tests, Kustomize rendering,
  commit-tagged Skaffold image builds and ECR push; a `workflow_run` workflow
  starts the private CodeBuild deployment runner after successful main CI.
  Upstream application source and manifests are consumed from the pinned Git
  submodule; no upstream files were changed. The local Docker daemon is
  unavailable, and Go/.NET runtimes are not installed, so image builds and
  application tests must run in GitHub Actions.
- Local validation: Terraform format/validate, Actionlint 1.7.12, Ruby YAML
  parse, Kustomize rendering (12 ClusterIP Services), Python bytecode compile,
  and `git diff --check` passed. Gitleaks is not installed locally. Workflow
  execution, GitHub OIDC assumption, image push, Kubernetes rollout and ALB
  creation remain pending publication and successful CI. No credentials or
  secret values are stored in the repository.
- Estimated platform spend at the current node size is approximately
  `$302/month` before traffic, NAT data processing, log ingestion, image
  storage, ALB and monitoring charges. Cost estimates are not a billing quote.

### 9. CI image build and private deployment troubleshooting (2026-11-09)

- Main CI run `42609687121` passed upstream Go tests, Cartservice .NET tests,
  and Kustomize validation. GitHub OIDC role assumption and ECR login worked;
  Skaffold built and pushed commit-tagged upstream images to ECR.
- The subsequent CodeBuild deployment run `42611266598` started the configured
  private build but failed in the QUEUED phase before source download. Read-only
  `batch-get-builds` identified the cause: the CodeBuild role's CloudWatch
  resource ARN covered only the log group, while `logs:CreateLogStream` and
  `logs:PutLogEvents` require the log-stream ARN. No application objects or ALB
  were created by that failed run.
- Updated the CodeBuild role policy to scope `logs:CreateLogStream` and
  `logs:PutLogEvents` to `deployment/*` streams under the existing log group.
  A fresh full Terraform plan showed only one in-place role-policy update
  (zero additions/deletions); apply completed with exactly that change.
- Started a new CodeBuild run from the already-built main commit. Its submitted
  and queued phases succeeded; the build then applied manifests and completed
  successfully. Build ID:
  `online-boutique-dev-deploy:1cbb4d83-0334-49bc-af80-ab6b8014dd4d`.
- Verified all 12 Deployments rolled out, including frontend `2/2`; all 13 Pods
  were Running/Ready with zero restarts. All 12 app Services are ClusterIP.
  Initial 1-second probe timeouts during startup recovered; the final pod
  readiness checks passed.
- The frontend Ingress reconciled to active internet-facing ALB
  `k8s-onlinebo-frontend-5d3878fd15-1975334738.us-east-1.elb.amazonaws.com`
  in both public AZ subnets. Its target group is IP mode on port 8080 with
  `/_healthz`; both frontend targets are healthy. `curl` returned HTTP 200 for
  `/`. The browser tool was blocked by a local client extension, so the website
  was not visually inspected in Chrome.
- No HTTPS listener exists. Domain and ACM certificate remain prerequisites.

### 10. Post-deployment review and journal correction (2026-11-09)

- PR #9 merged the least-privilege CodeBuild CloudWatch fix: `logs:CreateLogStream`
  and `logs:PutLogEvents` are scoped to deployment log streams under the existing
  log group. GitHub Actions post-merge deployment run `42616144276` completed
  successfully. The full Terraform plan after the IAM fix returned `No changes`;
  the saved plan was kept outside the repository.
- The successful deployment rollout reported all 12 Deployments complete,
  frontend at 2/2 replicas, and all 13 Pods Ready. The journal's current-status
  snapshot above now reflects this deployment rather than the earlier pre-CI
  state.
- Read-only AWS checks on 2026-11-09 found the EKS control plane and node group
  ACTIVE, three private `c7i-flex.large` workers across two AZs, node-group
  scaling bounds min 3 / desired 3 / max 6, the existing NAT Gateway available,
  and the ALB active across both public subnets. The API endpoint allowlist is
  one `/32`; its address is omitted from Git.
- The ALB uses an IP target group on port 8080. Both registered frontend targets
  were `healthy`. The configured Ingress is internet-facing, routes to the
  `frontend` ClusterIP Service port 80, and checks `/_healthz` over HTTP with
  success code 200. A live `curl` to `/` returned HTTP 200. The ALB security
  group allows public TCP/80; worker instances have private IPs. The Kubernetes
  overlay patches upstream `frontend-external` from `LoadBalancer` to
  `ClusterIP`, leaving the ALB Ingress as the public entry point. HTTPS is not
  configured pending an owner-provided domain and ACM certificate.
- CI builds upstream images with immutable `$GITHUB_SHA` tags. The deploy
  workflow passes the matching `workflow_run.head_sha` to CodeBuild, and
  `configure-ecr-kustomization.py` uses CodeBuild's resolved source SHA as the
  manifest image tag. This is consistent by construction. The live Pod image
  references could not be re-read during this review because the workstation
  could not resolve the EKS API hostname.
- There is one image build per successful main push, and CodeBuild applies the
  manifests without rebuilding the application. However, the build job runs on
  every main push, including docs-only changes; each successful CI run also
  starts a deployment. This is avoidable repeated work and should be narrowed
  with change detection while keeping tests active for documentation changes.
- The pinned upstream v0.10.7 release manifest defines readiness/liveness probes
  and container requests/limits for the application workloads. The AWS overlay
  sets two frontend replicas with zone spread and includes a frontend PDB
  (`minAvailable: 1`). No HPA or autoscaler controller is configured in the
  repository; the node group only has static min/desired/max capacity settings.
  The pipeline waits for `kubectl rollout status` and fails on a failed rollout,
  but it does not automatically roll back. A reviewed rollback procedure should
  use the last known-good Deployment revision or a controlled revert and then
  verify frontend health and ALB targets.
- Current billable resource classes include the EKS control plane, three EC2
  workers and their EBS volumes, NAT Gateway and processed traffic, ALB/LCUs and
  public IPv4 addresses, plus CloudWatch log ingestion/storage and ECR image
  storage. This review did not query the billing APIs or calculate a new cost
  estimate.
- A fresh `kubectl` read attempt failed because the workstation's resolver could
  not resolve the EKS API hostname. No Kubernetes writes or AWS resource changes
  were made. AWS target health and the external HTTP check still confirmed the
  frontend was serving traffic at review time.
