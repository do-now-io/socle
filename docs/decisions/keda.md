---
title: keda decisions
description: The decisions behind the keda module, one per section, each with its status.
sidebar:
  order: 10
---

KEDA's operator reads metrics on behalf of the client's workloads, so the
one decision this module makes is what cloud access the operator holds.

## KEDA-01: The operator's role, scoped per AWS service

**accepted** · 2026-10-01 · [`oci/catalog/keda/resourceset.yaml`](../../oci/catalog/keda/resourceset.yaml), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.** Which queues KEDA reads is the client's business, written in
his `ScaledObject`s, which OpenTofu and the template do not read. Two models
were possible: a role per workload, the operator assuming each one, or one
operator role scoped by the client. KEDA's `aws` pod identity resolves a
workload's role in two ways (`pkg/scalers/aws/aws_config_cache.go`,
v2.21.0): `AssumeRoleWithWebIdentity` with the pod's projected OIDC token
(IRSA), and `sts:AssumeRole` from the operator's own credentials. The socle
runs EKS Pod Identity, not IRSA, so there is no token file; and the
operator's role is created by Crossplane inside the boundary, which denies
`sts:*` ([CROSSPLANE-01](crossplane.md#crossplane-01-the-boundary-is-an-allowlist-of-services)).

**Decision.** One role for the operator, bound to `keda/keda-operator`.
`kube.keda.services` names the AWS services it may read, drawn from `sqs`,
`cloudwatch`, `kinesis` and `dynamodb`; each becomes one read-only statement
with the exact calls the scaler makes, taken from the scalers' source.
Nothing for a service not named, no role for an empty list, never `*`.

**Consequences.** `identityOwner: workload` and `roleArn` are dead ends on
the socle, by the boundary's design. A client who needs them makes the
operator's identity outside the socle. Resources are `*` within each
statement: the socle scopes the action, not the queue. The client keeps two
lists in step, `services` and the foundations' `allowed_services`; a drift
fails at IAM, visibly, not at plan. Adding a service is one word in the
catalog and one statement in the template.

**Sources.** KEDA 2.21.0 `pkg/scalers/aws_*_scaler.go` and
`pkg/scalers/aws/aws_config_cache.go`; EKS Pod Identity.
