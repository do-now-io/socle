---
title: Compatibility
description: The OpenTofu, provider, Flux, Kubernetes and chart versions each socle release pins or requires, and where it was tested.
sidebar:
  order: 3
---

What one socle version pins and requires; they move with `socle_version`
([Upgrade the socle](../guides/upgrade.md)).

## 0.1.0

### Tooling and providers

| Component | Version | Source |
| --- | --- | --- |
| OpenTofu | `>= 1.13`; CI runs `1.13.0` | every `versions.tf`; `tofu_version` in the workflows |
| `hashicorp/aws` | `>= 6.0, < 7.0` | `opentofu/aws`, `opentofu/bootstrap`, `opentofu/clusters/aws` |
| `hashicorp/helm` | `>= 3.0, < 4.0` | `opentofu/bootstrap`, `opentofu/clusters/aws` |
| `hashicorp/google` | `>= 8.0, < 9.0` | `opentofu/gcp` |
| `hashicorp/azurerm` | `>= 4.0, < 5.0` | `opentofu/azure` |
| `scaleway/scaleway` | `>= 2.82, < 3.0` | `opentofu/scaleway` |
| `aws` CLI | on the runner that applies an AWS root | the helm provider's exec (`aws eks get-token`) |

Exact provider builds: each root's `.terraform.lock.hcl`.

### Clouds and Kubernetes

| Cloud | Root | Kubernetes version |
| --- | --- | --- |
| AWS · EKS | `opentofu/clusters/aws` | `aws.kubernetes_version`, required, `1.x`; the example pins `1.34` |
| GCP · GKE | none yet | the release channel, `REGULAR` by default |
| Azure · AKS | none yet | `kubernetes_version`, required, `1.x`; the `stable` auto-upgrade channel within the maintenance window |
| Scaleway · Kapsule | none yet | `kubernetes_version`, required, a minor or a patch; auto-upgrade moves patches only |

Policy (proposed): the minor is pinned per cluster and moves dev, then
staging, then prod, never into a cloud's extended support.

### Flux and what precedes it

| Component | Version | Where | Pinned in |
| --- | --- | --- | --- |
| flux-operator, flux-instance charts | `0.60.0`, exact | every cloud | `operator_version` |
| Flux | `2.x`, the latest 2 series the operator embeds | every cloud | `flux_version`, bounded by `operator_version` |
| Cilium chart | `1.20.2` | aws, azure | `opentofu/bootstrap/cilium.tf` |
| CoreDNS chart | `1.47.1` (CoreDNS 1.14.6) | aws | `opentofu/bootstrap/cilium.tf` |
| `eks-pod-identity-agent` | `v1.4.0-eksbuild.2` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `snapshot-controller` | `v8.5.0-eksbuild.3` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `aws-ebs-csi-driver` | `v1.66.0-eksbuild.1` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `aws-efs-csi-driver` | `v3.4.2-eksbuild.1` | aws, on request | `opentofu/bootstrap/eks_addons.tf` |
| Gateway API standard CRDs | `v1.6.1`, commit `8bb74df` | aws, azure, scaleway | `oci/catalog/gateway-api/resourceset.yaml` |

### Catalog charts

From each `oci/catalog/<module>/resourceset.yaml`. Offered is not proven: CI applies on AWS only.

| Module | Chart | Version | App version | Clouds |
| --- | --- | --- | --- | --- |
| `hello` | `podinfo`, `oci://ghcr.io/stefanprodan/charts` | `6.15.0` | | all |
| `gateway_api` | no chart | | | all |
| `crossplane` | `crossplane`, `https://charts.crossplane.io/stable` | `2.4.2` | v2.4.2; AWS providers v2.8.1 (`provider-family-aws`, `provider-aws-iam`, `provider-aws-eks`, `provider-aws-s3`, `provider-aws-sqs`, `provider-aws-cloudwatchevents`); GCP providers v3.0.0 (`provider-family-gcp`, `provider-gcp-cloudplatform`, `provider-gcp-storage`) | all (providers on aws and gcp) |
| `external_dns` | `external-dns`, `https://kubernetes-sigs.github.io/external-dns/` | `1.22.0` | 0.22.0 | all |
| `argocd` | `argo-cd`, `oci://ghcr.io/argoproj/argo-helm` | `10.9.2` | v3.5.3 | all |
| `argocd_image_updater` | `argocd-image-updater`, `oci://ghcr.io/argoproj/argo-helm` | `1.3.1` | v1.3.0 | all (`repositories` on aws and gcp) |
| `monitoring` | `victoria-metrics-k8s-stack`, `oci://ghcr.io/victoriametrics/helm-charts` | `0.95.2` | VictoriaMetrics v1.153.0; operator v0.75.0; VictoriaLogs v1.53.0; VictoriaTraces v0.10.0; Alertmanager v0.34.0; kube-state-metrics 2.20.0; node-exporter 1.12.1; Grafana 13.2.3 | all |
| `otel_agent` | `opentelemetry-collector`, `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts` | `0.173.1` | 0.160.0 | all |
| `otel_gateway` | `opentelemetry-collector`, same | `0.173.1` | 0.160.0 | all |
| `keda` | `keda`, `https://kedacore.github.io/charts` | `2.21.0` | 2.21.0 | all (`services` on aws and gcp) |
| `metrics_server` | `metrics-server`, `https://kubernetes-sigs.github.io/metrics-server/` | `3.14.0` | 0.9.0 | aws |
| `karpenter` | `karpenter`, `oci://public.ecr.aws/karpenter` | `1.15.0` | 1.15.0 | aws |
| `kyverno` | `kyverno`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `kyverno_policies` | `kyverno-policies`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `external_secrets` | `external-secrets`, `oci://ghcr.io/external-secrets/charts` | `2.11.0` | v2.11.0 | all (its role and store on aws and gcp) |
| `reloader` | `reloader`, `oci://ghcr.io/stakater/charts` | `2.2.18` | v1.4.22 | all |
| `velero` | `velero`, `https://vmware-tanzu.github.io/helm-charts` | `12.2.0` | 1.18.2; `velero-plugin-for-aws` v1.14.4; `velero-plugin-for-gcp` v1.14.4 | aws, gcp |

### Where it was tested

| | |
| --- | --- |
| e2e platform | floci `2.1.0` (a real k3s behind an emulated EKS), on `ubuntu-24.04` runners |
| Flux CLI that pushes the artifact | `2.9.5` |
| What floci does not run | Cilium (every e2e root sets `cilium.enabled = false`), the EKS add-ons, Pod Identity, IAM enforcement, more than one node |
| Integration plans | floci `1.5.34` (AWS), floci-gcp `0.8.0`, floci-az `0.10.0` (red, not blocking); Scaleway plans its minimal example offline |

Chart versions in the templates, `cilium.tf`, `eks_addons.tf` and
`operator_version` move by hand: Renovate does not read them.

What Renovate does with a bump, once its box is ticked on the Dependency
Dashboard (#62):

- **Patch, minor, digest**: the PR merges by itself through GitHub's own
  auto-merge, so only once the `protect-main` ruleset is satisfied.
- **Major**: never by itself. The `needs-design-note` label asks for the
  module's page to say what changes (#61, M3).
- **Anything under `oci/` or `opentofu/`** waits three days after its
  upstream release, and is a `fix(deps)` commit: it ships to clients, so the
  CHANGELOG shows it. The CI's own tooling, under `.github/`, is
  `chore(ci)`.
