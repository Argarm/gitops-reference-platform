#!/usr/bin/env bash
#
# Layer 2 — Integration tests.
#
# These tests render the real overlays and check how the pieces fit together.
# Unlike the unit layer they exercise kustomize end-to-end and validate the
# rendered manifests against the upstream Kubernetes + ArgoCD CRD schemas:
#
#   1. each overlay (dev, prod) renders cleanly with kustomize
#   2. every rendered manifest passes `kubeconform -strict` against the
#      Kubernetes schemas AND the ArgoCD CRD catalog
#   3. the rendered output proves dev and prod are genuinely different
#      environments: prod runs more replicas, and the two land in different
#      namespaces with different ingress hosts
#
# Requires: kustomize (or kubectl), kubeconform, yq (v4). kubeconform fetches
# the ArgoCD CRD schemas over the network from the datreeio catalog.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

cd "$REPO_ROOT"

echo "== Layer 2: integration =="

# CRD schemas not shipped with Kubernetes (ArgoCD Application/AppProject) are
# resolved from the community datreeio catalog.
CRD_SCHEMA='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- 1. overlays render -----------------------------------------------------
echo "-- kustomize render --"
for env in dev prod; do
  if kustomize_build "kustomize/overlays/${env}" > "${WORKDIR}/${env}.yaml" 2> "${WORKDIR}/${env}.err"; then
    pass "overlay '${env}' renders"
  else
    fail "overlay '${env}' failed to render"
    cat "${WORKDIR}/${env}.err"
  fi
done

# Each overlay must render exactly the three workload Applications.
for env in dev prod; do
  count="$(yq ea 'select(.kind == "Application") | .metadata.name' "${WORKDIR}/${env}.yaml" | grep -Ecv '^(---)?$')"
  assert_eq "3" "$count" "overlay '${env}' renders 3 Applications"
done

# --- 2. kubeconform strict, CRD-aware --------------------------------------
echo "-- kubeconform (strict, CRD-aware) --"
for env in dev prod; do
  if out="$(kubeconform -strict -summary \
      -schema-location default \
      -schema-location "$CRD_SCHEMA" \
      "${WORKDIR}/${env}.yaml" 2>&1)"; then
    pass "overlay '${env}' passes kubeconform -strict"
  else
    fail "overlay '${env}' fails kubeconform -strict"
    echo "$out"
  fi
done

# --- 3. dev and prod are genuinely different environments ------------------
echo "-- environment differentiation --"

# yq helper: pull a scalar from the Application named "$2" in rendered file "$1".
app_field() { yq ea "select(.kind == \"Application\" and .metadata.name == \"$2\") | $3" "$1"; }

# prod scales out more than dev (all three workloads).
for app in podinfo httpbin guestbook; do
  dev_rc="$(app_field "${WORKDIR}/dev.yaml"  "${app}-dev"  '.spec.source.helm.valuesObject.replicaCount')"
  prod_rc="$(app_field "${WORKDIR}/prod.yaml" "${app}-prod" '.spec.source.helm.valuesObject.replicaCount')"
  assert_gt "$prod_rc" "$dev_rc" "prod '${app}' replicaCount ($prod_rc) > dev ($dev_rc)"
done

# dev and prod deploy into different namespaces (all three workloads).
for app in podinfo httpbin guestbook; do
  dev_ns="$(app_field "${WORKDIR}/dev.yaml"  "${app}-dev"  '.spec.destination.namespace')"
  prod_ns="$(app_field "${WORKDIR}/prod.yaml" "${app}-prod" '.spec.destination.namespace')"
  assert_ne "$dev_ns" "$prod_ns" "'${app}' namespace differs (dev '$dev_ns' vs prod '$prod_ns')"
done

# dev and prod expose different ingress hosts (the ingress-capable workloads).
for app in podinfo httpbin; do
  dev_host="$(app_field "${WORKDIR}/dev.yaml"  "${app}-dev"  '.spec.source.helm.valuesObject.ingress.hosts[0].host')"
  prod_host="$(app_field "${WORKDIR}/prod.yaml" "${app}-prod" '.spec.source.helm.valuesObject.ingress.hosts[0].host')"
  assert_ne "$dev_host" "$prod_host" "'${app}' ingress host differs (dev '$dev_host' vs prod '$prod_host')"
done

summary
