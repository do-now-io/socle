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

**A green `tofu apply` is not convergence**: it proves the objects were
deposited. `socle-root` is Ready only when every module is.

## Symptoms

### The plan refuses kube

**What you see:**

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

**Why:** `kube` is validated against the catalog at plan. Modules add their
own rules: `external_dns` without `domain_filters`, `kyverno_policies`
without `kyverno`, `keda.services` or `velero` without `crossplane`, a
secret-bearing path in `values`.

**Fix:** use what the message allows; the schema is in
[Inputs](../reference/inputs.md), the rules in
[`variables.tf`](../../opentofu/bootstrap/variables.tf).

### The plan warns that Crossplane has no identity

**What you see:** `kube.crossplane.enabled is set without aws.crossplane: the AWS provider runs with no identity, and every CloudAccess will fail.`

**Why:** Crossplane converges, but every module role then fails at the AWS
API.

**Fix:** `aws.crossplane = { allowed_services = [ … ] }` with the services
your modules use, or keep Crossplane off.

### The plan says the cluster has no schedulable node

**What you see:** `The cluster has no schedulable node (schedulable_nodes = 0), so CoreDNS and the Flux operator cannot start.`

**Why:** the foundations' `bootstrap_node_count` is 0 (on aws).

**Fix:** set `bootstrap_node_count` to at least 1.

### Calls to AWS hang without an error

**What you see:** a pod using Pod Identity (Crossplane's AWS providers first)
waits on `169.254.170.23` and logs nothing.

**Why:** the Pod Identity Agent is missing, or the pod was admitted before
its association existed.

**Fix:** set `eks_addons.pod_identity_agent = true` and check
`aws eks describe-addon --cluster-name <cluster> --addon-name eks-pod-identity-agent`;
delete a pod admitted too early so it is recreated.

### A Crossplane provider stays Healthy=False while its pods are Ready

**What you see:** `Healthy=False`, `Deployment does not have minimum
availability`, on running pods; every module with cloud access waits.

**Why:** the package manager's view of the Deployment is stale (once in five
e2e runs).

**Fix:** it clears when Crossplane re-evaluates the revision. To read it:

```sh
kubectl get providers.pkg.crossplane.io
kubectl get providerrevisions.pkg.crossplane.io
kubectl -n crossplane-system logs deploy/crossplane
```

### Turning a module off takes five minutes

**What you see:** helm-controller logs `running 'upgrade' action with timeout
of 5m0s`, then `uninstalled Helm release for deleted resource`.

**Why:** the module was turned off during the Helm upgrade a values change
drives; the deletion waits for it.

**Fix:** before turning a module off, wait for its release to be idle:
`Ready` and `Released` true, no `Reconciling`.

### The OCIRepository refuses the signature

**What you see:** `SourceVerified` false.

**Why:** the signature does not match `cosign_identity`, whose subject is
`publish-artifact.yaml` on its ref.

**Fix:**

- a branch build: set `cosign_identity` to that branch
  ([Upgrade the socle](upgrade.md#test-a-build-before-it-is-released));
- a hand-written identity: anchored regexes, every dot escaped, each
  backslash doubled in HCL: `"^https://github\\.com/…$"`;
- a re-signed mirror: copy the original signature with the artifact.

### MANIFEST_UNKNOWN on the OCIRepository

**What you see:** `MANIFEST_UNKNOWN`; the cluster stops pulling.

**Why:** the tag was deleted: branch tags with their branch and after seven
days, alphas after thirty
([Artifacts](../reference/artifacts.md#tags)). `feat-x` and `feat/x` share
their tags.

**Fix:** move `socle_version` to a release, or to a newer build.

### When one apply is not enough

- **Replacing the cluster.** A ForceNew foundations change leaves the helm
  provider unable to refresh. Fix: apply the foundations alone first
  (`-target=module.socle.module.foundations` with the AWS root), then a full
  apply.
- **Destroying with the API unreachable.** The releases need the API to go.
  Fix: drop the bootstrap from the state first
  (`tofu state rm module.socle.module.socle` with the AWS root)
  ([Uninstall](uninstall.md#everything)).
