#!/usr/bin/env python3
"""Map upstream release image names to this commit's private ECR images."""

import os
import re
from pathlib import Path

release = Path("application/upstream/release/kubernetes-manifests.yaml")
overlay = Path("kubernetes/aws/online-boutique/kustomization.yaml")
repository_prefix = os.environ["ECR_REPOSITORY_PREFIX"].rstrip("/")
image_tag = os.environ.get("CODEBUILD_RESOLVED_SOURCE_VERSION", "").strip()
if not image_tag:
    raise SystemExit("CODEBUILD_RESOLVED_SOURCE_VERSION is empty")

images = []
for upstream_image in re.findall(r"(?m)^\s*image:\s*([^\s]+)", release.read_text()):
    if not upstream_image.startswith(
        "us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo/"
    ):
        continue
    image_name = upstream_image.rsplit("/", 1)[1].split(":", 1)[0]
    source_name = upstream_image.rsplit(":", 1)[0]
    images.append((source_name, f"{repository_prefix}/{image_name}", image_tag))

if not images:
    raise SystemExit("No Google Online Boutique release images were found")

text = overlay.read_text().rstrip() + "\n\nimages:\n"
for source, target, tag in images:
    text += f"  - name: {source}\n    newName: {target}\n    newTag: {tag}\n"
overlay.write_text(text)
print(f"Mapped {len(images)} upstream application images to ECR at {image_tag}")
