---
title: 'Quickstart: AWS'
description: From an empty AWS account to an EKS cluster where the socle has converged, in one apply.
sidebar:
  order: 1
---

One `tofu apply` of the AWS root builds the VPC, EKS and its bootstrap nodes,
installs Cilium, CoreDNS, the EKS add-ons and Flux; Flux then converges the
catalog.

## Before you start

From [Prerequisites](../clouds/aws/prerequisites.md):

- an S3 state bucket;
- a principal that can create the resources (it becomes the cluster's first
  admin);
- the public IP of the machine that applies;
- OpenTofu 1.10 or later, the AWS CLI, `kubectl`.

## Write your main.tf

One file in an empty directory: the state backend, then the socle's AWS root
called as a module. Change the names, the region and the IP, keep the rest:

```hcl title="main.tf"
terraform {
  backend "s3" {
    bucket       = "acme-tofu-state"
    key          = "socle/aws/acme-prod.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
  }
}

locals {
  socle_version = "0.0.0" # x-release-please-version
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/clusters/aws?tag=${local.socle_version}"

  socle_version = local.socle_version

  aws = {
    region             = "eu-west-3"
    cluster_name       = "acme-prod"
    owner              = "platform"
    environment        = "prod"
    kubernetes_version = "1.34"
    availability_zones = ["eu-west-3a", "eu-west-3b"]

    # The public IP of the machine that applies, and your admins'.
    cluster_endpoint_public_access_cidrs = ["203.0.113.10/32"]
  }

  kube = {
    # No default StorageClass on EKS: keep the monitoring data in an emptyDir
    # until you create one (see Limits).
    victoria_metrics = { storage_size = "" }
    victoria_logs    = { storage_size = "" }
  }
}

output "cluster_name" {
  value = module.socle.cluster_name
}
```

- `socle_version` is the only line an [upgrade](../guides/upgrade.md) touches:
  it moves the module source and the Flux artifact together.
- `kubernetes_version` has no default: `1.34` is what CI applies; pick a
  minor in EKS standard support.
- `availability_zones` takes at least two; each adds a NAT Gateway.

To serve routes on your domain and let modules have their own AWS role, add
under `aws`:

```hcl
    # The ACM certificate of the two shared Gateways, validated in the public
    # Route 53 zone acme.example. Without it no Gateway is created.
    gateway_certificate = { domain = "acme.example" }

    # Crossplane's IAM role; allowed_services is the ceiling of every role a
    # catalog module gets.
    crossplane = { allowed_services = ["route53"] }
```

With both and `crossplane = { enabled = true }` under `kube`, external-dns
turns on for that domain. Every other key: [Configure](../guides/configure.md).

## Apply

```sh
tofu init
tofu apply
```

The apply ends once Flux's objects are in the cluster; Flux converges the
catalog after that.

## Check it converged

```sh
aws eks update-kubeconfig --region eu-west-3 --name acme-prod
kubectl -n flux-system get resourceset
kubectl -n flux-system get ocirepository socle
```

`socle-root` at `READY True` means every module's `ResourceSet` is applied
and healthy; the `OCIRepository` shows the pulled digest and
`SourceVerified`. If `socle-root` stays not Ready, the module's `ResourceSet`
names what is waiting: see [Troubleshooting](../guides/troubleshooting.md).

## Next steps

- [Enable a module](../guides/enable-a-module.md) and
  [Configure](../guides/configure.md) it.
- [Upgrade](../guides/upgrade.md): one line, `socle_version`.
- [Foundations](../clouds/aws/foundations.md) and
  [Limits](../clouds/aws/limits.md) on AWS.
- [Uninstall](../guides/uninstall.md).
