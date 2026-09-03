# Socle

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/do-now-io/socle/badge)](https://scorecard.dev/viewer/?uri=github.com/do-now-io/socle)
[![PR static checks](https://github.com/do-now-io/socle/actions/workflows/pr-static.yaml/badge.svg)](https://github.com/do-now-io/socle/actions/workflows/pr-static.yaml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Open source GitOps distribution for managed Kubernetes clusters — EKS, GKE,
AKS and Scaleway Kapsule.

Pick your cloud, pick your modules. Socle ships as one signed OCI artifact
pulled by Flux: upgrading your whole platform means bumping one version in Git.

## How it works

- **Foundations** — one OpenTofu root module per cloud: network, managed
  cluster, identities, Flux bootstrap. OpenTofu provisions and steps away.
- **Catalog** — à la carte modules (cert-manager, external-dns,
  monitoring, ...) shipped as HelmReleases. Cloud resources a module needs
  (IAM roles, DNS access, ...) are provisioned in-cluster by Crossplane —
  100% GitOps, no out-of-band scripts.
- **Upgrades** — the whole socle is published as a cosign-signed,
  SemVer-tagged OCI artifact. Your cluster pins one tag; Flux pulls,
  verifies and reconciles the rest in dependency order.

## Status

Pre-0.1.0 — under active construction. Nothing is installable yet.

## Security

See [SECURITY.md](SECURITY.md). Please report vulnerabilities through
[private vulnerability reporting](https://github.com/do-now-io/socle/security/advisories/new),
never in public issues.

## License

[Apache-2.0](LICENSE)
