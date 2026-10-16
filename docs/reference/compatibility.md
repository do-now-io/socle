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
| AWS · EKS | `opentofu/clusters/aws` | `aws.kubernetes_version`, required, `1.x`; CI applies `1.37`, the latest in EKS standard support; the example pins `1.36`, the N-1 ceiling of SOCLE-05 |
| GCP · GKE | `opentofu/clusters/gcp` | the release channel, `REGULAR` by default (1.34 to 1.36 offered, 1.36 the default, in October 2026) |
| Azure · AKS | none yet | `kubernetes_version`, required, `1.x`; the example pins `1.36`, the latest AKS GA (1.37 is in preview); the `stable` auto-upgrade channel within the maintenance window |
| Scaleway · Kapsule | none yet | `kubernetes_version`, required, a minor or a patch; the example pins `1.37`, the latest Kapsule offers; auto-upgrade moves patches only |

Policy (proposed): the minor is pinned per cluster and moves dev, then
staging, then prod, never into a cloud's extended support.

### Flux and what precedes it

| Component | Version | Where | Pinned in |
| --- | --- | --- | --- |
| flux-operator, flux-instance charts | `0.61.0`, exact | every cloud | `operator_version` |
| Flux | `2.x`, the latest 2 series (2.9.6 with operator 0.61.0) | every cloud | `flux_version` |
| Cilium chart | `1.20.3` | aws, azure | `opentofu/bootstrap/cilium.tf` |
| CoreDNS chart | `1.48.2` (CoreDNS 1.14.7) | aws | `opentofu/bootstrap/cilium.tf` |
| `eks-pod-identity-agent` | `v1.4.0-eksbuild.4` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `snapshot-controller` | `v8.6.0-eksbuild.10` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `aws-ebs-csi-driver` | `v1.67.0-eksbuild.1` | aws | `opentofu/bootstrap/eks_addons.tf` |
| `aws-efs-csi-driver` | `v3.5.1-eksbuild.1` | aws, on request | `opentofu/bootstrap/eks_addons.tf` |
| Gateway API standard CRDs | `v1.6.3`, commit `c083613` | aws, azure, scaleway | `oci/catalog/gateway-api/resourceset.yaml` |

### Catalog charts

From each `oci/catalog/<module>/resourceset.yaml`. Offered is not proven: CI applies on AWS only.

| Module | Chart | Version | App version | Clouds |
| --- | --- | --- | --- | --- |
| `hello` | `podinfo`, `oci://ghcr.io/stefanprodan/charts` | `6.15.0` | | all |
| `gateway_api` | no chart | | | all |
| `crossplane` | `crossplane`, `https://charts.crossplane.io/stable` | `2.4.2` | v2.4.2; AWS providers v2.9.0; GCP providers v3.1.0 (`provider-family-gcp`, `provider-gcp-cloudplatform`, `provider-gcp-storage`) | all (providers on aws and gcp) |
| `external_dns` | `external-dns`, `https://kubernetes-sigs.github.io/external-dns/` | `1.23.0` | 0.23.0 | all |
| `argocd` | `argo-cd`, `oci://ghcr.io/argoproj/argo-helm` | `10.10.5` | v3.5.5 | all |
| `argocd_image_updater` | `argocd-image-updater`, `oci://ghcr.io/argoproj/argo-helm` | `1.3.2` | v1.3.1 | all (`repositories` on aws and gcp) |
| `monitoring` | `victoria-metrics-k8s-stack`, `oci://ghcr.io/victoriametrics/helm-charts` | `0.96.0` | VictoriaMetrics v1.154.0; operator v0.75.0; VictoriaLogs v1.53.0; VictoriaTraces v0.10.0; Alertmanager v0.34.0; kube-state-metrics 2.20.0; node-exporter 1.12.1; Grafana 13.2.3 | all |
| `otel_agent` | `opentelemetry-collector`, `oci://ghcr.io/open-telemetry/opentelemetry-helm-charts` | `0.176.0` | 0.162.0 | all |
| `otel_gateway` | `opentelemetry-collector`, same | `0.176.0` | 0.162.0 | all |
| `keda` | `keda`, `https://kedacore.github.io/charts` | `2.21.0` | 2.21.0 | all (`services` on aws and gcp) |
| `metrics_server` | `metrics-server`, `https://kubernetes-sigs.github.io/metrics-server/` | `3.14.0` | 0.9.0 | aws |
| `kyverno` | `kyverno`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `kyverno_policies` | `kyverno-policies`, `oci://ghcr.io/kyverno/charts` | `3.9.1` | v1.19.1 | all |
| `external_secrets` | `external-secrets`, `oci://ghcr.io/external-secrets/charts` | `2.13.0` | v2.13.0 | all (its role and store on aws and gcp) |
| `reloader` | `reloader`, `oci://ghcr.io/stakater/charts` | `2.2.18` | v1.4.22 | all |
| `velero` | `velero`, `https://vmware-tanzu.github.io/helm-charts` | `12.2.1` | 1.18.2; `velero-plugin-for-aws` v1.14.4; `velero-plugin-for-gcp` v1.14.4 | aws, gcp |

### Where it was tested

| | |
| --- | --- |
| e2e platform | floci `2.3.0` (a real k3s behind an emulated EKS), on `ubuntu-24.04` runners |
| Flux CLI that pushes the artifact | `2.9.6` |
| What floci does not run | Cilium (every e2e root sets `cilium.enabled = false`), the EKS add-ons, Pod Identity, IAM enforcement, more than one node |
| Integration plans | floci `2.3.0` (AWS), floci-gcp `0.11.0`, floci-az `0.15.0` (red, not blocking); Scaleway plans its minimal example offline |

Renovate reads every pin above but three: the Kubernetes minors (SOCLE-05),
the EKS add-ons (no datasource lists them; `aws eks describe-addon-versions`
does) and the SHA256 beside each CI tool's version, which move by hand. Its
custom managers (`renovate.json`) cover the charts' `tag:` and `version:` in
the ResourceSets, the images and Crossplane packages in the catalog and the
clouds' patches, the Gateway API commit, the rule and dashboard sources,
`cilium.tf`, `operator_version`, and the CI tools. A chart's `# appVersion`
comment is not Renovate's to write: pr-static fails while it is not the
pinned chart's, and names the value (`.github/scripts/check-app-versions.py`).
