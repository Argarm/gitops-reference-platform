#!/usr/bin/env bash
#
# Layer 1 — Unit tests.
#
# Fast, static checks that need no cluster and no rendering:
#   1. yamllint every YAML file in the repository
#   2. every kustomization.yaml is a valid Kustomization, and each overlay
#      references the base
#   3. every ArgoCD Application declares project / source / destination /
#      syncPolicy
#   4. no hardcoded secrets are present in any manifest
#
# Requires: yq (v4). yamllint is required in CI; locally it is skipped with a
# warning if not installed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

cd "$REPO_ROOT"

echo "== Layer 1: unit =="

# --- 1. yamllint -----------------------------------------------------------
echo "-- yamllint --"
if command -v yamllint >/dev/null 2>&1; then
  if yamllint -c .yamllint.yml .; then
    pass "yamllint: no errors"
  else
    fail "yamllint reported errors"
  fi
elif [ -n "${CI:-}" ]; then
  fail "yamllint not installed (required in CI)"
else
  printf '  [ \033[33mSKIP\033[0m ] yamllint not installed locally (CI enforces it)\n'
fi

# --- 2. kustomization validity + overlay -> base reference -----------------
echo "-- kustomization structure --"
while IFS= read -r kfile; do
  kind="$(yq e '.kind' "$kfile")"
  assert_eq "Kustomization" "$kind" "kind: Kustomization in ${kfile#"$REPO_ROOT"/}"
done < <(find kustomize -name kustomization.yaml)

for overlay in dev prod; do
  kfile="kustomize/overlays/${overlay}/kustomization.yaml"
  if yq e '.resources[]' "$kfile" | grep -qx '../../base'; then
    pass "overlay '${overlay}' references ../../base"
  else
    fail "overlay '${overlay}' does not reference ../../base"
  fi
done

# --- 3. ArgoCD Application required fields ----------------------------------
echo "-- ArgoCD Application schema --"
while IFS= read -r afile; do
  # Names of Application documents missing any required key. `source` is
  # satisfied by either the singular `source` or the multi-source `sources`.
  bad="$(yq ea '
    select(.kind == "Application")
    | select(
        (.spec.project == null)
        or (.spec.destination == null)
        or (.spec.syncPolicy == null)
        or ((.spec.source == null) and (.spec.sources == null))
      )
    | .metadata.name
  ' "$afile")"
  rel="${afile#"$REPO_ROOT"/}"
  if [ -z "$bad" ]; then
    pass "all Applications in ${rel} declare project/source/destination/syncPolicy"
  else
    fail "${rel}: incomplete Application(s): ${bad//$'\n'/, }"
  fi
done < <(grep -rl "kind: Application" kustomize/base/apps argocd)

# --- 4. no hardcoded secrets ------------------------------------------------
echo "-- no hardcoded secrets --"
secret_resources="$(grep -rl "kind: Secret" kustomize argocd bootstrap 2>/dev/null || true)"
if [ -z "$secret_resources" ]; then
  pass "no Secret manifests committed"
else
  fail "Secret manifest(s) found: ${secret_resources//$'\n'/, }"
fi

if grep -rIE -- "-----BEGIN [A-Z ]*PRIVATE KEY-----" kustomize argocd bootstrap tests >/dev/null 2>&1; then
  fail "embedded private key material detected"
else
  pass "no embedded private key material"
fi

summary
