---
title: crossplane
description: "The tooling each module uses to declare its own cloud access: Crossplane and its providers (aws and gcp)."
category: platform
requires: []
---

Crossplane is the tooling a module that needs a cloud service uses to declare
its own role, beside its workload. It grants nothing by itself. **Off by
default**; turn it on when a module you want needs cloud access (external-dns,
external-secrets, keda with `services`, velero, karpenter,
argocd-image-updater with `repositories`). Providers exist on aws and gcp.

## Getting started

On aws, set the foundations' `aws.crossplane` with the services your modules
use (`crossplane = { allowed_services = ["route53", "secretsmanager"] }`); the
aws root wires `permissions_boundary` for you. On gcp, set `gcp.crossplane`
with the roles your modules' bindings grant
(`crossplane = { allowed_roles = ["roles/secretmanager.secretAccessor"] }`);
the gcp root wires `dns_records_role` for you. Then turn the module on:

```hcl kube-start="crossplane"
kube = {
  crossplane = {
    enabled = true
  }
}
```

Then `kubectl get providers.pkg.crossplane.io` shows the providers `Healthy`:
six on aws, three on gcp.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `permissions_boundary` | `""` | aws: the IAM policy every module role carries. The aws root fills it from the foundations; a value you write wins. |
| `dns_records_role` | `""` | gcp: the project custom role Crossplane grants external-dns. The gcp root fills it from the foundations; a value you write wins. |
| `values` | `{}` | Any [`crossplane` chart](https://artifacthub.io/packages/helm/crossplane/crossplane) value; yours win. |
| `values_secret` | `""` | A Secret in `crossplane-system` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="crossplane"
kube = {
  crossplane = {
    enabled = false # off by default; true installs the tooling

    # Any value of the crossplane chart 2.4.2; yours win over the socle's.
    values = {
      metrics = { enabled = true } # scrape annotations, read by otel_gateway
    }

    # A Secret you create in crossplane-system, whose values.yaml key holds
    # chart values that must not reach the OpenTofu state, such as an
    # extraEnvVarsCrossplane proxy URL with a password in it.
    values_secret = "crossplane-values"

    # On aws the root sets it to the foundations' boundary; written here, it
    # wins over the root's. Leave it out unless you mean to.
    # permissions_boundary = ""

    # On gcp the root sets it to the foundations' DNS records role, the one
    # Crossplane grants external-dns; written here, it wins over the root's.
    # dns_records_role = ""
  }
}
```

## Good to know

- **It needs `aws.crossplane` or `gcp.crossplane` in the foundations.**
  Without it the root warns: Crossplane converges, and every role or binding
  a module declares fails at the cloud's API.
- **On gcp a binding needs its role in `gcp.crossplane.allowed_roles`.**
  Crossplane may grant only those roles; any other binding stays not `Ready`
  on the IAM error, and the module's workload waits for it. Remove a role
  from the list only after the module that holds it is off: Crossplane may
  not revoke a role the list no longer names.
- **On azure and scaleway it installs the core alone.** No module declares a
  role there; each takes a credential you bring.
- **Turning it off deletes nothing it provisioned.** The CRDs, the webhook
  configuration and every module role stay, orphaned. Turn the modules that
  use it off first, wait for their roles to go, then turn Crossplane off.
- **`tofu plan` refuses secrets in `values`**: a `Secret` in `extraObjects`,
  or an `extraEnvVars*` entry named like a password, token or key. Use
  `values_secret`.
- **Upgrades**: the chart moves with `socle_version`, and its CRDs with it
  (Crossplane applies them at start). The providers move together, on
  one tag on each cloud.
- **Coming from an alpha before 0.1.0?** Once 0.1.0 is applied, strip the
  owners the old providers left on their ServiceAccount, once, or the garbage
  collector deletes it, and every provider's AWS access with it:
  `kubectl -n crossplane-system patch serviceaccount provider-aws --type json -p '[{"op":"remove","path":"/metadata/ownerReferences"}]'`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `crossplane` 2.4.2 from `https://charts.crossplane.io/stable`,
in `crossplane-system`. On aws, the providers `provider-family-aws`,
`provider-aws-iam`, `provider-aws-eks`, `provider-aws-s3`, `provider-aws-sqs`
and `provider-aws-cloudwatchevents` (v2.8.1), then
`ClusterProviderConfig/default` on EKS Pod Identity, once they are `Healthy`.
On gcp, `provider-family-gcp`, `provider-gcp-cloudplatform` and
`provider-gcp-storage` (v3.0.0), then `ClusterProviderConfig/default` on
`InjectedIdentity` for the cluster's project, once they are `Healthy`.

**What the socle sets**: requests with no limits, disk included on every
container, or GKE Autopilot reserves 1 GiB for each
([Autopilot defaults](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests#defaults)):
core 50m / 192Mi / 128Mi of disk, RBAC manager 10m / 32Mi / 64Mi, each
provider 50m / 320Mi on aws and 100m / 320Mi / 256Mi on gcp, inside
Autopilot's CPU-to-memory ratio. Every provider pod runs on one
ServiceAccount, `crossplane-system/provider-aws` or `provider-gcp`, which the
module creates itself, so the foundations can bind it before the cluster
has a node. Named through Crossplane's `serviceAccountTemplate` instead, each
provider revision would take it from the others about 25 times a second, each
write a billed line of the EKS audit log
([crossplane#7769](https://github.com/crossplane/crossplane/issues/7769)). Your `values` are merged over these.

**Cloud access**: on aws, the foundations' role for
`crossplane-system/provider-aws` creates roles only under `/socle/<cluster>/`
and only with the boundary, which allows `allowed_services` and always denies
`iam`, `sts` and the account services — but for one exception with `ec2`
allowed: passing the bootstrap nodes' role to EC2, what Karpenter launches
its nodes with ([AWS-21](../decisions/aws.md#aws-21-the-boundarys-one-iam-exception-the-node-role-passed-to-ec2)).
Beside roles, it manages buckets, SQS queues and EventBridge rules under
`<cluster>-` only, and never deletes a bucket. On gcp there is no Google service
account: the providers' own ServiceAccount is the principal,
`principal://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/<project>.svc.id.goog/subject/ns/crossplane-system/sa/provider-gcp`,
and `InjectedIdentity` makes the provider take its token from the GKE metadata
server ([Workload Identity Federation for GKE](https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)):
no key anywhere. The foundations let it grant only `allowed_roles` and the DNS
records role, through an IAM condition on `roles/resourcemanager.projectIamAdmin`
([limits on granting roles](https://cloud.google.com/iam/docs/setting-limits-on-granting-roles)),
and create buckets under `<cluster>-`, never delete one. It holds nothing of
Cloud DNS, so there is no Cloud DNS provider: external-dns gets its records
role on the project
([CROSSPLANE-05](../decisions/crossplane.md#crossplane-05-on-gcp-two-provider-families-on-the-providers-own-principal)).
The whole chain: [Module-owned cloud access](../architecture/module-iam.md).

**Ordering**: the `crossplane` ResourceSet installs the core; on aws and gcp,
its patch ([`oci/clusters/aws/crossplane/patch.yaml`](../../oci/clusters/aws/crossplane/patch.yaml),
[`oci/clusters/gcp/crossplane/patch.yaml`](../../oci/clusters/gcp/crossplane/patch.yaml),
[SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)) appends the providers and the
ProviderConfig as two more steps. Every module that declares a role waits
for `crossplane`, Ready trivially when the module is off.

**Measured** on floci 2.1.0, GitHub runner, 2026-09-30: on, providers and
ProviderConfig converged, a module role in IAM, and off again in under 4 min.
On the GKE Autopilot sandbox, 2026-10-07: core 176Mi, RBAC manager 18Mi,
165–222Mi working set per provider pod, no restart.

</details>
