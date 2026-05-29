#!/usr/bin/env bash
#
# Shared helpers for the test pyramid (unit / integration / e2e).
#
# Sourced by each layer's run.sh. Provides:
#   * REPO_ROOT          — absolute path to the repository root
#   * kustomize_build    — render a kustomization (standalone kustomize if
#                          available, otherwise `kubectl kustomize`)
#   * pass / fail / summary — a tiny assertion + reporting framework
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Kustomize shim: prefer the standalone, pinned `kustomize`; fall back to the
# version embedded in `kubectl`. Both accept `<verb> <path>`.
if command -v kustomize >/dev/null 2>&1; then
  _KUSTOMIZE=(kustomize build)
elif command -v kubectl >/dev/null 2>&1; then
  _KUSTOMIZE=(kubectl kustomize)
else
  echo "ERROR: neither 'kustomize' nor 'kubectl' is available on PATH" >&2
  exit 1
fi

kustomize_build() {
  "${_KUSTOMIZE[@]}" "$1"
}

# --- assertion framework ---------------------------------------------------
_PASS=0
_FAIL=0

pass() { _PASS=$((_PASS + 1)); printf '  [ \033[32mPASS\033[0m ] %s\n' "$1"; }
fail() { _FAIL=$((_FAIL + 1)); printf '  [ \033[31mFAIL\033[0m ] %s\n' "$1"; }

# assert_eq <expected> <actual> <message>
assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

# assert_gt <a> <b> <message>  — passes when a > b (integers)
assert_gt() {
  if [ "$1" -gt "$2" ]; then pass "$3"; else fail "$3 (expected $1 > $2)"; fi
}

# assert_ne <a> <b> <message>  — passes when a != b
assert_ne() {
  if [ "$1" != "$2" ]; then pass "$3"; else fail "$3 (both were '$1')"; fi
}

summary() {
  echo "------------------------------------------------------------"
  printf 'Passed: %d   Failed: %d\n' "$_PASS" "$_FAIL"
  [ "$_FAIL" -eq 0 ] || exit 1
}
