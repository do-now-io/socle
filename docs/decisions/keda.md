---
title: keda decisions
description: The decisions behind the keda module, one per section, each with its status.
sidebar:
  order: 10
---

KEDA's operator reads metrics on behalf of the client's workloads; the one
decision here is what cloud access the operator holds.

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
