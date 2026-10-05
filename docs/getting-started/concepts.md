---
title: Concepts
description: 'Foundations, catalog and upgrades: the three ideas the socle is built on, before your first cluster.'
sidebar:
  order: 0
---

The socle is a GitOps distribution for managed Kubernetes: EKS, GKE, AKS and
Scaleway Kapsule. You describe a cluster in one tfvars file; one `tofu apply`
creates it and hands it to Flux, which installs and keeps converged the
platform modules you chose. Three ideas carry the whole design. Read them
once, then pick your cloud below.

## 1. Foundations: the cluster, created once by OpenTofu

The foundations are one OpenTofu module per cloud: the network, the managed
cluster, the few nodes the socle starts on, and the identities. You do not
write them. You copy a root that calls them, and fill the cloud block of
your tfvars:

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

In the same apply, the **bootstrap** module installs what Flux needs before
it can run (Cilium and CoreDNS on the clouds that ship a cluster with no
network, the EKS add-ons on AWS), then the Flux Operator, then your
configuration as a single Kubernetes object. After that, OpenTofu steps away
until you change the tfvars. A foundations module describes the same cluster
whatever you run on it: choosing modules never changes it.

## 2. Catalog: modules you turn on, rendered by Flux

The catalog is a set of platform modules: ArgoCD, the Gateway API, DNS,
secrets, autoscaling, admission policies, backups, and a monitoring stack.
Each is one Flux Operator `ResourceSet`, shipped in a signed OCI artifact.
Flux pulls the artifact, checks its signature, and renders each module from
your configuration. You list only what differs from the defaults:

```hcl
kube = {
  argocd          = { domain = "argocd.acme.example" }
  victoria_traces = { enabled = true }
}
```

A misspelt module or attribute fails `tofu plan`, with the allowed values in
the message. Every module also takes `values`, any value of its chart, and
yours win over the socle's; secrets go in a Kubernetes Secret you name in
`values_secret`, so they never reach the OpenTofu state. A module that needs
cloud access declares its own role, through Crossplane. Turn a module off
and Flux removes what it installed.

| Layer | What it is | Owned by |
| --- | --- | --- |
| Foundations | network, managed cluster, nodes, identities | OpenTofu, applied once |
| Bootstrap | Cilium and CoreDNS where needed, the Flux Operator, your validated inputs | OpenTofu, in the same apply |
| Catalog | one `ResourceSet` per module, rendered from your inputs | Flux, from the signed artifact |

## 3. Upgrades: one line

`socle_version` pins everything at once: the OpenTofu modules, the Flux
artifact, and every chart and add-on version they carry. An upgrade is that
line and a `tofu apply`. Releases are signed; Flux verifies the artifact on
every reconciliation and refuses one that is not the socle's.

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

The design behind these three ideas is in the
[architecture overview](../architecture/overview.md).
