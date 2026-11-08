# Local Online Boutique on OrbStack Kubernetes

This deployment uses Google's upstream release manifest directly from the `application/upstream` submodule, pinned to the upstream commit recorded by Git. The root `kustomization.yaml` contains only local cluster adjustments; upstream source, Dockerfiles, and manifests remain unchanged.

## Image architecture

The upstream `v0.10.7` app images are published as `linux/amd64`. OrbStack's Kubernetes node is `linux/arm64`; the product catalog image was verified running under OrbStack emulation. `scripts/pull-upstream-images.sh` loads each upstream AMD64 image into OrbStack so Kubernetes can use the local images. Redis and the load-generator BusyBox init image support ARM64.

## Deploy

```sh
git submodule update --init --recursive
./scripts/pull-upstream-images.sh
kubectl create namespace online-boutique --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k .
kubectl wait --for=condition=Available deployment --all -n online-boutique --timeout=10m
kubectl port-forward -n online-boutique svc/frontend 8080:80
```

Then open <http://localhost:8080>. The local Kustomize config changes `frontend-external` to `ClusterIP`; the app is reachable locally only through port-forward. No cloud resources or monitoring are part of this deployment.

## Components

The local Kustomize config disables the optional load generator because synthetic traffic under AMD64 emulation made the cart service miss its upstream 1-second probe. All application services and Redis remain enabled. AMD64 emulation is less efficient than native ARM64 execution.
