---
title: Sizing
description: What the socle's catalog asks of a GKE Autopilot cluster, module by module, and the rule every container follows so Autopilot does not size it.
sidebar:
  order: 4
---

What the catalog asks of an Autopilot cluster before any client workload: about **2.0 vCPU, 5.0 GiB of memory and 5.3 GiB of ephemeral storage** in requests, every module of `oci/clusters/gcp` on, non-HA. Autopilot reserves about 2.6 vCPU of it once its minimums apply. Before every container stated its disk, the catalog reserved over **30 GiB of ephemeral storage** on the sandbox: 1 GiB a container.

## How Autopilot sizes a pod

Autopilot reserves, and bills, each pod from its declared requests, not from what it uses. From Google's [Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests) (last updated 2026-10-06):

| Rule | General-purpose compute class |
| --- | --- |
| A container that states no request for a resource gets | 500m CPU, 2 GiB memory, 1 GiB ephemeral storage, each resource on its own |
| The same, in a DaemonSet | 50m CPU, 100 MiB memory, 100 MiB ephemeral storage |
| Pod minimum, on a cluster that supports bursting | 50m CPU, 52 MiB memory, 10 MiB ephemeral storage |
| CPU : memory | 1:1 to 1:6.5 (vCPU : GiB); Autopilot raises the smaller one |
| Ephemeral storage limit | set equal to the request by GKE: a pod writing past its request is evicted |
| Without bursting | CPU rounded up to 0.25 vCPU, limits set equal to requests |

So a container that leaves out only its ephemeral-storage request still reserves 1 GiB of node disk.

## What the sandbox measured

On the sandbox cluster (2026-10-07), before this rule:

- Every socle pod reserved 1 GiB of ephemeral storage. On the sandbox's nodes (30 GB boot disks, 8 GiB of allocatable ephemeral storage) that is about seven pods a node, whatever their CPU and memory: the catalog spread over many nodes, and the project's 12-vCPU quota ([prerequisites](prerequisites.md#quotas)) ran out before the socle was up, with no client application.
- Working sets: the GCP Crossplane providers 165 to 222 MiB each, the Crossplane core 176 MiB, its RBAC manager 18 MiB.

## The rule

Every container the catalog runs states a cpu, a memory and an ephemeral-storage request, init containers, sidecars and Helm hook Jobs included, on every cloud and not only on GCP: a request left out is a pod sized by the platform. The figures are in each module's socle values (`oci/catalog/<module>/resourceset.yaml`), never in a cloud's patch; a client's `values` still win over them.

- **Memory and CPU** come from measurements where the repository has them (the *Measured* sections of the [catalog pages](../../catalog/index.mdx)), from the chart's own recommendation otherwise.
- **Ephemeral storage** is chosen, not measured: 64Mi for a long-running container (the kubelet keeps up to five 10 MiB log files per container, plus a few scratch files), 32Mi for an init container or a hook. More where a pod writes to an `emptyDir`: the ArgoCD repo server 1Gi (it clones the client's repositories and copies the argocd binary), the Velero server 512Mi (its plugin binary and Kopia's cache), the Crossplane providers 256Mi (Terraform workspaces under `/tmp`), Grafana 256Mi (its SQLite database and search index), vmagent 256Mi (its on-disk buffer), the Crossplane core 128Mi (a package cache). Because Autopilot turns the request into a limit, a client whose repositories, dashboards or buffers outgrow these raises them in `values`; past it, the pod is evicted.
- **Limits** are never a CPU or ephemeral-storage limit; memory limits only where a module already had one.
- **The VictoriaMetrics operator's pods** (VMSingle, VMAgent, VMAlert, VMAlertmanager, VMAuth, VLSingle, VTSingle) take their requests from the custom resource the [monitoring](../../catalog/monitoring.md) module's chart renders: `resources` for the main container, `configReloaderResources` for the config-reloader sidecar the operator adds beside four of them.

## Per module, gcp

Every module of `oci/clusters/gcp` on, non-HA, `hello` at one replica, no client values. Steady pods only: the Helm hook Jobs run for seconds and are not counted. "Reserved" applies the rules above to each pod: the pod minimum, then the ratio. It is computed from the documented rules, not read from a cluster.

| Module | Pods | Requests (cpu / mem / disk) | Reserved (cpu / mem / disk) |
| --- | --- | --- | --- |
| argocd | controller, server, repo server, ApplicationSet, Redis | 500m / 576Mi / 1280Mi | 500m / 576Mi / 1280Mi |
| argocd-image-updater | controller | 50m / 64Mi / 256Mi | 50m / 64Mi / 256Mi |
| crossplane | core, RBAC manager, 3 providers (family, cloudplatform, storage) | 360m / 1184Mi / 960Mi | 400m / 1204Mi / 960Mi |
| external-dns | 1 | 10m / 64Mi / 64Mi | 50m / 64Mi / 64Mi |
| external-secrets | controller, webhook, cert controller | 30m / 128Mi / 192Mi | 150m / 168Mi / 192Mi |
| keda | operator, metrics server, webhooks | 85m / 224Mi / 192Mi | 150m / 244Mi / 192Mi |
| kyverno | admission ×3, background, reports | 400m / 512Mi / 320Mi | 400m / 512Mi / 320Mi |
| monitoring | operator, Grafana and its two sidecars, kube-state-metrics, VMSingle, VMAgent, VMAlert, VMAlertmanager, VMAuth, VLSingle, VTSingle | 390m / 1892Mi / 1408Mi | 560m / 1892Mi / 1408Mi |
| otel-agent | 1 per node | 50m / 128Mi / 64Mi | 50m / 128Mi / 64Mi |
| otel-gateway | 1 | 100m / 128Mi / 64Mi | 100m / 128Mi / 64Mi |
| reloader | 1 | 10m / 64Mi / 64Mi | 50m / 64Mi / 64Mi |
| velero | server (plugin init container) | 50m / 128Mi / 512Mi | 50m / 128Mi / 512Mi |
| hello | 1 | 10m / 32Mi / 64Mi | 50m / 52Mi / 64Mi |
| **total** | | **2045m / 5124Mi / 5440Mi** | **2560m / 5224Mi / 5440Mi** |

Disk figures are all chosen. kyverno-policies and gateway-api run no pod on GCP; metrics-server is not offered there, and neither is the node exporter nor Velero's node-agent (Autopilot refuses their `hostPath`). The otel-agent row is per node. The VMSingle, VLSingle and VTSingle rows are with a claim (`storage_size` set, the default): their data in an `emptyDir` would count against the disk request.

Not in the table: Flux (installed by the bootstrap, outside the catalog), GKE's own system pods and DaemonSets, what Autopilot adds per node, and Velero's Kopia repository maintenance Jobs, which the server starts at runtime from its `repositoryMaintenanceJob` ConfigMap ([velero](../../catalog/velero.md)) and no render shows. With `ha`, ArgoCD adds three Redis pods with their sentinel, split-brain and HAProxy containers, every one with its requests.

## What fits a fresh project

Measured on the sandbox (project `sandbox-2bace`, cluster `socle-gke`, `europe-west1`, artifact `0.0.0-feat-gcp-parity.d896756`, 2026-10-16):

- **Disk caps the nodes, not CPU.** A fresh project has 250 GB of regional `SSD_TOTAL_GB`, and every Autopilot node boots on a 100 GB `pd-balanced` disk that counts as SSD: two nodes at most, before any claim. The 12-vCPU `CPUS_ALL_REGIONS` quota was not the limit.
- **Pods fill the nodes, not requests.** Autopilot caps a node at 32 pods. GKE's own DaemonSets and system pods take 13 of them on an `e2-standard-2` node and 25 on the `ek-standard-8` system node, which also carries a balloon pod holding 6 vCPU and 25 GB of reserved capacity. About 26 places are left for Flux and the catalog.
- **The full catalog does not fit.** Every module of `oci/clusters/gcp` on, it runs about 41 pods. On a fresh project, either the project's SSD quota is raised, or the client turns on only the modules it needs.
- **Small requests are raised**: a 20m CPU request is reserved as 50m, Autopilot's per-pod minimum (the *Reserved* column above).

So ask for the `SSD_TOTAL_GB` increase ([prerequisites](prerequisites.md#quotas)) before turning the whole catalog on. The sandbox's e2e ran in four waves of modules on one cluster, over a base of Flux, crossplane, gateway-api, the OpenTelemetry modules and hello; turning a wave off removed its modules' IAM bindings (external-secrets, keda, velero) from the project.

## On AWS

The same requests apply. With metrics-server, the node exporter, Velero's node-agent (512Mi of disk per node, no limit: Kopia's cache grows with what it uploads), six Crossplane providers and Karpenter's two replicas, the catalog requests about 2.4 vCPU, 6.8 GiB of memory and 6.8 GiB of ephemeral storage. On EKS a request only schedules; nothing turns it into a limit, but under DiskPressure the kubelet evicts first the pods furthest over their ephemeral-storage request.

## The guard

`.github/scripts/check-catalog-requests.sh`, a step of the `kubeconform` job in `pr-static.yaml`. For aws, gcp, and aws again with every `ha` input on, it renders every ResourceSet the cloud's overlay deploys from that cloud's committed sample (`oci/.ci/inputs-sample*.yaml`), and templates every HelmRelease there with a pinned `helm`, at its pinned chart version and with the socle's values alone: the client's `values` ConfigMap is left out, so a sample value cannot hide a gap in the socle's defaults. It also reads the plain manifests a module's Flux Kustomizations apply, the Crossplane `DeploymentRuntimeConfig`s and the VictoriaMetrics operator's custom resources, and fails on any container without a cpu, memory or ephemeral-storage request. A chart it cannot pull fails it too, after three attempts; the pulled charts are cached between runs. Helm `test` pods are skipped: helm-controller runs no tests. Pods an operator creates at runtime from no template of the render, Velero's maintenance Jobs, are out of its reach.
