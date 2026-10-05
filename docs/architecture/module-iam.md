---
title: Module IAM
description: Why each catalog module declares its own cloud access through Crossplane, and the one grant the foundations make to allow it.
sidebar:
  order: 3
---

Some catalog modules act on the cloud: external-dns writes DNS records, KEDA
reads queue depths, External Secrets reads a secret manager, Velero writes a
bucket. Each needs a role, on each cloud it runs on. This page explains where
those roles come from, and why that place.

## The rule

**A module that needs a cloud service carries its own access.** It ships its
`ServiceAccount` and the objects that create the role granting that access,
as Crossplane managed resources rendered by its own `ResourceSet`, inside the
artifact. `external_dns` is the worked example: on AWS its `ResourceSet`
declares the IAM role, grants it Route 53, binds it to the `ServiceAccount`
it renders through a Pod Identity association, and only then installs the
release that runs under it. One template, one module, one review.

**OpenTofu never creates a role for a module.** Not as a default, not as an
option, not as an escape hatch for a cluster without Crossplane. Five modules
on four clouds would be twenty IAM blocks a foundations module would carry
and a client would wire through his tfvars, and each new module would add
four more.

The invariance this enforces: **a foundations module never changes because of
the catalog.** `opentofu/aws` describes the same cluster whether the client
runs external-dns, ten modules or none. An optional IAM block per consumer
would make the cloud module a function of the modules chosen on top of it.
The decision is
[SOCLE-04](../decisions/socle.md#socle-04-each-module-owns-its-cloud-access-the-foundations-never-change).

## The one grant the foundations make

One thing cannot live in the artifact, because it is what lets the artifact
act on the cloud at all: the identity Crossplane's own provider runs as. The
foundations grant it expressly and once, per cloud. It is broad by design:
Crossplane creates whatever role a module declares, and the foundations
cannot know that list without becoming a function of the catalog again. It
is the same for every client and unchanged by any catalog choice, so it does
not break the invariance.

That grant is the socle's most powerful object, and it is bounded by shape
rather than by list. On AWS ([`opentofu/aws`](../../opentofu/aws/variables.tf),
variable `crossplane`):

- every role Crossplane creates lives under the path `/socle/<cluster>/` and
  must carry the permissions boundary the foundations write; IAM refuses the
  creation of any other;
- the boundary allows only the services the client lists in
  `aws.crossplane.allowed_services` (empty by default), and always denies
  `iam`, `sts`, `organizations`, `account`, `sso` and `identitystore`;
- Crossplane cannot attach managed policies, edit the boundary, or touch a
  role outside its path, its own included.

A module that uses a service already allowed needs no change anywhere; one
that uses a new service needs one word in the client's
`aws.crossplane.allowed_services`, a reviewed change to what the cluster may
ever touch. The root wires the boundary's ARN into
`kube.crossplane.permissions_boundary` for the modules to read.

## What runs before Crossplane cannot use it

Anything needed before Crossplane exists takes its access elsewhere, and that
is the boundary rather than an exception:

- Cilium's operator creates ENIs on AWS from its node's role: the foundations
  attach its policy to the bootstrap nodes' role.
- The EKS add-ons' roles (EBS CSI, EFS CSI) are created by the bootstrap
  module beside the add-ons, outside `/socle/<cluster>/`, so nothing
  Crossplane may rewrite holds the storage drivers' permissions.
- The Pod Identity Agent, which hands every association its credentials,
  Crossplane's included, is installed before `flux-operator`.

## The ordering chain

| # | Link | Where it lives |
| --- | --- | --- |
| 1 | The cluster, Crossplane's role, the boundary, Crossplane's Pod Identity association | the foundations, in the client's one apply |
| 2 | Cilium, CoreDNS, the Pod Identity Agent | the bootstrap module, before Flux |
| 3 | Flux | the bootstrap module |
| 4 | Crossplane core, its providers, the provider config | the `crossplane` module, one `ResourceSet` in steps |
| 5 | A module's role and its binding | the module's own `ResourceSet` |
| 6 | The module's workload | a child `ResourceSet`, `<module>-workload`, which `dependsOn` the role and the association being Ready |

Link 5 finishes before link 6 starts on AWS: the Pod Identity webhook injects
credentials at admission, and only if the association already exists. A pod
admitted before its association runs without credentials until it is
recreated. The child waits on an explicit `readyExpr`, because a managed
resource not yet created carries no Ready condition, which kstatus reads as
healthy. The module's own `ResourceSet` `dependsOn` the `crossplane` one,
which always exists and is Ready at once when Crossplane is off.

## Per cloud

| Cloud | Crossplane providers | What a module that needs access does |
| --- | --- | --- |
| AWS | IAM, EKS and S3 providers, on Pod Identity | declares its role, policy and Pod Identity association; refused at plan when a precondition is missing (Crossplane off, a service outside the allowlist, no region) |
| GCP, Azure, Scaleway | none yet | runs without a socle-made role; the client brings a credential, as each module page says |

The tooling, its versions and the AWS contract a module follows are on the
[crossplane](../catalog/crossplane.md) page; the reasoning per cloud is in
[crossplane decisions](../decisions/crossplane.md). Each module page has a
*Cloud access* section saying what it declares.
