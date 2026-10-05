---
title: Limits
description: What no apply can finish on GCP, and the provider limits the socle runs into.
sidebar:
  order: 3
---

## What no apply can finish

- **Linking the billing account to the cost export dataset.** With
  `billing_export_dataset_id` set, the module creates the BigQuery dataset;
  pointing the billing account's detailed usage cost export at it is a Cloud
  Console action. Google exposes no API for it, so there is no Terraform
  resource and no `gcloud` command. Nothing breaks without it: the cost data
  never arrives
  ([GCP-12](../../decisions/gcp.md#gcp-12-cost-attribution-through-the-detailed-billing-export)).
- **VPC Service Controls**, the network boundary in front of the control
  plane's DNS endpoint. It is set at organisation level, outside any project
  module; without it, IAM is the only gate.

## Provider limits

Autopilot:

- No privileged Pods outside Google's partner allowlists, no host
  namespaces, no writable `hostPath`, no SSH to nodes.
- Container-Optimized OS only; Dataplane V2 only.
- Every Pod is billed at least 250 mCPU and 512 MiB.
- Upgrades are automatic: you choose the window, not whether.
- The cluster mode is fixed at creation; moving to Standard is a new
  cluster and a migration.
- Velero's node-agent needs privileged mode and a writable `hostPath`, so
  file-level volume backup is impossible; only CSI snapshots remain.

Upgrades:

- The `EXTENDED` channel is forbidden on Autopilot; `RAPID` is outside the
  GKE SLA.
- GKE requires at least 48 hours of maintenance availability in any 92-day
  window, counting only contiguous blocks of 4 hours or more. The module
  enforces the 4 hours; GKE enforces the rest at apply.
- A `NO_UPGRADES` exclusion lasts at most 90 days, and at most 3 may exist;
  a cluster holds at most 20 exclusions. Google overrides exclusions at end
  of support.

Network:

- The Pod range cannot be changed after the cluster is created. The primary
  range can be expanded in place.
- No inter-node transparent encryption on Autopilot.
- FQDN network policies exist only as a GKE-specific alpha CRD.
- Only GKE's own GatewayClasses are served; the socle's `cilium` class does
  not exist here.
- One proxy-only subnetwork per region and VPC, shared by every regional
  Envoy-based load balancer in it: a second cluster sets
  `create_proxy_only_subnet = false`.

Identity:

- Workload Identity principals are built from project, namespace and service
  account, not cluster: two clusters in one project collide. Use one project
  per environment
  ([GCP-06](../../decisions/gcp.md#gcp-06-workload-identity-federation-a-google-service-account-per-kubernetes-service-account)).

Billing:

- Cloud Monitoring alert policies are free until 1 September 2027, then
  billed. The socle defines none
  ([GCP-11](../../decisions/gcp.md#gcp-11-service-metrics-read-every-300-s-cloud-monitoring-alert-policies-refused)).
- GKE cost allocation does not backfill, which is why it is on from
  creation.

## What the socle does not offer here yet

- **Velero.** The catalog offers it on aws only; a GCP cluster has no
  backup by default
  ([GCP-05](../../decisions/gcp.md#gcp-05-velero-by-default-backup-for-gke-as-a-priced-option)).
  The Backup for GKE agent is available with `backup_agent_enabled = true`.
- **Crossplane providers.** The crossplane module installs the core on GCP
  and no provider, so nothing provisions Google Cloud resources from the
  cluster
  ([GCP-13](../../decisions/gcp.md#gcp-13-crossplane-not-config-connector)).
- **`kube.keda.services`.** KEDA's own cloud role is aws-only; on GCP, bind
  an identity you made to `keda-operator` through values
  (`podIdentity.gcp`), or reference a Secret from a TriggerAuthentication.
- **The shared Gateways.** The `gateway_api` module is not offered on gcp,
  so the shared `public` and `private` Gateways do not exist; write your own
  Gateway on `gke-l7-global-external-managed`.
- **Hubble.** Dataplane V2 observability has no variable.
- **Service metrics from outside the cluster.** The `stackdriver_exporter`
  of GCP-11 is not built; only the reader binding is.
- **A ready root.** There is no `opentofu/clusters/gcp`; the
  [quickstart](../../getting-started/gcp.md) shows the root to write.
