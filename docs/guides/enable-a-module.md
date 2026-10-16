---
title: Enable a module
description: Turn a catalog module on, give it its values, check that it converged, and turn it off again.
sidebar:
  order: 1
---

The example turns on KEDA with read access to a queue service: SQS on AWS,
Pub/Sub on GCP. It is off by default and has cloud access, so every step
applies. A module without cloud access skips step 2.

## 1. Read the module's page

Its [catalog](../catalog/index.mdx) page lists its attributes, clouds,
requirements and cloud access. For [keda](../catalog/keda.md): `services`
needs `crossplane` on and each service allowed in the foundations: a service
on AWS, a role on GCP.

## 2. Give it what it requires

Allow the access in the cloud block and turn Crossplane on
([Module IAM](../architecture/module-iam.md)).

On AWS, the service:

```hcl
aws = {
  # …
  crossplane = { allowed_services = ["sqs"] }
}

kube = {
  crossplane = { enabled = true }
}
```

The root wires `kube.crossplane.permissions_boundary`; you do not write it.

On GCP, the role the module's binding grants, from
[Crossplane's allowed roles](../clouds/gcp/prerequisites.md#crossplanes-allowed-roles):

```hcl
gcp = {
  # …
  crossplane = { allowed_roles = ["roles/monitoring.viewer"] }
}

kube = {
  crossplane = { enabled = true }
}
```

`allowed_roles` is the ceiling of every role Crossplane may grant; there is
no boundary to wire.

## 3. Set the attribute

```hcl
kube = {
  crossplane = { enabled = true }
  keda       = { enabled = true, services = ["sqs"] } # ["pubsub"] on GCP
}
```

Chart values go in `kube.keda.values`, secrets in `kube.keda.values_secret`
([Configure a cluster](configure.md#3-pass-chart-values)). Then plan:

```sh
tofu plan
```

The plan shows one change, the `socle` release. It refuses a configuration
the module cannot run with and says why: for KEDA, a service outside `sqs`,
`cloudwatch`, `kinesis`, `dynamodb` on AWS or outside `pubsub` on GCP, or
`services` with `crossplane` off or on a cloud with no Crossplane provider.

## 4. Check that it converged

```sh
tofu apply
kubectl -n flux-system get resourceset keda                 # Ready=True
kubectl -n flux-system get resourceset socle-root           # Ready=True: everything converged
kubectl -n keda get helmrelease                             # the chart, Ready
```

A green apply is not convergence. A module with cloud access applies it in
a step before the chart: `keda`'s `cloud` step holds its role and Pod
Identity association on AWS, its IAM binding on GCP, and its `workload`
step, the chart, starts once they are Ready —
`kubectl -n flux-system describe resourceset keda` names the step it
waits on. On GCP, a role missing from `allowed_roles` leaves the binding
not Ready for good. If it stays not Ready, see
[Troubleshooting](troubleshooting.md).

## 5. Turn it off

Set `enabled = false` (or remove the module from `kube` if it is off by
default) and apply. Everything it rendered, its namespace included, goes in
about ten seconds.

- **CRDs that hold your objects stay** (KEDA, Gateway API, External Secrets,
  Velero, Crossplane); Kyverno's go, with every policy
  ([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off)).
- **Wait for an idle release first.** Turned off during a values upgrade, the
  module waits up to five minutes; wait for `Ready` and `Released`, no
  `Reconciling`.
- **Crossplane goes last.** Turning it off orphans every module role (AWS)
  or binding (GCP) still declared: turn the modules off, wait for their
  access to go, then Crossplane.
