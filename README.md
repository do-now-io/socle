<div align="center">

# Socle

**An open source GitOps distribution for managed Kubernetes clusters:
EKS, GKE, AKS and Scaleway Kapsule.**

Pick your cloud, pick your modules. You get one signed OCI artifact that Flux
pulls, and upgrading the whole platform is a one-line change in Git.

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/do-now-io/socle/badge)](https://scorecard.dev/viewer/?uri=github.com/do-now-io/socle)
[![PR static checks](https://github.com/do-now-io/socle/actions/workflows/pr-static.yaml/badge.svg)](https://github.com/do-now-io/socle/actions/workflows/pr-static.yaml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[![Socle in 22 seconds](docs/assets/socle-demo.gif)](docs/assets/socle-demo.mp4)

<sub>Click the animation to watch the full-quality video with sound.</sub>

</div>

**Documentation: <https://do-now-io.github.io/socle/>**

> [!NOTE]
> **0.1.0 is the first release.** Before 1.0.0 a minor may break; every push
> to `main` publishes a signed alpha. See [Status](#status).

## Why Socle

- **One apply.** A single OpenTofu root creates the cluster, installs Flux on
  it and hands the catalog over. After that, OpenTofu steps away.
- **One version.** `socle_version` pins the OpenTofu modules and the Flux
  artifact together. An upgrade is one line in your tfvars.
- **Signed end to end.** Both artifacts are signed keyless with cosign. Flux
  checks the signature on every reconciliation, and you cannot turn that check
  off.
- **Mistakes fail at plan.** If you misspell a module name or an attribute,
  `tofu plan` rejects it and lists the allowed values. The value is not
  silently dropped.
- **No out-of-band scripts.** When a module needs cloud access, the module
  declares its own IAM through Crossplane. Adding a module never changes the
  cloud foundations.
- **Your values win.** Every module accepts any chart value in `values`.
  Secrets go in `values_secret`, so they never reach the OpenTofu state.

## How it works

```mermaid
flowchart LR
  tfvars["your main.tf<br/>socle_version · &lt;cloud&gt; · kube"]
  subgraph tofu ["tofu apply — once"]
    foundations["Foundations<br/>network · cluster · identities"]
    bootstrap["Bootstrap<br/>Cilium · Flux Operator · inputs"]
  end
  oci[("ghcr.io/do-now-io/socle/flux-modules<br/>cosign-signed OCI")]
  subgraph cluster ["Cluster — continuously"]
    flux["Flux<br/>pull · verify · render"]
    catalog["Catalog modules<br/>ArgoCD · monitoring · DNS · …"]
  end
  tfvars --> foundations --> bootstrap --> flux
  oci -- verified pull --> flux --> catalog
```

| Layer | What it is | Owned by |
| --- | --- | --- |
| **Foundations** | One OpenTofu module per cloud: network, managed cluster, node group, identities | OpenTofu, applied once |
| **Bootstrap** | Cilium and CoreDNS where the cloud doesn't provide them, then the Flux Operator and your validated inputs | OpenTofu, in the same apply |
| **Catalog** | À la carte modules, one Flux Operator `ResourceSet` each, rendered from your inputs | Flux, from the signed artifact |

How the parts fit, and why: [Architecture](https://do-now-io.github.io/socle/architecture/overview/).

## What you write

You write one `main.tf` per cluster, calling the socle's root for your cloud.
Under `kube`, list only the values that differ from the catalog defaults:

```hcl
# clusters/prod/main.tf (plus your state backend)
locals {
  socle_version = "0.1.0" # the only line an upgrade touches. x-release-please-version
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/clusters/aws?tag=${local.socle_version}"

  socle_version = local.socle_version

  aws = {
    region             = "eu-west-3"
    cluster_name       = "acme-prod"
    owner              = "platform"
    environment        = "prod"
    kubernetes_version = "1.37"
    availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
    cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
    gateway_certificate = { domain = "acme.example" }
  }

  kube = {
    argocd     = { domain = "argocd.acme.example" }
    monitoring = { traces = { enabled = true } }
  }
}
```

```sh
tofu init && tofu apply
kubectl -n flux-system get resourceset    # socle-root and one per module
```

The full walkthrough is the [AWS quickstart](docs/getting-started/aws.md),
and every option is documented in
[prod.tfvars.example](opentofu/clusters/aws/prod.tfvars.example). On Google
Cloud, the same through [opentofu/clusters/gcp](opentofu/clusters/gcp/README.md)
and the [GCP quickstart](docs/getting-started/gcp.md).

## The catalog

Each module is a Flux Operator `ResourceSet` you turn on or off under `kube`.
The version is the upstream application's, pinned in the module.

### Continuous delivery

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`argocd`](docs/catalog/argocd.md) | GitOps for your applications. Flux runs the socle, and ArgoCD runs your apps | 3.5.5 | on | All | |
| [`argocd_image_updater`](docs/catalog/argocd-image-updater.md) | New image tags in your registry reach your applications, without a commit | 1.3.1 | off | All | Needs `argocd`; with `repositories`, `crossplane` for its read-only access: an ECR role on AWS, an Artifact Registry reader binding on GCP |

### Monitoring

The stack's design: [Observability](docs/architecture/observability.md).

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`monitoring`](docs/catalog/monitoring.md) | The stack in one release: metrics, logs and traces storage, the cluster scraped, Grafana, and kube-prometheus-stack's alert rules | 0.96.0 | on | All | Traces and alerting off by default |
| [`otel_agent`](docs/catalog/otel-agent.md) | Node-level OpenTelemetry collector: container logs | 0.160.0 | on | All | Runs while monitoring's logs are on |
| [`otel_gateway`](docs/catalog/otel-gateway.md) | Cluster-level collector: your applications' OTLP and the Kubernetes events | 0.160.0 | on | All | |
| [`metrics_server`](docs/catalog/metrics-server.md) | The resource metrics API behind `kubectl top` and CPU or memory autoscaling | 0.9.0 | on | AWS | GKE, AKS and Kapsule ship their own |

### Security

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`kyverno`](docs/catalog/kyverno.md) | The Kyverno admission engine, with no policy | 1.19.1 | off | All | Its webhooks never see the socle's namespaces |
| [`kyverno_policies`](docs/catalog/kyverno-policies.md) | Pod Security Standards, requests required, no `latest` tag, a registry allow-list, all in Audit; `enforce` makes a policy a native refusal | 1.19.1 | off | All | Needs `kyverno`; judges your applications, never the socle |
| [`external_secrets`](docs/catalog/external-secrets.md) | Kubernetes Secrets read from the cloud's secret manager, kept in step when they rotate | 2.13.0 | off | All | With `crossplane`: read-only access on a secret-name prefix — its own role on AWS, a conditional binding on GCP — and the `secret-manager` store |
| [`reloader`](docs/catalog/reloader.md) | Rolls a workload when a ConfigMap or Secret it reads changes | 1.4.22 | off | All | Opt-in per workload, by annotation |

### Networking and exposure

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`gateway_api`](docs/catalog/gateway-api.md) | Gateway API CRDs and the shared `public` and `private` Gateways | 1.6.3 | on | All | On GCP the CRDs and the controller are GKE's: the module creates the shared Gateways on Google's load balancers |
| [`external_dns`](docs/catalog/external-dns.md) | Publishes routes into the cloud's DNS zone | 0.23.0 | off | All | Turned on for you on AWS and GCP once a certificate is set and Crossplane can give it access |

### Cloud resources

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`crossplane`](docs/catalog/crossplane.md) | Lets each module declare its own cloud IAM | 2.4.2 | off | All | Needed by `velero` and `karpenter`, and on AWS and GCP by `external_dns`, `keda` (`services`), `external_secrets` and `argocd_image_updater` (`repositories`) for their own access; on GCP no Google service account |

### Autoscaling

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`keda`](docs/catalog/keda.md) | Event-driven autoscaling, down to zero | 2.21.0 | off | All | |
| [`karpenter`](docs/catalog/karpenter.md) | Nodes for your workloads, launched for what is Pending, Spot and Graviton first, removed when empty; a private pool, and a public one for traffic-heavy workloads (no NAT Gateway) | 1.15.0 | off | AWS | Needs `crossplane`; GKE Autopilot provisions its own nodes |

### Backup

| Module | What it does | Version | Default | Clouds | Notes |
| --- | --- | --- | :---: | --- | --- |
| [`velero`](docs/catalog/velero.md) | Backup and restore of the applications' volumes and their objects, into the module's own bucket | 1.18.2 | off | AWS · GCP | Needs `crossplane`; on GCP Persistent Disk snapshots only |

Cilium and CoreDNS come before the catalog. On AWS and Azure the bootstrap
module installs them ahead of Flux. GKE and Kapsule run their own:
[Cilium before Flux](docs/architecture/cilium-before-flux.md).

## Clouds

| Cloud | Foundations | One-apply root | Docs |
| --- | :---: | :---: | --- |
| AWS · EKS | ✅ | ✅ [`clusters/aws`](opentofu/clusters/aws) | [AWS](docs/clouds/aws/index.md) |
| GCP · GKE | ✅ | ✅ [`clusters/gcp`](opentofu/clusters/gcp) | [GCP](docs/clouds/gcp/index.md) |
| Azure · AKS | ✅ | ⏳ | [Azure](docs/clouds/azure/index.md) |
| Scaleway · Kapsule | ✅ | ⏳ | [Scaleway](docs/clouds/scaleway/index.md) |

## Status

Socle's first release is **0.1.0**. Before 1.0.0, a breaking change bumps
the minor.

- The foundations modules exist for all four clouds. The single-apply root
  exists for AWS and GCP, so far.
- On GCP every catalog module that runs on AWS runs too, metrics-server
  and karpenter aside (GKE serves its own metrics API, and Autopilot
  provisions its own nodes), each cloud-backed one with its own access
  through Crossplane and no Google service account. Its proof is a GKE
  Autopilot sandbox, by hand: floci-gcp has no Cloud DNS and no Workload
  Identity, so CI renders and plans GCP but runs no GKE e2e. One socle
  cluster per GCP project, and a fresh project needs its quotas raised
  first ([prerequisites](docs/clouds/gcp/prerequisites.md#quotas)).
- Every catalog module ships its own [Chainsaw](https://kyverno.github.io/chainsaw/)
  suite. CI runs these suites on floci,
  an AWS emulator with k3s, with one job per module and cloud. Each job applies
  OpenTofu, turns the module on and off, and ends with `tofu destroy`.
- Every push to `main` publishes `<next>-alpha.N`, signed. To release, you
  merge the release-please PR, which re-tags that same alpha. Nothing is
  rebuilt.
- Both packages are public: the cluster pulls the Flux artifact,
  `ghcr.io/do-now-io/socle/flux-modules`, and `tofu init` the OpenTofu
  modules, `ghcr.io/do-now-io/socle/opentofu-modules`, with no credential.

## Security

See [SECURITY.md](SECURITY.md). Report vulnerabilities through
[private vulnerability reporting](https://github.com/do-now-io/socle/security/advisories/new),
never in public issues.

## License

[Apache-2.0](LICENSE)
