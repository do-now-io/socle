---
title: Enable a module
description: Turn a catalog module on, give it its values, check that it converged, and turn it off again.
sidebar:
  order: 1
---

This guide turns on KEDA with a role that reads SQS, on AWS: a module that is
off by default and needs cloud access, so every step applies. A module that
needs neither skips step 2.

## 1. Read the module's page

Each module has a page in the [catalog](../catalog/index.md): what it
installs, its attributes and their defaults, the clouds it is offered on,
what it requires, and what it may do in your cloud account. For KEDA, that
is [keda](../catalog/keda.md): a non-empty `services` list needs the
`crossplane` module on, and each service allowed in the foundations.

## 2. Give it what it requires

KEDA's own role is a Crossplane managed resource, created inside the
boundary the foundations write. Allow the service in the cloud block, and
turn Crossplane on:

```hcl
aws = {
  # …
  crossplane = { allowed_services = ["sqs"] }
}

kube = {
  crossplane = { enabled = true }
}
```

The root wires `kube.crossplane.permissions_boundary` from the foundations;
you do not write it. How module access works is in
[Module IAM](../architecture/module-iam.md).

## 3. Set the attribute

```hcl
kube = {
  crossplane = { enabled = true }
  keda       = { enabled = true, services = ["sqs"] }
}
```

Only what differs from the defaults goes in `kube`. Chart values go in
`kube.keda.values`, secrets in a Secret named by `kube.keda.values_secret`
([Configure a cluster](configure.md#3-pass-chart-values)).

Then plan:

```sh
tofu plan -var-file=clusters/prod.tfvars
```

The plan refuses a configuration the module cannot run with, and says why.
For KEDA: a service outside `sqs`, `cloudwatch`, `kinesis`, `dynamodb`;
`services` with `crossplane` off; `services` on another cloud than aws. Other
modules have their own: `kyverno_policies` without `kyverno`, `velero` on aws
without `crossplane`, `velero` or `gateway_api` on a cloud that does not offer
them, `external_dns` on without `domain_filters`.

The plan shows one change: the `socle` release, whose inputs carry the new
values. Nothing else moves.

## 4. Check that it converged

```sh
tofu apply -var-file=clusters/prod.tfvars
```

The operator re-renders within seconds of the apply. A green apply is not
convergence; read the module's `ResourceSet`, named after its folder:

```sh
kubectl -n flux-system get resourceset keda           # Ready=True
kubectl -n flux-system get resourceset socle-root     # Ready=True: everything converged
kubectl -n keda get helmrelease                       # the chart, Ready
```

A module with cloud access converges in two layers: its `ResourceSet` holds
the role and its Pod Identity association, and a child `ResourceSet`,
`keda-workload`, holds the chart and waits for the role to be Ready.
`kubectl -n flux-system get resourceset keda keda-workload` shows which one
waits. When one stays not Ready, see [Troubleshooting](troubleshooting.md).

## 5. Turn it off

Set `enabled = false`, or remove the module from `kube` if it is off by
default, and apply. The operator garbage-collects everything the module
rendered, its namespace included, in about ten seconds.

- **CRDs that hold your objects stay.** KEDA keeps its CRDs, so your
  `ScaledObject`s survive; so do the Gateway API, External Secrets, Velero and
  Crossplane CRDs. Kyverno's go with it, with every Kyverno policy
  ([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off)).
- **Right after a values change, the off waits up to five minutes.** Each
  values change drives a Helm upgrade with `--wait`; helm-controller honours
  the deletion only once that upgrade returns. Wait for the release to be
  idle (`Ready` and `Released`, no `Reconciling`) before turning a module off.
- **Crossplane goes last.** Turning `crossplane` off does not delete what it
  provisioned: every module role still declared is orphaned in the cloud.
  Turn off the modules that use it, wait for their roles to be gone, then
  turn it off.
