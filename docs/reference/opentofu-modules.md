---
title: OpenTofu modules
description: The generated reference of every OpenTofu module, its requirements, resources, inputs and outputs.
sidebar:
  order: 1
---

Every module under [`opentofu/`](../../opentofu/), as terraform-docs writes
it in the module's README. `pr-static.yaml` fails when one of these blocks is
not current. A client consumes them from
`oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/<module>?tag=<socle_version>`
([Artifacts](artifacts.md)).

## aws

The AWS foundations: VPC, EKS Standard cluster with no CNI, the bootstrap
node group, the identities, Crossplane's role and boundary. See
[AWS](../clouds/aws/index.md).

::include{file="opentofu/aws/README.md" section="tf-docs"}

## gcp

The GCP foundations: a GKE Autopilot cluster in its own network. See
[GCP](../clouds/gcp/index.md).

::include{file="opentofu/gcp/README.md" section="tf-docs"}

## azure

The Azure foundations: VNet and an AKS Standard cluster with no CNI. See
[Azure](../clouds/azure/index.md).

::include{file="opentofu/azure/README.md" section="tf-docs"}

## scaleway

The Scaleway foundations: a private network and a Kapsule cluster. See
[Scaleway](../clouds/scaleway/index.md).

::include{file="opentofu/scaleway/README.md" section="tf-docs"}

## bootstrap

Cilium and CoreDNS where the cloud provides none, the EKS add-ons on aws, the
Flux Operator and instance, and the envelope carrying the inputs. Its `kube`
schema is in [Inputs](inputs.md).

::include{file="opentofu/bootstrap/README.md" section="tf-docs"}

## clusters/aws

The root a client copies for AWS: the aws foundations and the bootstrap in
one apply, one tfvars per cluster.

::include{file="opentofu/clusters/aws/README.md" section="tf-docs"}
