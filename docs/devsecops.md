# DevSecOps checks

This repository keeps Google Online Boutique as a pinned upstream Git submodule. The workflows scan this DevOps repository, its Terraform configuration, the pinned application dependencies, and the immutable application images built for ECR. They do not modify upstream source.

## GitHub Actions

| Check | Tool/version | Scope | Failure behavior |
|---|---|---|---|
| Secret scanning | Gitleaks Action `v3.0.0` pinned to commit `e0c47f4f8be36e29cdc102c57e68cb5cbf0e8d1e`; Gitleaks CLI `8.30.1` | Pull request commit range, plus all reachable repository history (`git log --all`) on PRs and pushes to `main` | Any finding or scanner error fails the security job. |
| Dependency scan | Trivy Action `v0.36.0` pinned to `ed142fd0673e97e23eac54620cfb913e5ce36c25`; Trivy CLI `v0.76.1` | Pinned `application/upstream` tree; HIGH and CRITICAL fixed vulnerabilities in supported dependency manifests | Findings with available fixes fail the job. Unfixed findings are suppressed to focus the gate on actionable issues. |
| Infrastructure scan | Checkov Action pinned to commit `45edc9d8856b664db2ec251f5f8632361f0a67aa`, using Checkov CLI/container `3.4.3` | Terraform configuration under `terraform/` | Failed checks fail the job; no soft-fail or baseline is configured. |
| Image scan and SBOM | Trivy `v0.76.1` through the pinned Trivy Action | Each Google application image present in the upstream release manifest after it is pushed to its immutable ECR `GITHUB_SHA` tag | HIGH and CRITICAL fixed vulnerabilities fail the CI workflow and therefore block the `workflow_run` deployment trigger. |
| SBOM artifacts | Trivy CycloneDX | One SBOM per scanned ECR image | Uploaded as a GitHub Actions artifact and retained for 7 days. |

`CI and ECR build` still runs its full application tests and Kustomize validation for every pull request. Its `main` push trigger is limited to application, deployment overlay, deploy buildspec, image mapping script, and CI workflow changes. Documentation-only pushes do not rebuild or deploy the application. The separate security workflow still scans pull requests and every push to `main`.

Image tags stay immutable: Skaffold pushes `$GITHUB_SHA`; the image scan matrix uses the same SHA; the deployment workflow sends the triggering CI run's `head_sha` to CodeBuild; and CodeBuild renders that source SHA into the Kubernetes overlay. A failed image scan makes the CI workflow unsuccessful, so the existing deploy workflow's success condition does not start CodeBuild.

## Safe handling of secret findings

The Gitleaks action is pinned and the CLI version is explicit. The action's built-in scan uses redaction. PR comments, SARIF artifact upload, and job summaries are disabled so a finding cannot be copied into those extra output surfaces. The additional full-history scan captures all CLI output in a temporary runner file, deletes it, and reports only pass/fail; its enforcement step emits a generic error. The workflow grants only `contents: read` and `pull-requests: read` to the Gitleaks job.

The job also creates a high-entropy synthetic GitHub-token-shaped string at runtime, commits it only in an isolated temporary repository under the runner's temp directory, and verifies that Gitleaks detects it and redacts it from its report/log. The fixture and report are deleted on exit. No synthetic credential is checked into this repository. Gitleaks Action does not require a license key for a personal GitHub account; if the repository is moved under an organization, the action owner requires a license secret.

The full-history scan checks all reachable refs fetched by checkout (`fetch-depth: 0`). The upstream Git submodule's own Git object history is outside this repository scan; Trivy scans its checked-out source and dependency manifests. Secret detection should still be enabled for the upstream repository separately if its history needs coverage.

If Gitleaks fails, use a private local scan with `gitleaks git --redact=100 --log-opts="--all" .` and do not paste unredacted output into a PR, issue, chat, or CI log. If a real credential was exposed, revoke or rotate it first, then remove it from current files and follow the repository's approved history-cleanup process. For a confirmed false positive, add only its reviewed Gitleaks fingerprint to `.gitleaksignore`; do not weaken a global rule. This workflow intentionally does not upload a report with finding details.

For Trivy findings, update the affected upstream dependency/image or use a reviewed, narrowly scoped ignore for a verified false positive. Do not lower the severity gate to hide a finding. For Checkov, fix the Terraform control or document a specific, justified suppression in a follow-up review; do not enable soft-fail to make a failing scan appear green.

## Running scans locally

Install the pinned CLI versions in an isolated development environment, then run:

```sh
gitleaks git --redact=100 --log-opts="--all" .
trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed application/upstream
checkov --directory terraform --framework terraform
```

The image scan and SBOM generation require an authenticated ECR image tagged with a commit SHA. The CI workflow performs those steps after building and pushing the images. Downloaded SBOM artifacts contain package metadata and are not a substitute for a vulnerability report or a signature/attestation.

## Current limitations

- Dependency scanning covers formats supported by the pinned Trivy CLI and present in the pinned upstream source; unsupported or absent lockfiles cannot provide complete dependency inventories.
- The image gate is after ECR push because it scans the exact immutable commit tag. A failed scan leaves that commit-tagged image in ECR but prevents application deployment; immutable tags are not overwritten on retry.
- Checkov scans Terraform source, not a Terraform plan or live AWS state.
- Gitleaks scans the DevOps repository history, not history inside the upstream submodule.
- The Trivy threshold is HIGH/CRITICAL and ignores unfixed issues. Review the scan result and update dependencies rather than treating this threshold as proof of zero risk.
- GitHub Actions job logs do not display the Gitleaks full-history findings. This protects secret values but means maintainers must reproduce the redacted local scan to identify the finding path/rule.


## Initial GitHub Actions results (PR #11)

Workflow run `42659088680` completed with Gitleaks passing, including the event scan, full reachable-history scan, and synthetic detection/redaction check. The Trivy filesystem dependency scan failed on actionable HIGH/CRITICAL advisories in the pinned Google source tree. Examples in its report include `golang.org/x/net` CVEs `CVE-2026-78661` and `CVE-2026-78669`, `protobufjs` `CVE-2026-41242`, and Python package findings. These are source-tree findings; PR runs do not build/push ECR images, so the image scan and SBOM job did not run. The Google submodule is already pinned to upstream's latest commit (`c7cb6d5`, 2026-10-27); no upstream fix was available at the time of this check. The gate remains enabled. Do not lower severity or add blanket ignores; update the upstream pin when Google publishes a reviewed fix, then rerun the image scan.

Checkov's full Terraform scan also failed on the existing baseline (88 passed, 15 failed). Reported controls span CodeBuild IAM/network egress, CloudWatch log encryption/retention, ECR encryption, Terraform source pinning, and backend S3 controls. The findings predate PR #11 and no Terraform file is changed by that PR. They are not waived or soft-failed; the baseline needs a separately reviewed remediation before the full scan can pass.

The existing application test workflow run `42659088572` passed its Go tests, .NET cart-service tests, and AWS Kustomize validation. PR #11 remains unmerged; no AWS or Kubernetes resources were changed for this security implementation.
