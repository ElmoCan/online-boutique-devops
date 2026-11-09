# Online Boutique rollback

## Preferred path: previous successful deployment

The `Rollback Online Boutique` workflow is manually dispatched from `main` and accepts a full Git commit SHA. It rejects commits that are not on `main`, and requires that the SHA has successful `CI and ECR build` and `Deploy Online Boutique` runs. CI success means the immutable image build and configured image security gate succeeded. The workflow then starts the existing private CodeBuild project with that exact source SHA and waits for completion. It does not rebuild or overwrite ECR tags.

1. Find the SHA of the last known-good `Deploy Online Boutique` run.
2. Open Actions → `Rollback Online Boutique` on `main`, enter that 40-character SHA, and run the workflow.
3. Confirm CodeBuild reports success and that all application Deployments roll out.
4. Verify frontend HTTP 200 through the current ALB DNS name and inspect the target group health.
5. Record the rollback SHA and reason in the project journal.

The rollback re-applies the manifests and immutable images from the selected source commit. It does not undo Terraform or AWS infrastructure changes.

## Emergency single-Deployment fallback

If CI/CodeBuild is unavailable and the frontend alone must be restored, an authorized operator can use `kubectl rollout history deployment/frontend -n online-boutique`, then `kubectl rollout undo deployment/frontend -n online-boutique --to-revision=<known-good-revision>`. This is an imperative recovery and creates drift from Git; follow it with a reviewed commit and normal pipeline deployment. Check `kubectl rollout status`, frontend endpoints, ALB targets, and HTTP 200 afterward.
