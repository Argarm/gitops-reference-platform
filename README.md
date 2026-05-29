# gitops-reference-platform

A reference GitOps platform built around ArgoCD's **app-of-apps** pattern, with two
environments (`dev` / `prod`), reproducible locally on [kind](https://kind.sigs.k8s.io/)
for CI and documented for production on AKS.

Every manifest is statically validated, rendered with Kustomize, and dry-run checked
against ArgoCD on every pull request — **no live cluster is ever spun up in CI**.

> Full architecture, bootstrap and test-strategy documentation lands with the project.
> See the sections added in the documentation commit.

## License

[MIT](./LICENSE) © 2026 Aarón García Marrero
