---
title: Uninstall
description: Turn one module off, remove the socle from a cluster, or destroy everything, and what is left behind by design.
sidebar:
  order: 4
---

Three scopes, from the smallest.

## One module

Set `kube.<module>.enabled = false` and apply
([Enable a module](enable-a-module.md#5-turn-it-off)). Turn `crossplane` off
last: the roles it created for other modules stay otherwise.

## The socle, keeping the cluster

1. Wait for every module's `ResourceSet` to be Ready, if you just turned one
   on.
2. Destroy the bootstrap module:

   ```sh
   tofu destroy -target=module.socle.module.socle
   ```

`flux-system` is then left with no `ResourceSet`, `FluxInstance` or
Deployment, and no module namespace remains (28 s on floci, 2026-09-30).

:::caution
Destroying right after turning a module on can leave that module's objects,
namespace included, in the cluster. Step 1 prevents it.
:::

<details>
<summary>Under the hood</summary>

The releases go in reverse: the envelope, the Flux instance, the operator,
then on aws the EKS add-ons and CoreDNS, and on aws and azure Cilium. The
`socle` Kustomization's `deletionPolicy: WaitForTermination` holds the
envelope until every catalog `ResourceSet` is finalized, so the operator is
never removed with work left
([Uninstall order](../architecture/flux-catalog.md#uninstall-order)). The
operator uninstalls from the inventory of its last completed reconcile,
hence step 1. CI asserts the empty result on every run (the `destroyed`
suite).

</details>

## Everything

With `karpenter` on, turn it off first and wait for its nodes to go
(`kubectl get nodeclaims` empty): they are in no OpenTofu state, and an
instance left behind stops the VPC's deletion
([karpenter](../catalog/karpenter.md)).

On GCP, the cluster carries deletion protection: set
`gcp.deletion_protection = false` and apply first. Then, on both:

```sh
tofu destroy
```

On GCP a first destroy fails on the certificate map, the regional
certificate and the proxy-only subnetwork: GKE removes the Gateways' load
balancers after the cluster. Run `tofu destroy` again a few minutes later
(measured on a sandbox, 2026-10-07).

The releases go before the cluster, which needs the API. If the runner can no
longer reach it (on AWS it left `cluster_endpoint_public_access_cidrs`, say),
drop the releases from the state first:

```sh
tofu state rm module.socle.module.socle
tofu destroy
```

Nothing then deletes the module access Crossplane created: see the table
below.

## What is left behind, by design

| What | Why | How to remove it |
| --- | --- | --- |
| The Gateway API CRDs | deleting a CRD deletes every Gateway and route | by hand once unused, or with the cluster |
| The CRDs of `external_secrets`, `keda`, `velero`, `crossplane`, `argocd_image_updater` | they hold your objects | as above |
| Module roles (AWS), when `crossplane` went first or the bootstrap left the state | nothing is left to delete them | delete the roles under `/socle/<cluster>/` in IAM |
| Module bindings (GCP), when `crossplane` went first or the bootstrap left the state | nothing is left to delete them; a socle created in the project next inherits them | remove the `principal://…` members of the project's IAM policy |
| Velero's bucket (S3 on AWS, GCS on GCP) | Crossplane may not delete a bucket of data | in the cloud, once its backups are not needed |
| Karpenter's CRDs, and the NodePools you wrote | Helm never deletes a chart's CRDs | by hand once unused, or with the cluster |
| An instance Karpenter launched, when the socle went while it drained | only Karpenter terminates its nodes | terminate the instances tagged `karpenter.sh/nodepool` and `kubernetes.io/cluster/<cluster>` in EC2 |
| A pending Velero `Restore` | its finalizer holds the namespace | delete the `Restore` ([Restore a backup](restore-a-backup.md)) |
| `ImageUpdater` objects in `argocd`, once `argocd_image_updater` is off | their finalizer holds them, and the `argocd` namespace, with no controller to release it | delete them before turning the module off, or release them: `kubectl -n argocd patch imageupdater <name> --type merge -p '{"metadata":{"finalizers":[]}}'` |
| The Applications and other objects `gitops` applied from your path | the module orphans them rather than delete your workloads ([gitops](../catalog/gitops.md)); an Application's `resources-finalizer.argocd.argoproj.io` then holds it, and the `argocd` namespace, with no controller to release it | delete them, or their finalizers, while ArgoCD still runs, before the uninstall |
| A mirror's pull secret | `flux-system` outlives the operator's release | with the cluster |
| On aws, `/aws/eks/<cluster>/cluster`, when control-plane logs were on and the destroy was interrupted during its five-minute wait, or EKS delivered later than that | EKS recreates the group when it delivers, with no retention and no key ([AWS-20](../decisions/aws.md#aws-20-a-destroy-leaves-no-log-group-behind)); the next apply of the same `cluster_name` fails on `ResourceAlreadyExistsException` | `aws logs delete-log-group --log-group-name /aws/eks/<cluster>/cluster`, or keep it: `tofu import 'module.foundations.aws_cloudwatch_log_group.cluster' /aws/eks/<cluster>/cluster` |
| On gcp, the cluster's flow, NAT and GKE logs | they are in the project's `_Default` bucket, which the socle does not own ([GCP-17](../decisions/gcp.md#gcp-17-the-logs-live-in-the-projects-buckets-so-a-destroy-leaves-nothing-to-collide)) | they expire with the bucket's retention, 30 days by default |
