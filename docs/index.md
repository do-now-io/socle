---
title: Socle
description: An open source GitOps distribution for managed Kubernetes clusters, on EKS, GKE, AKS and Scaleway Kapsule.
template: splash
hero:
  tagline: An open source GitOps distribution for managed Kubernetes clusters. Pick your cloud, pick your modules, and upgrade the whole platform with one line in Git.
---

:::note[Under construction]
This site is being built ([#71](https://github.com/do-now-io/socle/issues/71)). Its landing page comes with the
site's design; until then, the [README](../README.md) is the best introduction.
:::

[Get started](getting-started/concepts.md) · [Browse the catalog](catalog/index.md)

## The three ideas

- **Foundations.** One OpenTofu apply creates the cluster on your cloud, installs Flux and hands the catalog over.
  After that, OpenTofu steps away.
- **Catalog.** À la carte modules, one Flux Operator `ResourceSet` each, rendered from the inputs you validated at plan.
- **Upgrades.** `socle_version` pins the OpenTofu modules and the signed Flux artifact together. An upgrade is one line.

## Pick your cloud

- [AWS · EKS](clouds/aws/index.md)
- [GCP · GKE](clouds/gcp/index.md)
- [Azure · AKS](clouds/azure/index.md)
- [Scaleway · Kapsule](clouds/scaleway/index.md)
