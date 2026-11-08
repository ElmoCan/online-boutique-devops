#!/usr/bin/env bash
set -euo pipefail

# The currently published v0.10.7 application images are linux/amd64 only.
# OrbStack can run these under emulation; explicit platform selection places
# them in its local image store so Kubernetes does not try to pull remotely.
registry="us-central1-docker.pkg.dev/online-boutique-ci/microservices-demo"
tag="v0.10.7"
for service in \
  adservice cartservice checkoutservice currencyservice emailservice frontend \
  paymentservice productcatalogservice recommendationservice shippingservice
do
  docker pull --platform linux/amd64 "$registry/$service:$tag"
done

docker pull --platform linux/arm64 redis:alpine
