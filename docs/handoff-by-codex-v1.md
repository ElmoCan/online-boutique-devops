# Online Boutique DevOps - Codex Handoff v1

This is a continuation brief for Gemini AI Pro. Read this file first, then inspect the current repository and GitHub workflow state before changing anything. Continue as the project's DevOps engineer: reuse upstream Google Online Boutique, keep the work practical, verify results, and report blockers clearly.

## Project

- GitHub repository: <https://github.com/ElmoCan/online-boutique-devops>
- Google application source: <https://github.com/GoogleCloudPlatform/microservices-demo>
- Application source in this repo: `application/upstream` Git submodule, pinned to `c7cb6d5bfd6ea3aed768634ebbcb98cb7a523712`.
- AWS region: `us-east-1`
- EKS cluster: `online-boutique-dev`
- Namespace: `online-boutique`
- Goal: run the upstream application on EKS, expose only its frontend using AWS Load Balancer Controller and ALB, then verify it end to end.

## Important working rules

1. Keep Google source, Dockerfiles, Skaffold configuration, and release manifests unchanged. DevOps customizations belong in this repository.
2. Check current GitHub and AWS state before retrying operations. Do not blindly repeat a failed deployment.
3. Never put AWS keys, GitHub tokens, OIDC session credentials, kubeconfig content, Grafana passwords, or the EKS API allowlist address in Git or chat.
4. Do not run Terraform apply/destroy without explicit owner approval. The live infrastructure is already provisioned and can incur charges.
5. Keep worker nodes private, Services (including Redis) as ClusterIP, and the frontend as the only public route. Do not expose NodePorts or worker IPs.
6. Preserve S3 Terraform state, local state backups, saved plans, repository history, and all existing files.
7. Follow the repository feature-branch/PR workflow. Do not force-push or bypass failed checks. Earlier project policy permits merging after checks pass and the change is conflict-free.

## Current verified infrastructure

- EKS 1.36 cluster `online-boutique-dev` is ACTIVE. Three `c7i-flex.large` workers in private subnets across two AZs were observed Ready, with no public IPs.
- Project VPC uses `10.0.0.0/16`, two public and two private subnets, an Internet Gateway, and one NAT Gateway. The account default VPC and unrelated S3 bucket were not changed.
- Terraform state uses a dedicated S3 backend with versioning, encryption, blocked public access, TLS-only policy, and native S3 locking. Existing state and backups must be preserved.
- ECR repositories exist for the upstream Skaffold artifacts.
- GitHub OIDC trust is restricted to this repository's immutable owner/repository identity, the `main` branch, and audience `sts.amazonaws.com`. The GitHub Actions role may push to scoped ECR repositories and start/query the named CodeBuild project. It does not have EKS or ELB controller permissions.
- CodeBuild is a private VPC deployment runner. GitHub-hosted runners cannot reach the restricted EKS API directly. CodeBuild uses an EKS access entry and namespace-scoped RBAC.
- AWS Load Balancer Controller chart/application version 3.6.2 is installed through a dedicated IRSA role; both controller replicas were Ready. The `online-boutique` namespace and deployment RBAC exist.
- Estimated platform spend is about USD 302/month before variable NAT processing, CloudWatch ingestion, ECR storage, ALB, monitoring, traffic, and tax. A low-use ALB estimate adds about USD 29.57/month. Recheck current billing/costs; do not treat these estimates as a quote.

## CI/CD status: latest known

- PR #6 added the CI, ECR build, and private deployment workflow. It merged to `main` as `e271081b1d6dd0373e02566e79eefef521fc3b50`.
- Its first CI run exposed an upstream Go 1.27 vet warning on an unchanged checkoutservice call. The CI step was changed to run `go test -vet=off ./...`; the actual Go unit tests still run and passed. Cartservice .NET tests and Kustomize validation also passed.
- The first image-build attempt failed because Skaffold was run from the repository root, while its contexts are relative to `application/upstream`. PR #7 fixed the working directory and merged as `5e8f0a1da1c74d3fccc759de87a660e5117f7629`.
- Main workflow [CI run 42609687121](https://github.com/ElmoCan/online-boutique-devops/actions/runs/42609687121) completed successfully. Its Go tests, cartservice tests, Kustomize render, OIDC role assumption, ECR login, Skaffold build, and image pushes succeeded. Images use immutable tag `5e8f0a1da1c74d3fccc759de87a660e5117f7629`.
- Deployment workflow [run 42611266598](https://github.com/ElmoCan/online-boutique-devops/actions/runs/42611266598) failed because the CodeBuild role's log permission covered the log group ARN but not its log-stream ARN. Read-only AWS `batch-get-builds` confirmed the exact failure.
- The least-privilege IAM correction was applied from a fresh full Terraform plan containing only one in-place role-policy update (zero resources added/deleted). A direct CodeBuild retry from the already-built main commit succeeded: `online-boutique-dev-deploy:1cbb4d83-0334-49bc-af80-ab6b8014dd4d`.
- All 12 application Deployments rolled out successfully, including two frontend replicas. All 13 Pods were Ready with zero restarts at verification. All 12 Services, including `frontend`, `frontend-external`, and `redis-cart`, are ClusterIP.
- The frontend Ingress provisioned active internet-facing ALB `k8s-onlinebo-frontend-5d3878fd15-1975334738.us-east-1.elb.amazonaws.com` in both public subnets. The target group uses IP targets on port 8080 and health path `/_healthz`; both frontend Pod IP targets reported healthy. A direct HTTP request to `/` returned HTTP 200 (0.44 seconds).
- A Chrome browser smoke check was blocked by the local browser with `ERR_BLOCKED_BY_CLIENT`; HTTP verification via curl and AWS target-health checks succeeded. There is no HTTPS yet: domain and ACM certificate remain owner prerequisites.

## Remaining work

1. Update the project journal with the final deployment and ALB verification results, then commit/push that documentation and the Terraform IAM fix via a feature PR.
2. Decide whether to add Gitleaks, Trivy, Checkov and SBOM generation to CI; none is wired in yet.
3. Provide a domain and DNS ownership plan before configuring ACM HTTPS and Route 53. Do not invent a hostname or request a certificate without it.
4. Review actual AWS costs and shut down the learning environment when the owner requests it. The current platform is live and incurs charges.

## Repository map

- `.github/workflows/ci.yml` - upstream tests, overlay validation, main-branch image build/push.
- `.github/workflows/deploy-main.yml` - invokes and monitors private CodeBuild deployment after successful main CI.
- `ci/buildspec-deploy.yml` - builds deployment inputs and applies the Kustomize overlay from CodeBuild.
- `kubernetes/aws/online-boutique/` - namespace, RBAC, frontend PDB, ALB Ingress, and upstream overlay.
- `kubernetes/aws/controller/` - controller Helm values and ServiceAccount template.
- `terraform/` - VPC/EKS/ECR/IAM/CodeBuild/controller infrastructure and backend bootstrap.
- `docs/project-journal.md` - chronological project activity and decisions.
- `docs/aws-milestone-5-alb-ingress.md` - ALB architecture, prerequisites, and costs.

## Tooling notes

- Local Docker daemon was unavailable, so CI builds images on GitHub-hosted runners.
- Go and .NET were unavailable locally; both test suites passed on GitHub Actions.
- Terraform format/validate, Actionlint, Ruby YAML parsing, Python compilation, Kustomize rendering, and `git diff --check` passed locally.
- Gitleaks was not installed locally. No Gitleaks/Trivy/Checkov/SBOM job has been added yet; prioritize the working application deployment, then add the security supply-chain jobs.
- OrbStack was disabled and left untouched. It is separate from this AWS task.
