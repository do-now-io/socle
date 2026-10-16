---
title: Limits
description: What no apply can finish on GCP, the provider limits the socle runs into, and what it does not offer there yet.
sidebar:
  order: 3
---

## What no apply can finish

- **Linking the billing account to the cost export dataset**: a Cloud Console step, no API; without it the cost data never arrives.
- **VPC Service Controls** in front of the DNS endpoint: set at organisation level; without it, IAM is the only gate.

## Provider limits

- **Autopilot forbids** privileged Pods (outside Google's allowlists), host namespaces, writable `hostPath` and SSH to nodes.
- **Container-Optimized OS and Dataplane V2 only.**
- **Every Pod is billed at least 250 mCPU and 512 MiB.**
- **A request left out is sized by Autopilot**: a container that states no cpu, memory or ephemeral-storage request gets 500m CPU, 2 GiB of memory and 1 GiB of ephemeral storage (50m, 100 MiB and 100 MiB in a DaemonSet), each resource on its own, and GKE sets the ephemeral-storage limit equal to the request. So every container of the catalog, init containers, sidecars and Helm hooks included, states all three, on every cloud: 64Mi of disk for a long-running container, 32Mi for an init container or a hook, more where it writes to an `emptyDir`. The figures, module by module, and the CI guard that keeps them: [sizing](sizing.md).
- **A fresh project holds two nodes, and the full catalog does not fit them**: its 250 GB `SSD_TOTAL_GB` quota is two Autopilot nodes (a 100 GB `pd-balanced` boot disk each), Autopilot caps a node at 32 pods and GKE's own pods take 13 to 25 of them, which leaves about 26 places for Flux and a catalog of about 41 pods, every module on (sandbox, 2026-10-16). Raise the SSD quota first, or turn on only the modules you need: [sizing](sizing.md#what-fits-a-fresh-project).
- **Upgrades are automatic**: you choose the window, not whether.
- **The cluster mode is fixed**: Standard means a new cluster.
- **No file-level Velero backup**: its node-agent needs privileged mode and `hostPath`; only CSI snapshots remain.
- **`EXTENDED` channel forbidden**; `RAPID` is outside the GKE SLA.
- **Maintenance**: at least 48 hours available per 92 days, in blocks of 4 hours or more; GKE enforces it at apply.
- **Exclusions**: a `NO_UPGRADES` one lasts at most 90 days, at most 3 of them, 20 in all; Google overrides them at end of support.
- **The Pod range is fixed at creation**; the primary range can grow.
- **No inter-node transparent encryption**; FQDN policies are a GKE alpha CRD.
- **Only GKE's GatewayClasses**: the socle's `cilium` class does not exist here.
- **One proxy-only subnetwork per region and VPC**: a second cluster sets `create_proxy_only_subnet = false`.
- **One socle cluster per project**: a Workload Identity principal names the project, the namespace and the ServiceAccount, never the cluster, so two clusters in one project share every module's principal, and what Crossplane grants one serves the other.
- **Alert policies billed from 1 September 2027**; the socle defines none.
- **Cost allocation does not backfill**, hence on from creation.

## What the socle does not offer here yet

- **File-level Velero backups**: CSI snapshots only (see above); Backup for GKE with `backup_agent_enabled = true` covers the rest.
- **Crossplane providers beyond Cloud Platform and Storage**: the modules' project and bucket bindings and their buckets; no Cloud DNS provider, external-dns writes its records itself.
- **`kube.keda.services`** beyond `pubsub`: the operator's principal holds `roles/monitoring.viewer` only. Another source takes a `TriggerAuthentication` on a Secret of yours; leave the chart's `podIdentity.gcp.enabled` off, it would make the operator impersonate a Google service account no binding names ([keda](../../catalog/keda.md#good-to-know)).
- **Hubble**: no variable.
- **Service metrics from outside the cluster**: the `stackdriver_exporter` is not built, only the reader binding.
