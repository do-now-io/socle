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
- **Two clusters in one project share Workload Identity principals**: one project per environment.
- **Alert policies billed from 1 September 2027**; the socle defines none.
- **Cost allocation does not backfill**, hence on from creation.

## What the socle does not offer here yet

- **Velero**: aws only; Backup for GKE with `backup_agent_enabled = true`.
- **Crossplane providers**: the core only.
- **`kube.keda.services`**: bind your own identity through `podIdentity.gcp` in values, or use a TriggerAuthentication Secret.
- **The shared Gateways**: `gateway_api` is not offered on gcp; write your own Gateway on `gke-l7-global-external-managed`.
- **Hubble**: no variable.
- **Service metrics from outside the cluster**: the `stackdriver_exporter` is not built, only the reader binding.
- **A ready root**: no `opentofu/clusters/gcp`; the [quickstart](../../getting-started/gcp.md) shows the one to write.
