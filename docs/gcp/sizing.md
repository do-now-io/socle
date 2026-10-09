# Google Cloud — sizing the catalog on Autopilot

What the socle's catalog asks of an Autopilot cluster, module by module,
before any client workload: about **2.3 vCPU, 4.3 GiB of memory and 4.4 GiB
of ephemeral storage** in requests, every module on, non-HA. Until
2026-10-08 the same catalog reserved 2.7 vCPU, 6.0 GiB and **32 GiB of
ephemeral storage**, because most of its containers stated no disk.

## How Autopilot sizes a pod

Autopilot reserves, and bills, each pod from its declared requests — not from
what it uses. From Google's
[Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests)
(last updated 2026-10-06):

| Rule | General-purpose compute class |
| --- | --- |
| A container that states no request for a resource gets | 500m CPU, 2 GiB memory, 1 GiB ephemeral storage — each resource on its own |
| The same, in a DaemonSet | 50m CPU, 100 MiB memory, 100 MiB ephemeral storage |
| Pod minimum, on a cluster that supports bursting | 50m CPU, 52 MiB memory, 10 MiB ephemeral storage |
| CPU : memory | 1:1 to 1:6.5 (vCPU : GiB); Autopilot raises the smaller one |
| Ephemeral storage limit | set equal to the request, by GKE: a pod writing past its request is evicted |
| Without bursting | CPU rounded up to 0.25 vCPU, limits set equal to requests |

So a container that leaves out only its ephemeral-storage request still
reserves 1 GiB of node disk.

## What the sandbox measured

On the sandbox cluster (2026-10-07), before this sizing:

- Every socle pod reserved 1 GiB of ephemeral storage. On the sandbox's nodes
  (a sandbox-only compute class, 30 GB boot disks), with 8 GiB of
  allocatable ephemeral storage, that is about seven pods a node, whatever
  their CPU and memory: the catalog spread over many nodes, and the project's
  12-vCPU quota ([prerequisites](prerequisites.md#quotas)) ran out before the
  socle was up, with no client application.
- Working sets: the GCP Crossplane providers 165–222 MiB each, the Crossplane
  core 176 MiB, its RBAC manager 18 MiB.

## The rule

Every container the catalog runs states a cpu, a memory and an
ephemeral-storage request, init containers, sidecars and Helm hook Jobs
included — on every cloud, not only on GCP: a request left out is a pod sized
by the platform. The figures are in each module's socle values
(`oci/catalog/<module>/resourceset.yaml`); a client's `values` still win over
them.

- **Memory and CPU** come from measurements where the repository has them
  (the *Measured* sections of [docs/catalog](../catalog/)), from the chart's
  own recommendation otherwise. They are not changed by this page, except
  the Crossplane core (128Mi → 192Mi, measured at 176Mi on GKE), Grafana
  (256Mi → 320Mi, measured at about 300Mi: the pod asks 60m / 384Mi with its
  sidecar, 6.25 GiB a vCPU, inside the 1:6.5 ratio), VictoriaMetrics
  (128Mi → 192Mi, measured at about 150Mi under both collectors), ArgoCD's
  Redis (32Mi → 64Mi, to stay inside the 1:1 ratio) and podinfo (1m/16Mi →
  10m/32Mi, the same).
- **Ephemeral storage** is chosen, not measured: 64Mi for a long-running
  container — the kubelet keeps up to five 10 MiB log files per container,
  plus a few scratch files — 32Mi for an init container or a hook. More where
  a pod writes to an `emptyDir`: the ArgoCD repo server 1Gi (it clones the
  client's repositories and copies the argocd binary), the Velero server 512Mi
  (its plugin binary and Kopia's cache), Grafana 256Mi (its SQLite database
  and search index), the Crossplane core 128Mi (a package cache the chart
  caps at 20Mi), the Crossplane providers 256Mi (Terraform workspaces under
  `/tmp`), VictoriaMetrics, VictoriaLogs and VictoriaTraces **2Gi when
  `storage_size = ""`** — their data then lives in an `emptyDir`, counted
  against the request — and 64Mi when a claim holds it. Because Autopilot
  turns the request into a limit, a client whose repositories, dashboards
  or emptyDir-held data outgrow these raises them in `values`; past it, the
  pod is evicted. 2Gi is chosen, not derived from the retention: data meant
  to last belongs on a claim.
- **Limits** are unchanged: memory limits only where a module already had one
  (the collectors, external-dns, external-secrets, reloader, Velero, KEDA's
  and Kyverno's chart limits), never a CPU or ephemeral-storage limit.

## Per module, gcp

Every module of `oci/clusters/gcp` on, non-HA, `hello` at one replica, no
client values. Steady pods only: the Helm hook Jobs run for seconds and are
not counted. "Reserved" applies the rules above to each pod — the defaults
for a missing request, the pod minimum, the ratio.

| Module | Pods | Reserved before (cpu / mem / disk) | Requests now (cpu / mem / disk) | Reserved now | Memory figure |
| --- | --- | --- | --- | --- | --- |
| crossplane | core, RBAC manager, 4 providers | 500m / 1460Mi / 6144Mi | 460m / 1504Mi / 1216Mi | 500m / 1524Mi / 1216Mi | measured, GKE sandbox |
| argocd | controller, server, repo server, ApplicationSet, Redis | 500m / 564Mi / 5120Mi | 500m / 576Mi / 1280Mi | 500m / 576Mi / 1280Mi | chosen |
| kyverno | admission ×3, background, reports | 400m / 512Mi / 5120Mi | 400m / 512Mi / 320Mi | 400m / 512Mi / 320Mi | measured, floci (48–59Mi a replica) |
| external-secrets | controller, webhook, cert controller | 150m / 168Mi / 3072Mi | 30m / 128Mi / 192Mi | 150m / 168Mi / 192Mi | chosen |
| keda | operator, metrics server, webhooks | 150m / 244Mi / 3072Mi | 85m / 224Mi / 192Mi | 150m / 244Mi / 192Mi | measured, floci (13–35Mi) |
| grafana | Grafana + dashboard sidecar | 60m / 320Mi / 2048Mi | 60m / 384Mi / 320Mi | 60m / 384Mi / 320Mi | measured, floci (~300Mi + 72Mi) |
| velero | server (plugin init container) | 500m / 2048Mi / 1024Mi | 50m / 128Mi / 512Mi | 50m / 128Mi / 512Mi | chosen; the init container had no request |
| otel-gateway | 1 | 100m / 128Mi / 1024Mi | 100m / 128Mi / 64Mi | 100m / 128Mi / 64Mi | measured, floci (45–50Mi) |
| otel-agent | 1 per node | 50m / 128Mi / 100Mi | 50m / 128Mi / 64Mi | 50m / 128Mi / 64Mi | measured, floci (33–52Mi) |
| victoria-metrics | 1 | 50m / 128Mi / 1024Mi | 50m / 192Mi / 64Mi | 50m / 192Mi / 64Mi | measured, floci (~150Mi under both collectors) |
| victoria-logs | 1 | 50m / 128Mi / 1024Mi | 50m / 128Mi / 64Mi | 50m / 128Mi / 64Mi | measured, floci (32–47Mi) |
| victoria-traces | 1 | 50m / 128Mi / 1024Mi | 50m / 128Mi / 64Mi | 50m / 128Mi / 64Mi | measured, floci (10Mi) |
| external-dns | 1 | 50m / 64Mi / 1024Mi | 10m / 64Mi / 64Mi | 50m / 64Mi / 64Mi | chosen |
| reloader | 1 | 50m / 64Mi / 1024Mi | 10m / 64Mi / 64Mi | 50m / 64Mi / 64Mi | chosen |
| hello | 1 | 50m / 52Mi / 1024Mi | 10m / 32Mi / 64Mi | 50m / 52Mi / 64Mi | chosen |
| **total** | | **2710m / 6136Mi / 32868Mi** | **1915m / 4320Mi / 4544Mi** | **2260m / 4420Mi / 4544Mi** | |

"Reserved" is computed from the documented rules, not read from a cluster.
Disk figures are all chosen. kyverno-policies and gateway-api run no pod on
GCP; metrics-server is not offered on GCP. The otel-agent row is per node.
The three Victoria rows are with a claim (`storage_size` set, the default):
with `storage_size = ""` each asks 2Gi of ephemeral storage instead of
64Mi, 5952Mi more in all.

Not in the table: Flux (installed by the bootstrap, outside the catalog),
GKE's own system pods and DaemonSets, what Autopilot adds per node, and
Velero's Kopia repository maintenance Jobs (file-system backups, so AWS
today), which the server starts at runtime: they ask the server's
50m / 128Mi / 512Mi through the chart's `repositoryMaintenanceJob`
ConfigMap ([velero](../catalog/velero.md)), and no render shows them.
With `ha`, ArgoCD adds three Redis pods with their sentinel, split-brain and
HAProxy containers — every one with its requests.
Nor is [alerting](../catalog/alerting.md), which came after the measure: its
vmalert pod (with its rules sidecar) and Alertmanager request 40m / 208Mi /
192Mi together, measured on floci, and reserve 100m / 212Mi / 192Mi under
the pod minimum. Its disk figure is chosen.

## On AWS

The same requests apply: the AWS renders changed only in `resources`. With
metrics-server and Velero's node-agent (512Mi of disk requested per node, no
limit: Kopia's cache grows with what it uploads), the catalog requests
1865m, 4648Mi and 5120Mi of ephemeral storage. On EKS a request only
schedules; nothing turns it into a limit — but under DiskPressure the
kubelet evicts first the pods furthest over their ephemeral-storage
request. An EKS without a default StorageClass sets `storage_size = ""`
(`opentofu/clusters/aws/prod.tfvars.example`): the Victoria pods then ask
2Gi each, so the data they keep in their `emptyDir` stays under what they
asked for.

## The guard

`.github/scripts/check-catalog-requests.sh`, a step of the `kubeconform` job
in `pr-static.yaml`: for aws, gcp, and aws again with every `ha` input on
(argocd's Redis HA, metrics-server's replicas — kyverno has no `ha` switch,
its three admission replicas are always rendered), it templates every
HelmRelease of the render with `helm template` (a pinned helm), at its
pinned chart version and with the socle's values alone — the client's
`values` ConfigMap left out, so a sample value cannot hide a gap in the
socle's defaults — reads the Crossplane `DeploymentRuntimeConfig`s and the
plain manifests a module applies, and fails on any container without a cpu,
memory or ephemeral-storage request. A chart it cannot pull fails it too,
with helm's message, after three attempts; the pulled charts are cached
between runs, keyed on the modules' ResourceSets. It runs on the committed
samples (`oci/.ci/inputs-sample*.yaml`), so a module or a chart bump that
brings a container without requests fails before merge. Helm `test` pods
are skipped: helm-controller runs no tests. Pods an operator creates at
runtime from no template of the render — Velero's maintenance Jobs — are
out of its reach.
