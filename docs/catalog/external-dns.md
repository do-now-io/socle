---
title: external-dns
description: Publishes DNS records for your Services, Ingresses and HTTPRoutes into your cloud's zone.
category: networking
requires: []
---

external-dns watches your Services, Ingresses and Gateway API HTTPRoutes and
writes their names into your cloud's DNS zone: Route 53, Cloud DNS, Azure
DNS or Scaleway DNS. It is **off by default**, because it needs a zone,
which has no default. On aws the client root turns it on for you when you
asked for the Gateways' certificate and gave Crossplane `route53`.

## Getting started

Turn it on with the zones it may write to. On aws, with crossplane on and
`route53` in `aws.crossplane.allowed_services`, the module brings its own
role; elsewhere, create its credential Secret ([Per cloud](#per-cloud)).

```hcl title="terraform.tfvars" kube-start="external_dns"
kube = {
  crossplane = { enabled = true } # aws: the module's own role
  external_dns = {
    enabled        = true
    domain_filters = ["acme.example"]
    policy         = "upsert-only"
  }
}
```

After the apply, `kubectl -n flux-system get resourceset external-dns` is
Ready, and a route on `shop.acme.example` gets an A record and a
`socle-` TXT record in the zone within seconds.

## What it installs

| | |
| --- | --- |
| Chart | `external-dns` `1.22.0` (external-dns 0.22.0) from `https://kubernetes-sigs.github.io/external-dns/` |
| Namespace | `external-dns`, Pod Security `restricted` enforced |
| Objects | `Namespace/external-dns`; on aws with crossplane on, `Role/external-dns` and `PodIdentityAssociation/external-dns`; the child `ResourceSet/external-dns-workload` holding `HelmRepository/external-dns`, `ConfigMap/external-dns-socle-values`, `ConfigMap/external-dns-client-values` and `HelmRelease/external-dns` |

The pod runs as `external-dns/external-dns` on every cloud: the
ServiceAccount your cloud identity binds to.

The socle's values:

| Value | Setting |
| --- | --- |
| `sources` | `service`, `ingress`, and `gateway-httproute` when `kube.gateway_api.enabled` is on: external-dns exits at start when a source's CRDs are missing |
| `registry`, `txtPrefix` | `txt`, `socle-`: each ownership record sits next to its name, not on it, since a TXT record cannot share a CNAME's name |
| `txtOwnerId` | `txt_owner_id` |
| `domainFilters`, `policy` | `domain_filters`, `policy` |
| `triggerLoopOnEvent` | `true`: a new route resolves within seconds, not at the next one-minute loop |
| Resources | 10m / 64Mi requested, 128Mi limit |
| Provider | per cloud, below |

The HelmRelease retries a failed install every two minutes
(`RetryOnFailure`): on azure and scaleway the pod cannot start until you
create its Secret, in a namespace the module creates.

## What you can set

Under `kube.external_dns` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `domain_filters` | `[]` | The zones it may write to. Required when enabled. On aws they also scope the module's role. |
| `policy` | `"upsert-only"` | `upsert-only` never deletes a record; `sync` also deletes the records it owns. |
| `txt_owner_id` | the cluster name | Written into every TXT record the module owns, so two clusters never fight over one zone. |
| `values` | `{}` | Any `external-dns` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). A list replaces the socle's: your `env` on aws replaces the `external-dns-aws` entries. |
| `values_secret` | `""` | The name of a Secret you create in `external-dns`, with a `values.yaml` key, merged last. Label it `reconcile.fluxcd.io/watch: Enabled` for a change to apply before the next interval. |

Refused at plan:

- `enabled = true` with an empty `domain_filters`: a module that publishes
  nothing.
- A `domain_filters` entry that is not a lowercase DNS name, or has a leading
  dot or a wildcard.
- `policy` other than `upsert-only` or `sync`.
- `txt_owner_id` that is not 1 to 63 letters, digits, dots, dashes or
  underscores.
- On aws with crossplane on, an empty `region` in the bootstrap module: the
  association is regional. The aws root passes `aws.region`.
- In `values`: `secretConfiguration`; an `env` or `provider.webhook.env`
  entry with a literal value whose name looks like a credential
  (`AWS_SECRET_ACCESS_KEY`, `SCW_SECRET_KEY`, `*_TOKEN`; `valueFrom` passes);
  an `extraArgs` flag such as `txt-encrypt-aes-key`.
- `values_secret` that is not a valid Secret name.

On aws the client root derives the module for you when
`aws.gateway_certificate` is set, `kube.crossplane.enabled` is on,
`aws.crossplane` is set and lists `route53`: `enabled = true`,
`domain_filters = [<gateway_certificate.domain>]`. What you write under
`kube.external_dns` wins.

**Annotations.** external-dns 0.22 reads `external-dns.kubernetes.io/hostname`
and `external-dns.kubernetes.io/target`. The older
`external-dns.alpha.kubernetes.io/` annotations most tutorials show are
ignored: no record is created from them.

### Every setting

Every attribute, at its default, and how chart values and secrets go in:

```hcl title="terraform.tfvars" kube-full="external_dns"
kube = {
  external_dns = {
    # On aws the root turns the module on, with the certificate's domain as its
    # filter, once the Gateways have a certificate: write these two only to
    # change that. Elsewhere, it is off and the filter is required to turn it on.
    # enabled        = false
    # domain_filters = []            # the zones it may write to
    policy         = "upsert-only" # "upsert-only" never deletes; "sync" deletes the records it owns
    txt_owner_id   = "acme-prod"   # default: the cluster's name

    # Any value of the external-dns chart 1.22.0; yours win over the socle's.
    values = {
      interval       = "5m"
      excludeDomains = ["internal.acme.example"]
    }

    # A Secret you create in external-dns, whose values.yaml key holds chart
    # values that must not reach the OpenTofu state, such as
    # extraArgs.txt-encrypt-aes-key.
    values_secret = "external-dns-values"
  }
}
```

## Per cloud

| Cloud | Provider | The credential |
| --- | --- | --- |
| aws | `aws` (Route 53, `AWS_REGION=us-east-1`) | With crossplane on: the module's own role, through its Pod Identity association. With crossplane off: an association you made for `external-dns/external-dns`, or the Secret `external-dns-aws` |
| gcp | `google` (Cloud DNS) | Workload Identity: DNS roles granted to the ServiceAccount's principal, or a Google service account named in `values` as `serviceAccount.annotations."iam.gke.io/gcp-service-account"`. The project comes from the metadata server |
| azure | `azure` (Azure DNS) | The Secret `external-dns-azure` with an `azure.json` key (tenant, subscription, resource group, and a service principal or `useWorkloadIdentityExtension`), mounted at `/etc/kubernetes`. For workload identity, also the `azure.workload.identity/client-id` annotation and the `azure.workload.identity/use` pod label through `values` |
| scaleway | `scaleway` (Scaleway DNS) | The Secret `external-dns-scaleway` with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`, an API key scoped to DomainsDNSFullAccess |

Create the Secret after enabling the module, since the namespace comes with
it:

```sh
kubectl -n external-dns create secret generic external-dns-azure --from-file=azure.json
kubectl -n external-dns create secret generic external-dns-scaleway \
  --from-literal=SCW_ACCESS_KEY=... --from-literal=SCW_SECRET_KEY=...
```

**The `external-dns-aws` Secret.** On aws the pod reads three optional keys
from it: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINT_URL`.
Absent, no variable is set and the SDK uses its default chain, the module's
own association included. It is how you give the pod static keys or a
Route 53-compatible endpoint. Anyone who can write Secrets in
`external-dns` can redirect external-dns, as anyone who can edit its
Deployment already can.

A zone in another GCP project or Azure subscription than the cluster's, and
Azure zones spread over several resource groups, are not supported.

## Cloud access

On aws with crossplane on, the module declares its own IAM role,
`<cluster>-external-dns` under `/socle/<cluster>/`, carrying the permissions
boundary, trusted by `pods.eks.amazonaws.com`, with one inline policy
`route53`:

- `route53:ChangeResourceRecordSets` on every hosted zone, only when every
  name in the change batch is a `domain_filters` entry or under one
  (`route53:ChangeResourceRecordSetsNormalizedRecordNames`), lowercased and
  without the trailing dot
  ([EXTERNAL-DNS-01](../decisions/external-dns.md#external-dns-01-route-53-writes-scoped-by-record-name));
- `GetHostedZone`, `ListResourceRecordSets`, `ListTagsForResource` and
  `ListTagsForResources` on `hostedzone/*`, `ListHostedZones` and
  `ListHostedZonesByName` on `*`: Route 53 has no condition key for reads,
  so the role can read every zone of the account.

The boundary must allow `route53`: `aws.crossplane.allowed_services` in the
foundations. A zone of another cluster delegated under one of your filters
(`team.acme.example` under `acme.example`) is writable by both: the TXT
registry keeps them apart, IAM does not. Narrow `domain_filters` if you need
that separation.

Elsewhere, or with crossplane off, the module declares nothing: the
credential is yours, as above.

## Ordering

The module requires nothing. It waits for crossplane: the `external-dns`
ResourceSet `dependsOn` the `crossplane` ResourceSet, Ready trivially when
crossplane is off. On aws with crossplane on, `external-dns-workload`
`dependsOn` the Role and the association being `Ready`: EKS Pod Identity
hands a pod its credentials at admission only, so the chart is applied once
the association exists. A role that never turns Ready (the boundary refuses
it, `route53` not allowed) leaves the workload unapplied and `socle-root`
not Ready, with the reason on the Role's conditions
([Module-owned cloud access](../architecture/module-iam.md)).

Turn the module off before crossplane, never in the same apply: without a
provider, the Role and the association keep their finalizers, which hold
the namespace.

## Upgrade notes

The chart is pinned to an exact version in an HTTPS Helm repository; its
pin moves with `socle_version`. 0.22 changed the annotation prefix, above:
check your workloads' annotations when you come from an external-dns of
your own.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-24 | floci, fake Route 53, the `external-dns-aws` Secret | An Ingress became an A record and an ExternalName Service a CNAME, each with a `socle-` TXT naming the owner; with `upsert-only` the A record outlived the Ingress; after `policy = "sync"`, the A record and its TXT went |
| 2026-09-24 | floci, crossplane on | The Role became IAM role `<cluster>-external-dns` under `/socle/<cluster>/`, with the trust and the condition key; a minute later the workload was still withheld, the association never syncing on floci |

Its decisions: [external-dns decisions](../decisions/external-dns.md).
