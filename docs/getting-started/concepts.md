---
title: Concepts
description: 'Foundations, catalog and upgrades: the three ideas the socle is built on, before your first cluster.'
sidebar:
  order: 0
---

The socle is a GitOps distribution for EKS, GKE, AKS and Scaleway Kapsule.
You describe a cluster in one tfvars file; `tofu apply` creates it and hands
it to Flux, which installs and keeps converged the modules you chose.

## 1. Foundations: the cluster, created once by OpenTofu

One OpenTofu module per cloud builds the network, the managed cluster, the
first nodes and the identities. You copy a root that calls it and fill the
cloud block:

```hcl
aws = {
  region             = "eu-west-3"
  cluster_name       = "acme-prod"
  owner              = "platform"
  environment        = "prod"
  kubernetes_version = "1.34"
  availability_zones = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
}
```

In the same apply, the **bootstrap** installs what Flux needs first (Cilium
and CoreDNS where the cloud ships none, the EKS add-ons on AWS), the Flux
Operator, and your configuration. Then OpenTofu steps away.

## 2. Catalog: modules you turn on, rendered by Flux

Each catalog module (ArgoCD, Gateway API, DNS, secrets, autoscaling,
policies, backups, monitoring) is one Flux `ResourceSet` in a signed OCI
artifact. You list only what differs from the defaults:

```hcl
kube = {
  argocd          = { domain = "argocd.acme.example" }
  victoria_traces = { enabled = true }
}
```

A typo fails `tofu plan`. `values` takes any chart value and wins over the
socle's; secrets go in `values_secret`, out of the state. A module that needs
cloud access declares its own role, through Crossplane. Turn a module off and
Flux removes it.

## 3. Upgrades: one line

`socle_version` pins the modules, the artifact and every chart they carry. An
upgrade is that line and a `tofu apply`; Flux refuses an artifact the socle
did not sign.

## How you know it worked

A green apply means the objects were deposited. The cluster has converged
when the root `ResourceSet` is Ready:

```sh
kubectl -n flux-system get resourceset socle-root
```

## Pick your cloud

| Cloud | Quickstart | State |
| --- | --- | --- |
| AWS · EKS | [Get started on AWS](aws.md) | foundations and the one-apply root |
| GCP · GKE | [Get started on GCP](gcp.md) | foundations; no root yet |
| Azure · AKS | [Get started on Azure](azure.md) | foundations; no root yet |
| Scaleway · Kapsule | [Get started on Scaleway](scaleway.md) | foundations; no root yet |

The design is in the [architecture overview](../architecture/overview.md).
