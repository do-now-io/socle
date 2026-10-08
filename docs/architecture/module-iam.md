---
title: Module IAM
description: Why each catalog module declares its own cloud access through Crossplane, and the one grant the foundations make to allow it.
sidebar:
  order: 3
---

Some modules act on the cloud: external-dns writes DNS records, KEDA reads
queues, External Secrets reads a secret manager, Velero writes a bucket. Each
needs a role on each cloud.

## The rule

**A module carries its own access.** Its `ResourceSet` declares the role, its
policy and its binding as Crossplane managed resources, then installs the
workload that runs under it. One template, one review.

**OpenTofu never creates a role for a module**, not even as an option. A
foundations module therefore never changes because of the catalog.

## The one grant the foundations make

Crossplane's own identity is the one thing the artifact cannot carry. The
foundations grant it once, the same for every client, bounded by shape
([`opentofu/aws`](../../opentofu/aws/variables.tf), variable `crossplane`):

- every role it creates lives under `/socle/<cluster>/` and carries the
  foundations' permissions boundary; IAM refuses any other;
- the boundary allows only `aws.crossplane.allowed_services` (empty by
  default) and always denies `iam`, `sts`, `organizations`, `account`, `sso`
  and `identitystore`;
- Crossplane cannot attach managed policies, edit the boundary, or touch a
  role outside its path.

A module on a new service needs one word in `allowed_services`: a reviewed
change. The root wires the boundary into `kube.crossplane.permissions_boundary`.

## The ordering chain

```text
foundations: cluster, Crossplane's role and boundary
  └▶ bootstrap: Cilium, CoreDNS, Pod Identity Agent, then Flux
       └▶ crossplane module: core, providers, provider config
            └▶ <module>: its role and Pod Identity association
                 └▶ <module>-workload: the chart, once the role is Ready
```

On AWS the role must exist before the pod: Pod Identity injects credentials
at admission only, so a pod admitted earlier runs without them until it is
recreated.

<details>
<summary>Under the hood</summary>

The child waits on an explicit `readyExpr`, because a managed resource not
yet created has no Ready condition, which kstatus reads as healthy. The
module's own `ResourceSet` `dependsOn` the `crossplane` one, which always
exists and is Ready at once when Crossplane is off.

What runs before Crossplane takes its access elsewhere: Cilium's operator
from the bootstrap nodes' role; the EBS and EFS CSI drivers from roles the
bootstrap creates outside `/socle/<cluster>/`; the Pod Identity Agent is
installed before `flux-operator`.

</details>

## Per cloud

| Cloud | Crossplane providers | A module that needs access |
| --- | --- | --- |
| AWS | IAM, EKS and S3, on Pod Identity | declares its role, policy and association; refused at plan when Crossplane is off, a service is not allowed, or the region is missing |
| GCP, Azure, Scaleway | none yet | runs without a socle-made role; you bring a credential, as its page says |

Versions and the AWS contract: [crossplane](../catalog/crossplane.md).
