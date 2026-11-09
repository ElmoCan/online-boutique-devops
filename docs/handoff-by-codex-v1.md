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
- Deployment workflow [run 42611266598](https://github.com/ElmoCan/online-boutique-devops/actions/runs/42611266598) failed. It authenticated to AWS and successfully started the private CodeBuild project, then observed CodeBuild status `FAILED`. The exact build failure is not known yet. The local AWS CLI could not connect to the CodeBuild regional endpoint to retrieve build phases/log references.
- Therefore, do **not** claim the application is deployed. The last confirmed state is images pushed to ECR, but CodeBuild deployment failed. Application Pods, Services, Ingress, ALB and frontend access have not been verified after the failure.

## Exact next steps

1. Inspect CodeBuild build `online-boutique-dev-deploy:ce5b23ed-e86b-480d-ae91-d42f6f735fbc` in AWS Console (region `us-east-1`) and open its CloudWatch logs. Determine the first failing build phase and fix only that cause. If AWS API access is available, use read-only `batch-get-builds` and CloudWatch log reads; do not print credentials.
2. Review `ci/buildspec-deploy.yml`, `scripts/configure-ecr-kustomization.py`, CodeBuild environment variables and source settings in `terraform/codebuild.tf`. Confirm CodeBuild can fetch this repository/submodule and that `AWS_REGION`, `EKS_CLUSTER_NAME`, and ECR image prefix are present.
3. Check whether the CodeBuild source checkout points to the exact main commit and contains the required manifest, Kustomize overlay, script, and submodule. Do not assume `workflow_run`'s source commit is checked out automatically; the CodeBuild project's GitHub source behavior must be verified.
4. After the fix, publish through a feature branch and PR, wait for checks, then follow the established merge policy. A successful main CI run should trigger the deployment workflow again.
5. Verify rollout: Deployments and Pods Ready; health probes passing; Services and endpoints present; all app Services/Redis ClusterIP; no rollout errors or failed events. Inspect logs if anything is unhealthy.
6. Verify ALB Ingress events and target health. Test the ALB DNS address over HTTP. Confirm only the frontend is reachable publicly and workers stay private.
7. HTTPS is pending an owner-provided domain and a public ACM certificate in `us-east-1`. No domain/certificate was available in the last inspection; do not invent a hostname or request a certificate without it.
8. Append verified results, the CodeBuild error and fix, application status, ALB URL, and any cost changes to `docs/project-journal.md` and update the milestone documentation.

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
