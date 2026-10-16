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

On GCP there is no role to create and no boundary to carry: a module's
identity is its Kubernetes ServiceAccount itself, a Workload Identity
Federation principal named by the project number, and no Google service
account exists ([GCP-14](../decisions/gcp.md#gcp-14-workload-identity-federation-direct-principals-no-google-service-account)).
What bounds Crossplane is a condition on its own grant
([`opentofu/gcp`](../../opentofu/gcp/iam.tf), variable `crossplane`,
[GCP-15](../decisions/gcp.md#gcp-15-crossplanes-grants-bounded-by-the-roles-the-client-allows)):

- Project IAM Admin, under `modifiedGrantsByRole.hasOnly(...)`: it may grant
  and revoke only `gcp.crossplane.allowed_roles` (empty by default, at most
  nine) and the socle's DNS records role, never Project IAM Admin itself;
- buckets under `<cluster_name>-` only, created and configured, never
  deleted, never read;
- nothing of Cloud DNS: external-dns gets the project custom role
  `socleDnsRecords_<cluster>`, created by the foundations, which the root
  wires into `kube.crossplane.dns_records_role`.

A module that needs a new role needs one line in `allowed_roles`: a reviewed
change. Owner, editor, viewer, `iam.*`, `resourcemanager.*` and predefined
admin or owner roles are refused at plan.

## The ordering chain

```text
foundations: cluster, Crossplane's role and boundary (GCP: its conditional grants)
  └▶ bootstrap: Cilium, CoreDNS, Pod Identity Agent, then Flux
       └▶ crossplane module: core, then the cloud's providers and provider config
            └▶ <module>, step cloud: its role and Pod Identity association (GCP: its bindings),
               healthy once <module>-access sees them Ready
                 └▶ <module>, step workload: the chart
```

On AWS the role must exist before the pod: Pod Identity injects credentials
at admission only, so a pod admitted earlier runs without them until it is
recreated. On GCP the step `cloud` holds the module's bindings
(`ProjectIAMMember`, or `Bucket` and `BucketIAMMember`) on its own
principal, and the workload waits for them through `<module>-access`, as
on AWS.

<details>
<summary>Under the hood</summary>

A module's cloud resources are what that cloud adds to it:
`oci/clusters/<cloud>/<module>/patch.yaml` inserts a step `cloud` before the
module's `workload` step and makes the module `dependsOn` the `crossplane`
`ResourceSet`, which always exists and is Ready at once when Crossplane is
off ([SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)). The step also renders
`<module>-access`, an empty `ResourceSet` that waits on the role and the
association with an explicit `readyExpr`, because a managed resource not yet
created has no Ready condition, which the step's health check reads as
healthy; the `workload` step starts once it is Ready.

What runs before Crossplane takes its access elsewhere: Cilium's operator
from the bootstrap nodes' role; the EBS and EFS CSI drivers from roles the
bootstrap creates outside `/socle/<cluster>/`; the Pod Identity Agent is
installed before `flux-operator`.

</details>

## Per cloud

| Cloud | Crossplane providers | A module that needs access |
| --- | --- | --- |
| AWS | IAM, EKS and S3, on Pod Identity | declares its role, policy and association. Refused at plan when the role is required and Crossplane is off (`keda.services`, `velero`, `argocd_image_updater.repositories`) or the region is missing; a service missing from `allowed_services` fails at IAM, on the Role's `Synced` condition |
| GCP | Cloud Platform and Storage, on Workload Identity Federation (InjectedIdentity, no Google service account) | binds its own ServiceAccount's principal: ProjectIAMMember, or Bucket and BucketIAMMember; a role missing from gcp.crossplane.allowed_roles fails at IAM, the binding never Ready |
| Azure, Scaleway | none yet | runs without a socle-made role; you bring a credential, as its page says |

Versions and the AWS and GCP contracts: [crossplane](../catalog/crossplane.md).
