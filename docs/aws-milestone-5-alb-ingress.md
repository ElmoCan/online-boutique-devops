# AWS Milestone 5: ALB Ingress preparation

**Status:** Read-only AWS discovery completed; preparation is on the local
`feature/aws-lbc-ingress` worktree based on current `origin/main` commit
`4f77d7a`. No AWS resources were created or changed, no controller was
installed, and no ALB was created. Nothing was pushed or merged.

## Live environment snapshot

Read-only AWS CLI calls used `devops-practice` in `us-east-1`. The caller is
account `471623014584` (`YusufSir`). Credentials were not read or printed.

- EKS `online-boutique-dev` is `ACTIVE`, Kubernetes `1.36`; public and private
  API access are enabled. Public access is restricted to a single `/32`.
- The managed node group is `ACTIVE`, `ON_DEMAND`, `c7i-flex.large`, min/desired
  3 and max 6. Its Auto Scaling Group has three `InService`/`Healthy` EC2
  instances distributed 2 in `us-east-1a` and 1 in `us-east-1b`.
- Read-only EC2 inspection confirmed all three workers have private addresses
  only and no public IPv4. Both public ALB subnets have at least 250 free IPv4
  addresses, above ALB's minimum subnet headroom requirement.
- The Kubernetes API could not be reached from this workstation. The current
  outbound address did not match the EKS API allowlist. Therefore live node
  `Ready` conditions, workloads, Services, Ingresses, and the deployed frontend
  replica count could not be verified. No endpoint CIDR was changed.
- The active project VPC is `vpc-0ca73856f4cd0179f` (`10.0.0.0/16`). Public
  subnets are `subnet-0596618607a622fe8` (`10.0.1.0/24`, `us-east-1a`) and
  `subnet-0a71bcc8bf0f7582b` (`10.0.2.0/24`, `us-east-1b`). Both carry
  `kubernetes.io/role/elb=1` and the cluster `shared` tag. Both route to the
  Internet Gateway. Their `MapPublicIpOnLaunch` setting is false; this keeps
  ordinary EC2 launches private and does not prevent an internet-facing ALB
  from using those subnets.
- Private subnets are `subnet-01dfceaffbf2844b6` (`10.0.11.0/24`, AZ-a) and
  `subnet-0e9fec1d55fb6bf6e` (`10.0.12.0/24`, AZ-b). Both carry
  `kubernetes.io/role/internal-elb=1` and the cluster `shared` tag. Their
  default route uses the existing single NAT Gateway. Nodes use these private
  subnets, and public-IP assignment is disabled in their launch template.
- No project ALB exists yet. The cluster security group permits API traffic
  from the node security group; the node security group has no public ingress
  rule. The controller webhook also requires TCP 9443 from the EKS control
  plane to controller Pods/nodes; that specific path must be confirmed in the
  live security-group rules before installation. It could not be rechecked in
  the latest read-only session because AWS endpoints were unreachable. The
  current node role has the standard EKS worker, CNI, and ECR-read
  policies, with no AWS Load Balancer Controller policy attached.
- The EKS OIDC provider exists. A separate GitHub OIDC provider exists with
  client ID `sts.amazonaws.com`. The current GitHub Actions role trust is
  name-based (`repo:ElmoCan/online-boutique-devops:ref:refs/heads/main`) and
  has the correct `sts.amazonaws.com` audience. The live ECR permissions are
  scoped to the project repository and `eks:DescribeCluster` is scoped to the
  project cluster. The role is not granted ELB permissions.
- The Elastic Load Balancing service-linked role already exists. `aws eks
  list-addons` returned no managed add-ons. The node role has the standard VPC
  CNI policy, but the live `aws-node` DaemonSet and Pod IP behavior could not be
  checked while the Kubernetes API is unreachable. Confirm VPC CNI health
  before using ALB IP targets.
- No Route 53 hosted zones or ACM certificates are present in `us-east-1`.
- AWS Free Tier usage data is readable, but this installed AWS CLI (2.27.19)
  does not expose the newer account-plan-state operation. Free-plan eligibility
  and remaining credits could not be verified from this session.

## Architecture prepared

```text
Internet
   │ HTTP :80 (temporary until domain + ACM certificate are supplied)
   ▼
Internet-facing ALB in public AZ-a and AZ-b subnets
   │ target-type: ip, health check /_healthz
   ▼
frontend Service (ClusterIP :80) ──► frontend Pods (:8080), 2 replicas
                                           │
                                           └─► private ClusterIP services
                                                including redis-cart
```

The AWS Load Balancer Controller is planned as a Helm release in `kube-system`
at chart/controller version `3.6.2`, with two replicas and a disruption budget.
It receives a dedicated IRSA role trusted only by the EKS OIDC provider and the
`kube-system/aws-load-balancer-controller` ServiceAccount. The controller role
is separate from both the worker node role and GitHub Actions role. Its
version-matched policy is based on the upstream `v3.6.2` release. The upstream
policy contains 16 statements. The checked-in subset removes optional WAF,
Shield, Cognito, and legacy IAM server-certificate actions. The remaining
policy still uses `Resource: "*"` for some discovery and lifecycle actions and
for a security-group permission required to reconcile IP targets; do not
replace it with a broader AWS managed policy. Its source hash and removed
actions are recorded below.

The chart and controller version are pinned together at `3.6.2`. The upstream
release exists, and the official installation docs recommend Helm and IRSA and
provide the version-matched IAM policy. Those docs state controller 2.5.0+
supports Kubernetes 1.22+; EKS 1.36 is above that documented minimum. This is a
minimum-version compatibility check, not a live chart render or end-to-end
certification. `helm` is not installed, and the cluster API is unreachable from
this workstation.

The IAM policy is based on the version-matched upstream policy and excludes
optional WAF, Shield, Cognito, and legacy certificate actions. It still has an
unconditioned `ec2:AuthorizeSecurityGroupIngress` / `RevokeSecurityGroupIngress`
statement with `Resource: "*"`, matching the upstream policy's broad rule for
security-group reconciliation. Upstream recommends scoping this permission to
the VPC or cluster tag. Before applying, constrain it to the project VPC and
validate the resulting policy while retaining the controller's ability to add
backend rules to the worker security group.

The upstream v0.10.7 frontend source registers `/_healthz` as a handler that
returns `ok` (HTTP 200), so ALB health checks do not depend on the Cookie header
used by the Kubernetes readiness and liveness probes.

The public route is only a Kubernetes `Ingress` targeting `Service/frontend`:
the target mode is IP, not node/NodePort. The prepared Kustomize overlay reads
Google's pinned v0.10.7 upstream release manifest without editing it. That
release also defines `frontend-external` as `type: LoadBalancer`; the overlay
patches it to `ClusterIP` so it cannot create a second load balancer. The
frontend Deployment is set to two replicas, spread across zones and hosts, and
protected by a PDB with `minAvailable: 1`. The other upstream services remain
ClusterIP.

## GitHub OIDC correction

GitHub's current immutable subject format is
`repo:OWNER@OWNER-ID/REPO@REPO-ID:ref:refs/heads/BRANCH`. The public repository
metadata confirmed owner ID `135598223` and repository ID `1450199615`. The
prepared Terraform trust condition is therefore exactly:

```text
repo:ElmoCan@135598223/online-boutique-devops@1450199615:ref:refs/heads/main
```

This is GitHub's documented subject syntax; the shorter `repo@OWNER-ID/...:ref/heads/main`
spelling is not the `sub` claim GitHub issues. The audience remains
`sts.amazonaws.com`. This is an IaC correction only; the
live IAM role still has the old name-based subject until a separately approved
Terraform change is applied. A repo-root `.github/workflows` directory is not
present yet, so no workflow currently demonstrates the claim at runtime.

## HTTPS, domain, and DNS prerequisites

The current Ingress is HTTP-only because no usable domain, hosted zone, or ACM
certificate is present. Before enabling HTTPS, supply a domain name you control,
decide which DNS provider will host its records, and request a public ACM
certificate in `us-east-1`. Complete DNS validation before adding the certificate
ARN to the Ingress. Then configure listener ports `[{"HTTP":80},{"HTTPS":443}]`,
`alb.ingress.kubernetes.io/certificate-arn`, and
`alb.ingress.kubernetes.io/ssl-redirect: "443"`. Do not add a placeholder ARN
or enable redirect before an HTTPS listener exists. CloudFront remains out of
scope for this milestone.

## Cost estimate

The ALB is an incremental resource; EKS, nodes, NAT, and VPC costs are already
present and are not included below. A 730-hour month in `us-east-1`:

| Item | Approximate cost |
| --- | ---: |
| ALB base ($0.0225/hour) | $16.43/month |
| Two in-use public IPv4 addresses ($0.005/hour each) | $7.30/month |
| ALB LCU ($0.008/LCU-hour; usage dependent) | $0 at zero measured usage; about $5.84/month at 1 LCU continuously |
| Expected simple low-use ALB subtotal at 1 LCU | **about $29.57/month ($0.99/day)** |
| Public ACM certificate attached only to ALB | No certificate fee |
| Route 53 hosted zone, if added | $0.50/month plus applicable queries |
| Domain registration, if needed | TLD-dependent annual charge |

The previous ALB estimate of approximately $29.57/month matches the base ALB,
two public IPv4 addresses, and 1 LCU continuously. Traffic/LCU usage, data
transfer, DNS queries, and domain registration are additional. ALB pricing is
not the same as Free Tier eligibility: the account plan and credits remain
unverified, and no assumption is made that this ALB is free.

## Preparation files

- `terraform/modules/aws_load_balancer_controller/` defines the dedicated IRSA
  role and attaches an ALB-focused subset of the upstream v3.6.2 policy.
- `terraform/modules/github_oidc/main.tf` uses the repository's immutable
  owner/repository IDs and exact `main` ref.
- `kubernetes/aws/controller/helm-values.yaml` pins resource settings and
  references the prepared ServiceAccount. `service-account.yaml.tmpl` expects
  `AWS_LBC_IAM_ROLE_ARN` to be filled from the Terraform output at deployment.
- `kubernetes/aws/online-boutique/` is a Kustomize overlay on the upstream
  release, with the ALB Ingress, frontend replica/spread patch, PDB,
  namespace-scoped deployer Role/RoleBinding, and private `frontend-external`
  Service patch. The deployer group can manage application Deployments,
  Services, ServiceAccounts, Ingresses, and PDBs only inside `online-boutique`;
  it can read Pods, ReplicaSets, and Events. It cannot read Secrets or modify
  RBAC, Namespaces, or cluster-scoped resources. The RoleBinding expects the EKS
  access entry to map the GitHub IAM role to group `online-boutique-deployer`.
  A prior live inspection saw that mapping, but current AWS endpoint failures
  prevented rechecking it; current `main` Terraform does not encode the access
  entry, so reconcile state and ownership before changing it.

The controller Helm chart installs its own cluster-scoped RBAC to watch
Ingresses and related resources; that is separate from the namespace-scoped
GitHub deployer Role.

Kustomize's default path restriction rejects a base outside the overlay
directory. To consume the upstream manifest in place without copying or editing
it, render the trusted repository overlay with
`kubectl kustomize --load-restrictor=LoadRestrictionsNone kubernetes/aws/online-boutique`
and pipe the result to `kubectl apply -f -` only after deployment approval.
This makes the overlay repository-layout dependent; keep it and its upstream
manifest in the same repository tree.

## Validation results

- `terraform fmt -recursive`: passed; formatted the root module and new
  controller module.
- `terraform init -backend=false -lockfile=readonly`: passed to register the
  local module and reuse pinned providers. The backend was disabled; no state
  migration or AWS API calls were run.
- `terraform validate`: passed.
- Kustomize rendered 39 objects using `LoadRestrictionsNone` after adding the
  deployer Role and RoleBinding. YAML parsing and assertions confirmed all 12
  Services are `ClusterIP`; frontend replicas are
  2 with zone/host spread; the Ingress uses `alb`, IP targets, and `/_healthz`;
  and the PDB has `minAvailable: 1`.
- AWS IAM Access Analyzer `validate-policy` on the prepared controller policy
  returned no findings.
- The installed Access Analyzer API rejects `TRUST_POLICY` as an unsupported
  policy type. The proposed IRSA trust JSON was parsed locally, and its OIDC
  issuer, `aud`, and exact ServiceAccount `sub` were checked. This validates
  syntax and structure but is not a live assume-role test.
- Helm is not installed, so `helm template` could not run. Kubernetes API
  validation is blocked because the workstation's current egress address is
  outside the EKS API `/32` allowlist.
- Follow-up checks on 2026-11-09: Terraform formatting and Kustomize rendering
  passed. The first sandboxed `terraform validate` could not start provider
  processes; rerunning local validation outside the sandbox succeeded. AWS CLI
  read-only calls to STS, EKS, Route 53, and ACM could not connect to their
  service endpoints, so the 2026-11-08 inventory is not a same-day recheck. No
  AWS settings were changed.
- Existing Terraform state and saved plan files were not opened or changed. No
  Terraform plan or apply was run.

## Deployment sequence after approval

1. Reconfirm account, billing plan/credits, cluster status, AWS API access,
   subnets, live VPC CNI, application Services/Deployments, and TCP 9443
   webhook reachability from the EKS control plane to the controller.
2. Apply the reviewed Terraform plan to create the dedicated controller policy
   and IRSA role and update GitHub trust to the immutable subject.
3. Render/apply the ServiceAccount from the Terraform role ARN; install the
   pinned Helm chart `3.6.2` in `kube-system` with the checked-in values.
4. Verify controller readiness, events, permissions, and target registration.
5. Render/apply the Kustomize overlay with the documented path-restriction
   override. Confirm `frontend` and `frontend-external` are both ClusterIP, all
   other services remain ClusterIP, two frontend Pods are
   healthy, and the Ingress resolves to one internet-facing ALB.
6. Verify ALB security groups permit inbound HTTP/HTTPS only as intended and
   backend traffic only from the ALB security group to frontend port 8080.
7. After the owner supplies a domain, validate ACM in `us-east-1`, switch to
   HTTPS redirect, add DNS alias, and verify the browser certificate and
   application health.

## Sources

- [AWS Load Balancer Controller v3.6.2 release](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.6.2)
- [Upstream installation and IAM policy instructions](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.2/docs/deploy/installation.md)
- [AWS Load Balancer Controller Helm chart metadata and versions](https://artifacthub.io/packages/helm/aws/aws-load-balancer-controller)
- [Upstream v3.6.2 IAM policy](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.6.2/docs/install/iam_policy.json)
- [AWS EKS Helm installation guide](https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html)
- [GitHub immutable OIDC subject claims](https://docs.github.com/en/actions/reference/security/oidc)
- [Application Load Balancer pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [Public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
- [ACM pricing](https://aws.amazon.com/certificate-manager/pricing/)
- [Route 53 pricing](https://aws.amazon.com/route53/pricing/)

Policy provenance: upstream v3.6.2 IAM policy SHA-256
`16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a`.
The checked-in ALB-focused subset SHA-256 is
`82a0cf022ba2a50cf366eda2f037993251e48c93e67200d5b7111d9ca5845fa4`.
The subset removes `cognito-idp:DescribeUserPoolClient`, legacy IAM server
certificate read actions, WAF regional/WAFv2 actions, Shield Advanced actions,
and `elasticloadbalancing:SetWebAcl`. Revisit these removals if those features
are enabled later.
