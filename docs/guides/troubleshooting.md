---
title: Troubleshooting
description: What to read when a plan is refused, an apply is green but the cluster does not converge, or a module will not go away.
sidebar:
  order: 5
---

## Read the state first

```sh
kubectl -n flux-system get resourcesetinputprovider socle -o yaml   # what OpenTofu deposited: your configuration, normalised
kubectl -n flux-system get ocirepository socle                      # the pulled tag and digest, and SourceVerified
kubectl -n flux-system get resourceset                              # socle-root and one per module, with Ready
kubectl -n flux-system describe resourceset <module>                # why one is not Ready
kubectl -n <namespace> get helmrelease                              # the module's chart
```

**A green `tofu apply` is not convergence.** Helm's `wait` does not wait for
a custom resource to be Ready: the apply proves the objects were deposited.
The signal is `socle-root` Ready, which it is only when every module is.

## The plan refuses kube

`kube` is validated against the catalog at plan, and the message lists what
is allowed:

```text
kube = { external_dsn = { enabled = true } }
→ kube: unknown module(s) external_dsn. Catalog: argocd, crossplane, external_dns, …

kube = { argocd = { domian = "argocd.acme.example" } }
→ kube: unknown attribute. Allowed per module: {"argocd":["admin_enabled","domain",…],…}

kube = { hello = { replicas = "three" } }
→ kube: an attribute has the wrong type. Each value must have the type of its catalog default: …

kube = { velero = { enabled = true } }        # on gcp
→ kube: a module is not offered on gcp. Cloud-bound modules: {"gateway_api":["aws","azure","scaleway"],"velero":["aws"]}
```

Each module adds its own rules, with a message that says what to do:
`external_dns` enabled without `domain_filters`, `kyverno_policies` without
`kyverno`, `keda.services` or `velero` without `crossplane`, a secret-bearing
chart path in `values`. The rules are the validations of `kube` in
[`variables.tf`](../../opentofu/bootstrap/variables.tf); the schema is in
[Inputs](../reference/inputs.md).

## The plan warns that Crossplane has no identity

```text
kube.crossplane.enabled is set without aws.crossplane: the AWS provider runs with no identity, and every CloudAccess will fail.
```

A `check`, not an error: Crossplane installs and converges, but every role a
module declares fails at the AWS API. Set
`aws.crossplane = { allowed_services = [ … ] }`, naming the services your
modules use, or keep Crossplane off.

## The plan says the cluster has no schedulable node

```text
The cluster has no schedulable node (schedulable_nodes = 0), so CoreDNS and the Flux operator cannot start.
```

On aws the foundations' `bootstrap_node_count` sets it; it must be at least
1. Without nodes Helm would wait `helm_timeout_seconds` for pods that never
schedule, and the EKS add-ons would report `DEGRADED`.

## Calls to AWS hang without an error

A pod using Pod Identity (Crossplane's AWS providers first) waits on
`169.254.170.23` and logs nothing. The Pod Identity Agent is missing:
`eks_addons.pod_identity_agent` is `false`, or the add-on did not install.
Check `aws eks describe-addon --cluster-name <cluster> --addon-name
eks-pod-identity-agent`. A pod admitted before its association existed never
gets credentials either: delete it so it is recreated.

## A Crossplane provider stays Healthy=False while its pods are Ready

The AWS `Provider`s report `Healthy=False`, `Deployment does not have minimum
availability`, while their pods are Running and Ready: the package manager's
view of the Deployment is stale. The `crossplane-provider-config`
`ResourceSet` waits on that condition, so every module with cloud access
waits with it. Seen once in five e2e runs; it clears when Crossplane
re-evaluates the revision. To read it:

```sh
kubectl get providers.pkg.crossplane.io
kubectl get providerrevisions.pkg.crossplane.io
kubectl -n crossplane-system logs deploy/crossplane
```

## Turning a module off takes five minutes

A values change drives a Helm upgrade with `--wait`, and helm-controller
honours a deletion only once the running action returns. Turned off during
that upgrade, the module waits for the upgrade's five-minute timeout, and
helm-controller's log shows `running 'upgrade' action with timeout of 5m0s`
then `uninstalled Helm release for deleted resource`. Wait for the release to
be idle (`Ready` and `Released` true, no `Reconciling`) before turning a
module off.

## The OCIRepository refuses the signature

`SourceVerified` false: the artifact's signature does not match
`cosign_identity`.

- A branch build pinned without its identity: set `cosign_identity` to that
  branch ([Upgrade the socle](upgrade.md#test-a-build-before-it-is-released)).
- A hand-written identity: both fields are regexes, anchored, every dot
  escaped. In HCL each backslash is doubled: `"^https://github\\.com/…$"`.
- A mirror that re-signed the artifact: copy the original signature with the
  artifact instead.

The subject includes the workflow file's name, `publish-artifact.yaml`, and
its ref.

## MANIFEST_UNKNOWN on the OCIRepository

The tag no longer exists in the registry. Branch tags are deleted when their
branch is deleted and after seven days, alphas after thirty
([Artifacts](../reference/artifacts.md#tags)). A cluster pinned to one stops
pulling. Move `socle_version` to a release, or to a newer build. Two branch
names with the same slug (`feat-x`, `feat/x`) share their tags: deleting one
deletes the other's.

## When one apply is not enough

- **Replacing the cluster.** A ForceNew change of the foundations makes the
  endpoint unknown at plan, and the helm provider cannot refresh its
  releases. Apply with `-target=module.foundations` first, then a full apply.
- **Destroying with the API unreachable.** The releases are deleted before
  the cluster, which needs the API. If the runner cannot reach it, run
  `tofu state rm module.socle` first ([Uninstall](uninstall.md#everything)).
