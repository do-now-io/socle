---
title: 'Quickstart: AWS'
description: From an empty AWS account to an EKS cluster where the socle has converged, in one apply.
sidebar:
  order: 1
---

One `tofu apply` of the AWS root builds the VPC, the EKS cluster and its
bootstrap nodes, installs Cilium, CoreDNS, the EKS add-ons and Flux, and
Flux then converges the catalog.

## Before you start

Everything on [Prerequisites](../clouds/aws/prerequisites.md) must exist:

- an S3 bucket for the state;
- a principal that can create the resources, reached through a profile or
  an OIDC role in CI — it becomes the cluster's first admin;
- the public IP of the machine that applies, for
  `cluster_endpoint_public_access_cidrs`;
- OpenTofu 1.10 or later, the AWS CLI and `kubectl`;
- a GHCR login with `read:packages`, while the modules package is private.

## Write your tfvars

Copy the root from the repository at the release you want:
[`opentofu/clusters/aws`](../../opentofu/clusters/aws) — `main.tf`,
`variables.tf`, `outputs.tf`, `versions.tf` and `prod.tfvars.example`. In
`main.tf`, point both module sources at the published modules package:

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

OpenTofu resolves `var.socle_version` at `tofu init`, so the one line in
the tfvars moves the foundations, the bootstrap module and the artifact
together.

Add the state backend, in a `backend.tf` beside them:

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

Then `cp prod.tfvars.example prod.tfvars` and edit it. The smallest file
that applies:

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

- `kubernetes_version` has no default. `1.34` is the version CI applies
  (`prod.tfvars.example` and the e2e fixtures); choose a minor EKS has in
  standard support. The policy is
  [SOCLE-05](../decisions/socle.md#socle-05-the-kubernetes-version-moves-by-rings-n-1-then-n).
- `availability_zones` takes at least two AZs of `aws.region`. Each one adds
  a NAT Gateway.

Two optional blocks under `aws`, each with what it turns on:

```hcl
  # The ACM certificate of the two shared Gateways, validated in the public
  # Route 53 zone acme.example. Without it no Gateway is created.
  gateway_certificate = { domain = "acme.example" }

  # Crossplane's IAM role; allowed_services is the ceiling of every role a
  # catalog module gets.
  crossplane = { allowed_services = ["route53"] }
```

With both, and `kube.crossplane = { enabled = true }`, the root turns on
`external_dns` for that domain by itself. Every other key, and every catalog
module, is in [Configure](../guides/configure.md).

## Apply

```sh
tofu init -var-file=prod.tfvars
tofu apply -var-file=prod.tfvars
```

`tofu init` needs the tfvars: the module sources read `socle_version`.

The apply creates the foundations, then installs Cilium beside the node
group (the nodes are Ready only once Cilium runs on them), then CoreDNS,
the EKS add-ons and the Flux Operator. It ends once Flux's objects are in
the cluster; Flux converges the catalog after that.

## Check it converged

```sh
aws eks update-kubeconfig --region eu-west-3 --name acme-prod
kubectl -n flux-system get resourceset
```

The list holds `socle-root` and one `ResourceSet` per catalog module, on or
off. `socle-root` waits for everything it applies: when it reports
`READY True`, every module's `ResourceSet` is Ready, which means each
module's objects are applied and healthy. A green `tofu apply` alone proves
only that the objects were deposited.

```sh
kubectl -n flux-system get ocirepository socle
```

shows the artifact digest pulled and `SourceVerified`: the signature was
checked. When `socle-root` stays not Ready, the message on the module's
`ResourceSet` names what is waiting; see
[Troubleshooting](../guides/troubleshooting.md).

## Next steps

- [Enable a module](../guides/enable-a-module.md), and set its values in
  [Configure](../guides/configure.md).
- [Upgrade](../guides/upgrade.md): one line, `socle_version`.
- What is decided for you on AWS: [Foundations](../clouds/aws/foundations.md);
  what the socle cannot do there: [Limits](../clouds/aws/limits.md).
- Tearing it down: [Uninstall](../guides/uninstall.md).
