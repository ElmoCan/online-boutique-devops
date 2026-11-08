#!/bin/sh
# kube-prometheus-stack 93.1.0 publishes these two v0.95.1 images as AMD64 only.
# OrbStack can emulate them on ARM64; the rest of the stack uses native ARM64 images.
set -eu

docker pull --platform linux/amd64 quay.io/prometheus-operator/prometheus-operator:v0.95.1
docker pull --platform linux/amd64 quay.io/prometheus-operator/prometheus-config-reloader:v0.95.1
