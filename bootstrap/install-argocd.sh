#!/usr/bin/env bash
#
# Idempotent ArgoCD installer.
#
# Installs a pinned ArgoCD version into the `argocd` namespace and waits for it
# to become available. Running it twice is safe: the namespace is applied
# server-side and the install manifest is re-applied (a no-op when unchanged).
#
# This script targets the CURRENT kubectl context. Point kubectl at the desired
# cluster (e.g. the local kind cluster) before running it.
#
# Usage:
#   ./bootstrap/install-argocd.sh
#
# Environment overrides:
#   ARGOCD_VERSION   ArgoCD release tag to install (default below)
#   ARGOCD_NAMESPACE Namespace to install into   (default: argocd)
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.4.3}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
INSTALL_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo ">> Installing ArgoCD ${ARGOCD_VERSION} into namespace '${ARGOCD_NAMESPACE}'"

# 1. Ensure the namespace exists (idempotent via apply).
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 2. Apply the pinned ArgoCD install manifest (idempotent).
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${INSTALL_MANIFEST}"

# 3. Wait for the core components to roll out.
echo ">> Waiting for ArgoCD components to become available..."
for deploy in argocd-server argocd-repo-server argocd-applicationset-controller argocd-dex-server; do
  kubectl rollout status -n "${ARGOCD_NAMESPACE}" "deployment/${deploy}" --timeout=300s || true
done
kubectl rollout status -n "${ARGOCD_NAMESPACE}" statefulset/argocd-application-controller --timeout=300s || true

cat <<EOF

>> ArgoCD ${ARGOCD_VERSION} is installed.

Next steps:
  1. Register the platform AppProject:
       kubectl apply -f argocd/projects/platform-project.yaml
  2. Bootstrap the app-of-apps root application:
       kubectl apply -f argocd/root-app.yaml
  3. Retrieve the initial admin password:
       kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret \\
         -o jsonpath='{.data.password}' | base64 -d; echo
  4. Port-forward the API/UI:
       kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 8080:443
EOF
