---
title: Enable a module
description: Turn a catalog module on, give it its values, check that it converged, and turn it off again.
sidebar:
  order: 1
---

The example turns on KEDA with a role that reads SQS, on AWS: off by default
and with cloud access, so every step applies. A module without cloud access
skips step 2.

## 1. Read the module's page

Its [catalog](../catalog/index.mdx) page lists its attributes, clouds,
requirements and cloud access. For [keda](../catalog/keda.md): `services`
needs `crossplane` on and each service allowed in the foundations.

## 2. Give it what it requires

Allow the service in the cloud block and turn Crossplane on
([Module IAM](../architecture/module-iam.md)):

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

## 3. Set the attribute

```hcl
kube = {
  crossplane = { enabled = true }
  keda       = { enabled = true, services = ["sqs"] }
}
```

Chart values go in `kube.keda.values`, secrets in `kube.keda.values_secret`
([Configure a cluster](configure.md#3-pass-chart-values)). Then plan:

```sh
tofu plan -var-file=clusters/prod.tfvars
```

The plan shows one change, the `socle` release. It refuses a configuration
the module cannot run with and says why: for KEDA, a service outside `sqs`,
`cloudwatch`, `kinesis`, `dynamodb`, or `services` with `crossplane` off or
off aws.

## 4. Check that it converged

```sh
tofu apply -var-file=clusters/prod.tfvars
kubectl -n flux-system get resourceset keda keda-workload   # Ready=True
kubectl -n flux-system get resourceset socle-root           # Ready=True: everything converged
kubectl -n keda get helmrelease                             # the chart, Ready
```

A green apply is not convergence. A module with cloud access has two
`ResourceSet`s: `keda` holds the role, `keda-workload` the chart, which waits
for the role. If one stays not Ready, see [Troubleshooting](troubleshooting.md).

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
- **Crossplane goes last.** Turning it off orphans every module role still
  declared: turn the modules off, wait for their roles to go, then Crossplane.
