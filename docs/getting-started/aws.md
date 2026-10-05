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
- OpenTofu 1.10 or later, the AWS CLI, `kubectl`;
- a GHCR login with `read:packages`, while the modules package is private.

## Write your tfvars

Copy [`opentofu/clusters/aws`](../../opentofu/clusters/aws) at the release you
want (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
`prod.tfvars.example`). In `main.tf`, point both sources at the published
package:

```hcl
module "foundations" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/aws?tag=${var.socle_version}"
  # ...
}

module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"
  # ...
}
```

Add the backend in a `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket       = "acme-tofu-state"
    key          = "socle/aws/acme-prod.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
  }
}
```

Then `cp prod.tfvars.example prod.tfvars`. The smallest file that applies:

```hcl
socle_version = "0.0.0" # x-release-please-version

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
```

`kubernetes_version` has no default: `1.34` is what CI applies; pick a minor
in EKS standard support ([SOCLE-05](../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n)).
`availability_zones` takes at least two; each adds a NAT Gateway.

Optionally, under `aws`:

```hcl
  # The ACM certificate of the two shared Gateways, validated in the public
  # Route 53 zone acme.example. Without it no Gateway is created.
  gateway_certificate = { domain = "acme.example" }

  # Crossplane's IAM role; allowed_services is the ceiling of every role a
  # catalog module gets.
  crossplane = { allowed_services = ["route53"] }
```

With both and `kube.crossplane = { enabled = true }`, the root turns on
`external_dns` for that domain. Every other key: [Configure](../guides/configure.md).

## Apply

`tofu init` needs the tfvars too: the module sources read `socle_version`.

```sh
tofu init -var-file=prod.tfvars
tofu apply -var-file=prod.tfvars
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
