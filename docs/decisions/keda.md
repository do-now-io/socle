---
title: keda decisions
description: The decisions behind the keda module, one per section, each with its status.
sidebar:
  order: 10
---

KEDA's operator reads metrics on behalf of the client's workloads; the
decisions here are what cloud access the operator holds, per cloud.

## KEDA-01: The operator's role, scoped per AWS service

**accepted** · 2026-10-01 · [`oci/catalog/keda/resourceset.yaml`](../../oci/catalog/keda/resourceset.yaml), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** One role for `keda/keda-operator`. `kube.keda.services` names
the services it may read (`sqs`, `cloudwatch`, `kinesis`, `dynamodb`), each
one read-only statement with the exact calls the scaler makes; nothing for an
unnamed service, no role for an empty list, never `*`.

**Context.** A role per workload needs either IRSA's token file (the socle
runs EKS Pod Identity) or `sts:AssumeRole` from the operator, which the
boundary denies ([CROSSPLANE-01](crossplane.md#crossplane-01-the-boundary-is-an-allowlist-of-services)).

**Consequences.** `identityOwner: workload` and `roleArn` are dead ends on the
socle. Resources are `*` within each statement. The client keeps `services`
and the foundations' `allowed_services` in step; a drift fails at IAM.

**Sources.** KEDA 2.21.0 `pkg/scalers/aws_*_scaler.go` and `pkg/scalers/aws/aws_config_cache.go`; EKS Pod Identity.

## KEDA-02: On GCP, one Cloud Monitoring read on the operator's principal

**accepted** · 2026-10-07 · [`oci/clusters/gcp/keda/patch.yaml`](../../oci/clusters/gcp/keda/patch.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** On gcp `kube.keda.services` may name `pubsub` only. It becomes
one project-level `ProjectIAMMember` granting `roles/monitoring.viewer` to the
Workload Identity principal of `keda/keda-operator`, by project number, with
no Google service account. The chart's `podIdentity.gcp.enabled` stays off.

**Context.** KEDA's `gcp-pubsub` scaler never calls Pub/Sub: it queries Cloud
Monitoring for `pubsub.googleapis.com/subscription/num_undelivered_messages`,
so it needs `monitoring.timeSeries.list`, and `roles/monitoring.viewer` is the
narrowest predefined role holding it; `roles/pubsub.viewer`, which #68 first
listed, would grant nothing the scaler uses. With `podIdentity.provider: gcp`
KEDA builds its clients from Application Default Credentials, which the GKE
metadata server answers for the pod's own ServiceAccount. The subscriptions
are named in the client's `ScaledObject`s, which the socle does not read, and
Crossplane may grant only the roles the client lists in
`gcp.crossplane.allowed_roles`, so no narrower custom role.

**Consequences.** The operator reads every metric of the project, never a
message. The same binding serves `gcp-stackdriver`, `gcp-cloudtasks` and the
`prometheus` scaler on Cloud Monitoring's PromQL endpoint, so `cloudtasks` and
`monitoring` are not separate names. The client keeps
`roles/monitoring.viewer` in `allowed_roles`; without it the binding stays
`Synced=False` and the module waits. The workload's own
`roles/pubsub.subscriber` is the client's, never the socle's. Two clusters in
one project would share the principal and the binding; the socle runs one
cluster per project. The ordering on `keda-access` and the
`socle.do-now.io/cloud-access` annotation are kept though GKE hands out
tokens at call time: the same chain as on AWS.

**Sources.** KEDA 2.21.0 `pkg/scalers/gcp_pubsub_scaler.go`, `pkg/scalers/gcp/gcp_stackdriver_client.go`, `pkg/scalers/gcp/gcp_common.go` · [Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity) · [Cloud Monitoring roles](https://cloud.google.com/monitoring/access-control) · [KEDA GCP deprecations, 2025-09-15](https://keda.sh/blog/2025-09-15-gcp-deprecations).
