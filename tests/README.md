# Tests

The repository is validated by a three-layer **test pyramid**. Every layer is
fast, hermetic and runs the same way locally and in CI — none of them needs a
running cluster or any cloud credentials.

```
        ▲   e2e          app-of-apps graph + offline ArgoCD acceptance
       ╱ ╲              (slowest, broadest reasoning, fewest tests)
      ╱───╲  integration  render overlays + kubeconform + env differentiation
     ╱─────╲ unit         static lint + schema + structure checks
    ╱───────╲            (fastest, most numerous)
```

Run a single layer:

```bash
bash tests/unit/run.sh
bash tests/integration/run.sh
bash tests/e2e/run.sh
```

All three share `tests/lib/common.sh`, which provides the `kustomize_build`
shim (standalone `kustomize`, falling back to `kubectl kustomize`) and a tiny
`pass` / `fail` / `assert_*` / `summary` framework. Any failing assertion exits
non-zero, so each script is CI-ready as-is.

## Layer 1 — unit (`tests/unit/run.sh`)

Pure static analysis; no rendering. The cheapest checks that catch the most
common mistakes:

- `yamllint` over the whole repo (enforced in CI; skipped locally if not
  installed)
- every `kustomization.yaml` really is a `Kustomization`, and each overlay
  references the base
- every base ArgoCD `Application` declares `project` / `source` / `destination`
  / `syncPolicy`
- no `Secret` manifests or embedded private keys are committed

## Layer 2 — integration (`tests/integration/run.sh`)

Renders the overlays end-to-end and checks how the pieces compose:

- both the `dev` and `prod` overlays render with kustomize and produce exactly
  the three workload Applications
- the rendered manifests pass `kubeconform -strict` against the Kubernetes
  schemas **and** the ArgoCD CRD catalog (Application / AppProject schemas are
  fetched from the [datreeio CRDs catalog](https://github.com/datreeio/CRDs-catalog))
- the render proves `dev` and `prod` are genuinely different environments: prod
  runs more replicas, and the two land in different namespaces with different
  ingress hosts

## Layer 3 — e2e (`tests/e2e/run.sh`)

Reasons about the whole app-of-apps graph the way ArgoCD would, but entirely
offline:

- **app-of-apps integrity** — `argocd/root-app.yaml` declares exactly one parent
  per environment, each parent lives in the `platform` project and points at the
  matching overlay path, and that path exists in the repo
- **ArgoCD acceptance** — every Application ArgoCD would reconcile (the two
  environment parents and the workload children each overlay renders) round-trips
  through `argocd admin app generate-spec --validate=false` without error,
  proving each spec is structurally valid

### Why e2e is dry-run only

A "real" e2e test would `kind create cluster`, install ArgoCD, apply the
root app and wait for everything to sync. We deliberately **don't** do that here:

- **Speed** — provisioning kind + ArgoCD and waiting on reconciliation turns a
  sub-second check into a multi-minute one, on every push.
- **Determinism** — a live sync pulls third-party Helm charts and depends on
  cluster timing, so it fails for reasons that have nothing to do with this repo.
- **Cost** — it needs no paid infrastructure, so the full pyramid runs on a
  vanilla GitHub-hosted runner.

Everything that can break in *this* repository — overlay wiring, schema
validity, environment differentiation and Application correctness — is provable
statically. Actually standing the platform up belongs to a manual/staging step,
documented in the root [README](../README.md) (local `kind` bootstrap) and the
"Production on AKS" section, not to per-commit CI.
