---
title: Configure a cluster
description: Set up the root and one tfvars file per cluster, choose the catalog with kube, and pass chart values and secrets.
sidebar:
  order: 0
---

A cluster is one tfvars file, applied by a root you copy once. This guide
sets both up. It assumes your cloud's prerequisites are met: see
[AWS](../clouds/aws/prerequisites.md). AWS is the only cloud with a root
today.

## 1. Copy the root

Copy [`opentofu/clusters/aws/`](../../opentofu/clusters/aws/) into your
repository and never edit its logic. In your copy, point both module sources
at the published modules package, with the version as a variable:

```hcl
module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"
  # …
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
  # …
}
```

OpenTofu resolves both at `tofu init` from the tfvars. The repository's own
copy uses relative sources so that CI applies it from a checkout. Commit the
root's `.terraform.lock.hcl`. Add your state backend: the root declares none.

## 2. Write one tfvars per cluster

Three blocks: the version, the cloud, the catalog.

```hcl
# clusters/prod.tfvars
socle_version = "0.0.0" # x-release-please-version

aws = {
  region             = "eu-west-3"
  cluster_name       = "acme-prod"
  owner              = "platform"
  environment        = "prod"
  kubernetes_version = "1.34"
  availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
  gateway_certificate = { domain = "acme.example" }
}

kube = {
  argocd           = { domain = "argocd.acme.example" }
  victoria_metrics = { storage_size = "" }
  victoria_logs    = { storage_size = "" }
  kyverno          = { enabled = true }
}
```

- **`socle_version`** is a released version, never `latest` or `main`. It is
  the only line an upgrade touches ([Upgrade the socle](upgrade.md)).
- **`aws`** mirrors the foundations module's variables, passed through one by
  one. The keys without a default are required; every other key is optional.
  `kubernetes_version` has no default. The full list, with every option
  commented, is
  [`prod.tfvars.example`](../../opentofu/clusters/aws/prod.tfvars.example).
- **`kube`** lists only what differs from the catalog's defaults. A module
  absent from it is at its defaults, on or off as the catalog says. Names are
  `snake_case`. The defaults are in [Inputs](../reference/inputs.md#the-catalog-schema);
  what each module does is on its [catalog page](../catalog/index.mdx).

On AWS, set `storage_size = ""` on the Victoria backends until your cluster
has a default StorageClass: EKS marks none, and their claims would stay
`Pending`. The data then lives in an `emptyDir`
([Observability](../architecture/observability.md#where-the-data-lives)).

## 3. Pass chart values

Every module with a chart takes `values`, any value of its chart, merged over
the socle's defaults. Where yours and the socle's set the same key, yours win,
and so do they over the module's own named attributes:

```hcl
kube = {
  argocd = {
    domain = "argocd.acme.example"
    values = {
      configs = {
        cm   = { "accounts.alice" = "apiKey, login" }
        rbac = { "policy.csv" = "g, alice, role:admin" }
      }
    }
    values_secret = "argocd-values"
  }
}
```

`values` lands in the OpenTofu state and in a ConfigMap, so secrets are
refused there at plan. Put them in a Secret you create in the module's
namespace, with a `values.yaml` key, and name it in `values_secret`:

```sh
kubectl -n argocd create secret generic argocd-values --from-file=values.yaml
kubectl -n argocd label secret argocd-values reconcile.fluxcd.io/watch=Enabled
```

The Secret is merged last and is optional: the module converges without it,
and picks it up when it appears. The label makes a change apply at once
rather than at the release's next interval. OpenTofu never reads it.

## 4. Adjust what precedes Flux, if you need to

On aws the root also takes `cilium`, `coredns` and `eks_addons`, every key
optional:

```hcl
cilium     = { hubble = true }
coredns    = { values = { replicaCount = 3 } }
eks_addons = { efs_csi = true }
```

Their attributes are in
[Inputs](../reference/inputs.md#cilium-coredns-and-the-eks-add-ons). Leave
`cilium.enabled` at `true` on a real EKS: the cluster has no other network.

## 5. Plan and apply

```sh
tofu init
tofu plan  -var-file=clusters/prod.tfvars
tofu apply -var-file=clusters/prod.tfvars
```

A misspelt module or attribute, a value of the wrong type, a module not
offered on your cloud or a secret in `values` fails the plan, with the
allowed values in the message
([Troubleshooting](troubleshooting.md#the-plan-refuses-kube)). A green apply
means the objects are deposited; check that they converged with
`kubectl -n flux-system get resourceset socle-root`
([Enable a module](enable-a-module.md#4-check-that-it-converged)).
