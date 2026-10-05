---
title: Compatibility
description: The OpenTofu, provider, Flux, Kubernetes and chart versions each socle release pins or requires, and where it was tested.
sidebar:
  order: 3
---

What one socle version pins and requires; they move with `socle_version`
([Upgrade the socle](../guides/upgrade.md)). No version is released yet.

## main (unreleased)

### Tooling and providers

| Component | Version | Source |
| --- | --- | --- |
| OpenTofu | `>= 1.10` | every `versions.tf` |
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

Policy (proposed): [SOCLE-05](../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).

### Flux and what precedes it

| Component | Version | Where | Pinned in |
| --- | --- | --- | --- |
| flux-operator, flux-instance charts | `0.60.0`, exact | every cloud | `operator_version` |
| Flux | `2.x`, the latest 2 series | every cloud | `flux_version` |
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
| `gateway_api` | no chart | | | aws, azure, scaleway |
| `crossplane` | `crossplane`, `https://charts.crossplane.io/stable` | `2.4.2` | v2.4.2; AWS providers v2.8.1 | all (providers on aws only) |
| `external_dns` | `external-dns`, `https://kubernetes-sigs.github.io/external-dns/` | `1.22.0` | 0.22.0 | all |
| `argocd` | `argo-cd`, `oci://ghcr.io/argoproj/argo-helm` | `10.9.2` | v3.5.3 | all |
| `victoria_metrics` | `victoria-metrics-single`, `oci://ghcr.io/victoriametrics/helm-charts` | `0.48.0` | v1.153.0 | all |
| `otel_agent` | `opentelemetry-collector`, `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts` | `0.173.1` | 0.160.0 | all |
| `otel_gateway` | `opentelemetry-collector`, same | `0.173.1` | 0.160.0 | all |
| `grafana` | `grafana`, `oci://ghcr.io/grafana-community/helm-charts` | `13.2.6` | 13.2.2 | all |
| `victoria_logs` | `victoria-logs-single`, `oci://ghcr.io/victoriametrics/helm-charts` | `0.13.9` | v1.52.0 | all |
| `victoria_traces` | `victoria-traces-single`, `oci://ghcr.io/victoriametrics/helm-charts` | `0.1.11` | v0.11.0 | all |
| `keda` | `keda`, `https://kedacore.github.io/charts` | `2.21.0` | 2.21.0 | all (`services` on aws only) |
| `kyverno` | `kyverno`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `kyverno_policies` | `kyverno-policies`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `external_secrets` | `external-secrets`, `oci://ghcr.io/external-secrets/charts` | `2.11.0` | v2.11.0 | all (its role and store on aws only) |
| `reloader` | `reloader`, `oci://ghcr.io/stakater/charts` | `2.2.18` | v1.4.22 | all |
| `velero` | `velero`, `https://vmware-tanzu.github.io/helm-charts` | `12.2.0` | 1.18.2; `velero-plugin-for-aws` v1.14.4 | aws |

### Where it was tested

| | |
| --- | --- |
| e2e platform | floci `2.1.0` (a real k3s behind an emulated EKS), on `ubuntu-24.04` runners |
| Flux CLI that pushes the artifact | `2.9.5` |
| What floci does not run | Cilium (every e2e root sets `cilium.enabled = false`), the EKS add-ons, Pod Identity, IAM enforcement, more than one node |
| Integration plans | floci `1.5.34` (AWS), floci-gcp `0.8.0`, floci-az `0.10.0` (red, not blocking); Scaleway plans its minimal example offline |

Chart versions in the templates, `cilium.tf`, `eks_addons.tf` and
`operator_version` move by hand: Renovate does not read them.
