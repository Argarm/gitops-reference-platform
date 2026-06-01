#!/usr/bin/env bash
#
# Layer 3 — End-to-end tests.
#
# The top of the pyramid: it reasons about the whole app-of-apps graph the way
# ArgoCD itself would, but WITHOUT provisioning a cluster or talking to a server.
# Everything here is offline and deterministic:
#
#   1. app-of-apps integrity — the root Application declares one parent per
#      environment, each parent lives in the `platform` project and points at the
#      matching overlay path, and that path actually exists in the repo
#   2. ArgoCD acceptance — every Application that ArgoCD would reconcile (the two
#      environment parents AND the workload children rendered by each overlay) is
#      a structurally valid Application: it round-trips through
#      `argocd admin app generate-spec` without error
#
# Why dry-run only: spinning up kind + ArgoCD and waiting for syncs is slow,
# flaky and adds nothing this layer can't already prove statically. See
# tests/README.md for the full rationale.
#
# Requires: kustomize (or kubectl), argocd (v3 CLI), yq (v4).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

cd "$REPO_ROOT"

echo "== Layer 3: e2e =="

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

ROOT_APP="argocd/root-app.yaml"

# validate_apps <multi-doc-manifest> <label>
#
# Splits a manifest into individual Application documents and feeds each through
# `argocd admin app generate-spec --validate=false`. That parses and normalizes
# the spec entirely offline (no repo or cluster contact), so a non-zero exit or
# error means the Application is malformed.
validate_apps() {
  local file="$1" label="$2" name single out
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    single="${WORKDIR}/app-${name}.yaml"
    yq ea "select(.kind == \"Application\" and .metadata.name == \"$name\")" "$file" > "$single"
    if out="$(argocd admin app generate-spec -f "$single" --validate=false -o yaml 2>&1)"; then
      pass "argocd accepts ${label} Application '${name}'"
    else
      fail "argocd rejects ${label} Application '${name}'"
      echo "$out"
    fi
  done < <(yq ea 'select(.kind == "Application") | .metadata.name' "$file" | grep -Ev '^(---)?$')
}

# --- 1. app-of-apps integrity ----------------------------------------------
echo "-- app-of-apps integrity --"

# Exactly the two environment parents, nothing more.
parents="$(yq ea 'select(.kind == "Application") | .metadata.name' "$ROOT_APP" | grep -Ev '^(---)?$' | sort | tr '\n' ' ')"
assert_eq "platform-dev platform-prod " "$parents" "root-app declares platform-dev + platform-prod"

for env in dev prod; do
  name="platform-${env}"
  proj="$(yq ea "select(.metadata.name == \"$name\") | .spec.project" "$ROOT_APP")"
  path="$(yq ea "select(.metadata.name == \"$name\") | .spec.source.path" "$ROOT_APP")"
  assert_eq "platform" "$proj" "'${name}' belongs to the platform project"
  assert_eq "kustomize/overlays/${env}" "$path" "'${name}' targets the ${env} overlay"
  if [ -d "$REPO_ROOT/$path" ]; then
    pass "'${name}' overlay path '${path}' exists in the repo"
  else
    fail "'${name}' overlay path '${path}' is missing"
  fi
done

# --- 2. ArgoCD accepts every Application it would reconcile -----------------
echo "-- argocd dry-run (offline spec validation) --"

# The two environment parents.
validate_apps "$ROOT_APP" "root"

# The workload children each overlay renders.
for env in dev prod; do
  if kustomize_build "kustomize/overlays/${env}" > "${WORKDIR}/${env}.yaml" 2>/dev/null; then
    validate_apps "${WORKDIR}/${env}.yaml" "${env}-overlay"
  else
    fail "could not render overlay '${env}' for e2e validation"
  fi
done

summary
