---
title: Configure a cluster
description: Set up the root and one tfvars file per cluster, choose the catalog with kube, and pass chart values and secrets.
sidebar:
  order: 0
---

A cluster is one tfvars file, applied by a root you copy once.

**Before you start:** your cloud's [prerequisites](../clouds/aws/prerequisites.md)
are met. AWS is the only cloud with a root today.

## 1. Copy the root

Copy [`opentofu/clusters/aws/`](../../opentofu/clusters/aws/) into your
repository and never edit its logic. Point both module sources at the
published package:

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

Commit the root's `.terraform.lock.hcl`, and add your state backend: the root
declares none.

## 2. Write one tfvars per cluster

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

| Block | What it holds |
| --- | --- |
| `socle_version` | A released version, never `latest` or `main`; the only line an [upgrade](upgrade.md) touches. |
| `aws` | The foundations' variables. Keys without a default, `kubernetes_version` among them, are required. Every option: [`prod.tfvars.example`](../../opentofu/clusters/aws/prod.tfvars.example). |
| `kube` | Only what differs from the catalog's defaults, in `snake_case`. Defaults: [Inputs](../reference/inputs.md#the-catalog-schema); modules: [catalog](../catalog/index.mdx). |

On AWS, keep `storage_size = ""` on the Victoria backends until the cluster
has a default StorageClass: EKS marks none, and their claims would stay
`Pending` ([Observability](../architecture/observability.md#where-the-data-lives)).

## 3. Pass chart values

Every module with a chart takes `values`, any value of its chart. Yours win
over the socle's defaults and over the module's named attributes:

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

`values` lands in the OpenTofu state, so secrets are refused there at plan.
Put them in a Secret with a `values.yaml` key, in the module's namespace, and
name it in `values_secret`:

```sh
kubectl -n argocd create secret generic argocd-values --from-file=values.yaml
kubectl -n argocd label secret argocd-values reconcile.fluxcd.io/watch=Enabled
```

The Secret is merged last and optional; the label applies a change at once.
OpenTofu never reads it.

## 4. Adjust what precedes Flux, if you need to

On aws the root also takes `cilium`, `coredns` and `eks_addons`, every key
optional ([Inputs](../reference/inputs.md#cilium-coredns-and-the-eks-add-ons)):

```hcl
cilium     = { hubble = true }
coredns    = { values = { replicaCount = 3 } }
eks_addons = { efs_csi = true }
```

Leave `cilium.enabled` at `true` on a real EKS: the cluster has no other
network.

## 5. Plan and apply

```sh
tofu init
tofu plan  -var-file=clusters/prod.tfvars
tofu apply -var-file=clusters/prod.tfvars
```

A misspelt name, a wrong type, a module not offered on your cloud or a secret
in `values` fails the plan
([Troubleshooting](troubleshooting.md#the-plan-refuses-kube)). A green apply
is not convergence: check
`kubectl -n flux-system get resourceset socle-root`
([Enable a module](enable-a-module.md#4-check-that-it-converged)).
