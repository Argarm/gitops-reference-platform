# Bootstrap

Everything needed to stand the platform up on a local
[kind](https://kind.sigs.k8s.io/) cluster. The same steps work against any
cluster (including AKS — see the [Production on AKS](../README.md#production-on-aks)
section); only the cluster underneath changes.

## Contents

| File                | Purpose                                                          |
| ------------------- | --------------------------------------------------------------- |
| `kind-config.yaml`  | Reproducible single-node kind cluster (node image pinned by digest, ingress ports mapped to localhost). |
| `install-argocd.sh` | Idempotent installer for a pinned ArgoCD release; waits for the core components to roll out. |

## Prerequisites

- [`kind`](https://kind.sigs.k8s.io/) and a container runtime (Docker / Podman)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/)

## Steps

### 1. Create the cluster

```bash
kind create cluster --name gitops-ref --config bootstrap/kind-config.yaml
```

This creates a single control-plane node from a digest-pinned image, labelled
`ingress-ready=true` and with host ports 80/443 mapped so an ingress controller
is reachable at `localhost`.

### 2. Install ArgoCD

```bash
./bootstrap/install-argocd.sh
```

The script applies the `argocd` namespace and a pinned ArgoCD install manifest
(both idempotent — re-running is a no-op when nothing changed) and waits for the
server, repo-server, applicationset controller, dex and the application
controller to become available. Override the version or namespace if needed:

```bash
ARGOCD_VERSION=v3.4.3 ARGOCD_NAMESPACE=argocd ./bootstrap/install-argocd.sh
```

> The script targets the **current** kubectl context. Make sure `kubectl` points
> at the cluster you intend to install into before running it.

### 3. Register the project and bootstrap the app-of-apps

```bash
kubectl apply -f argocd/projects/platform-project.yaml
kubectl apply -f argocd/root-app.yaml
```

`platform-project.yaml` creates the `platform` AppProject that scopes which
repos may be deployed and into which namespaces. `root-app.yaml` is the
app-of-apps root: applying it brings up the `platform-dev` and `platform-prod`
parents, which render the dev and prod overlays and, in turn, every workload.

### 4. Access the UI

```bash
# Initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Port-forward the API/UI to https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Log in as `admin` with the password above. ArgoCD will show the full
app-of-apps tree reconciling toward the state declared in Git.

## Teardown

```bash
kind delete cluster --name gitops-ref
```

## Note on CI

CI never runs these scripts — it validates and dry-runs the manifests entirely
offline (see [`tests/README.md`](../tests/README.md)). This directory exists for
local end-to-end experimentation and as the documented, reproducible cluster
shape that production environments mirror.
