---
title: Module IAM
description: Why each catalog module declares its own cloud access through Crossplane, and the one grant the foundations make to allow it.
sidebar:
  order: 3
---

Some modules act on the cloud: external-dns writes DNS records, KEDA reads
queues, External Secrets reads a secret manager, Velero writes a bucket,
Karpenter launches nodes. Each
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
  role outside its path;
- with `ec2` in the list, and only then, a role may pass the bootstrap
  nodes' role to EC2 and read instance profiles: Karpenter's nodes run as
  that role, through the instance profile the foundations give it, and no
  other IAM action is allowed
  ([AWS-21](../decisions/aws.md#aws-21-the-boundarys-one-iam-exception-the-node-role-passed-to-ec2));
- beside roles, Crossplane manages a module's buckets, queues and
  EventBridge rules under `<cluster>-` only.

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
            └▶ <module>, step cloud: its ServiceAccount, role and Pod Identity association (GCP: its bindings),
               healthy once <module>-access sees them Ready and, on AWS, a pod has proven the credentials
                 └▶ <module>, step workload: the chart
```

On AWS the association must be usable before the pod exists. Pod Identity
injects the credentials at admission only, so a pod admitted earlier runs
without them until it is recreated. `Ready` is not enough: associations are
[eventually consistent](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html#pod-id-considerations).
The association is `Ready` as soon as `CreatePodIdentityAssociation`
returns, and the admission webhook learns of it seconds later. On the
sandbox, external-dns was admitted 3 s after the association turned `Ready`,
got no credentials, and logged soft errors for 21 minutes until someone ran
`rollout restart` ([#97](https://github.com/do-now-io/socle/issues/97)). So
`<module>-access` waits for proof: a Job, under the module's own
ServiceAccount, runs `aws sts get-caller-identity` with the instance metadata
off. A pod admitted too early has no credentials and fails, and the Job's next
pod is a new admission. The workload step starts once the Job is `Complete`.
The wait is exactly as long as the propagation, with no fixed delay and no
`rollout restart`.

On GCP the step `cloud` holds the module's bindings (`ProjectIAMMember`, or
`Bucket` and `BucketIAMMember`) on its own principal, and the workload waits
for them through `<module>-access`, as on AWS. There is no Job: nothing is
injected at admission. The GKE metadata server exchanges the token on each
call, so a pod that starts while a binding is still propagating
([typically 2 minutes, potentially 7 or longer](https://cloud.google.com/iam/docs/access-change-propagation))
gets refusals, then succeeds once it lands. external-dns, External Secrets,
KEDA, Velero and Argo CD Image Updater all retry on their own loop. A Job
there would hold every install for a delay that already ends on its own.

<details>
<summary>Under the hood</summary>

A module's cloud resources are what that cloud adds to it:
`oci/clusters/<cloud>/<module>/patch.yaml` inserts a step `cloud` before the
module's `workload` step and makes the module `dependsOn` the `crossplane`
`ResourceSet`, which always exists and is Ready at once when Crossplane is
off ([SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)). The step also renders
`<module>-access`, a `ResourceSet` that waits on the role and the
association with an explicit `readyExpr`, because a managed resource not yet
created has no Ready condition, which the step's health check reads as
healthy. The `workload` step starts once it is Ready.

On AWS, `<module>-access` then applies `<serviceaccount>-pod-identity`, a
Job with `wait: true`. Its one container is the AWS CLI's own image,
`public.ecr.aws/aws-cli/aws-cli` pinned by digest, and it runs one command
with no shell. It needs no permission: `GetCallerIdentity` answers even
under an explicit deny ([API_GetCallerIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_GetCallerIdentity.html)),
so the boundary's deny on `sts` leaves it whole. Each failure is a new pod,
and a Job that exhausts its six retries is recreated on the next reconcile
(`recreateOnFailure`). A completed Job stays, and runs again only when its
template changes. If `kube.kyverno_policies.allowed_registries` is set, it
must include `public.ecr.aws`. One way bypasses the injection: an optional
Secret `<module>-aws` (static keys, `AWS_ENDPOINT_URL`) that the Job reads
with `envFrom`. external-dns's workload reads the same Secret. The floci e2e
uses it, because floci's Pod Identity credentials reach AWS's own endpoints.

For the Job to run before the chart, the module's ServiceAccount on AWS is the
cloud step's, not the chart's (`serviceAccount.create: false` in
`<module>-cloud-values`). It is kept with Crossplane off too, so that turning
Crossplane on or off never moves it between owners. It carries
`helm.sh/resource-policy: keep`, so on the one upgrade that hands it over
from the chart, Helm leaves it in place (measured: same UID).

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
