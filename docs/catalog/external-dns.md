---
title: external-dns
description: Publishes DNS records for your Services, Ingresses and HTTPRoutes into your cloud's zone.
category: networking
requires: []
---

external-dns writes the names of your Services, Ingresses and HTTPRoutes into
your cloud's DNS zone: Route 53, Cloud DNS, Azure DNS or Scaleway DNS. **Off by
default**, since a zone has no default; on aws the root turns it on when the
Gateways have a certificate and Crossplane may use `route53`.

## Getting started

Turn it on with the zones it may write to (on aws and gcp, crossplane brings
its access):

```hcl kube-start="external_dns"
kube = {
  crossplane = { enabled = true } # aws: the module's own role; gcp: its own IAM member
  external_dns = {
    enabled        = true
    domain_filters = ["acme.example"]
    policy         = "upsert-only"
  }
}
```

Then `kubectl -n external-dns logs deploy/external-dns` shows the records it writes.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. |
| `domain_filters` | `[]` | The zones it may write to. Required when on; on aws they also scope its role. |
| `policy` | `"upsert-only"` | `upsert-only` never deletes a record; `sync` also deletes the records it owns. |
| `txt_owner_id` | the cluster name | Marks the records it owns, so two clusters never fight over one zone. |
| `values` | `{}` | Any [`external-dns` chart](https://artifacthub.io/packages/helm/external-dns/external-dns) value; yours win. A list replaces the socle's. |
| `values_secret` | `""` | A Secret in `external-dns` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="external_dns"
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

## Good to know

- **The credential depends on the cloud.** aws with crossplane on: the
  module's own role (`route53` must be in `aws.crossplane.allowed_services`).
  gcp with crossplane on: the module's own IAM member, the foundations' DNS
  records role on the project for `external-dns/external-dns`'s Workload
  Identity principal, nothing to add to `gcp.crossplane.allowed_roles`; with
  it off, Workload Identity and DNS roles you grant that principal. azure: a
  Secret `external-dns-azure` with an `azure.json` key. scaleway: a Secret
  `external-dns-scaleway` with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`. Create
  the Secret after the first apply: the namespace comes with the module.
- **Only the `external-dns.kubernetes.io/` annotations work.** The older
  `external-dns.alpha.kubernetes.io/` ones most tutorials show are ignored.
- **`tofu plan` refuses** an empty `domain_filters` when on, malformed
  filters or owner ids, and credentials written in `values`. Use
  `values_secret` or a Secret.
- **On gcp, it writes every zone of the project it is allowed to.** The
  role is on the project, so only `domain_filters` keeps it to your names,
  in public zones only (`--google-zone-visibility=public`). One socle cluster
  per project, and each filter in a public zone of it: a name in no such zone
  is skipped, and only the log says so.
- **Turn it off before crossplane**, never in the same apply: the role's or
  the member's finalizers would hold the namespace.
- **Upgrades**: the chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `external-dns` 1.22.0 (external-dns 0.22.0) from
`https://kubernetes-sigs.github.io/external-dns/`, in `external-dns` (Pod
Security `restricted`), as the ServiceAccount `external-dns/external-dns` on
every cloud. On aws with crossplane on, `Role/external-dns` and
`PodIdentityAssociation/external-dns` beside it; on gcp with crossplane on,
`ProjectIAMMember/external-dns` (`cloudplatform.gcp.m.upbound.io/v1beta1`).
Each with crossplane on, a `ResourceSet/external-dns-access` in `flux-system`
that waits for them.

**What the socle sets**: sources `service`, `ingress`, and `gateway-httproute`
when gateway-api is on; a TXT registry with the `socle-` prefix; reaction on
events, so a new route resolves within seconds; the provider of the cloud,
and on gcp `--google-project` (the cluster's project, where the member is
bound) and `--google-zone-visibility=public` as an `extraArgs` map, so yours
merge into it. Your `values` are merged over these.

**Cloud access**: on aws with crossplane on, the role `<cluster>-external-dns`
may change records only when every name is under a `domain_filters` entry,
and read every zone of the account. On gcp with crossplane on, no Google
service account: the member grants
`inputs.modules.crossplane.dns_records_role` (the foundations'
`socleDnsRecords_<cluster>`: zones `get`/`list`, changes, record sets, no IAM)
on the project to
`principal://iam.googleapis.com/projects/<project number>/locations/global/workloadIdentityPools/<project id>.svc.id.goog/subject/ns/external-dns/sa/external-dns`.
Cloud DNS has no condition on record names and ignores zone-level IAM for
the zone's own policy, hence the project
([EXTERNAL-DNS-03](../decisions/external-dns.md#external-dns-03-cloud-dns-through-a-project-role-bounded-by-the-domain-filters)).
`tofu plan` refuses the module on gcp with crossplane on and
`dns_records_role` empty; the gcp root wires the role once
`gcp.crossplane` is set. Elsewhere, the credential is yours.

**Ordering**: the module is the same on every cloud; each cloud's patch
([`oci/clusters/<cloud>/external-dns`](../../oci/clusters/aws/external-dns/patch.yaml),
[SOCLE-32](../decisions/socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)) inserts a step with the provider and, on
aws and gcp with crossplane on, the module's access, before the chart's. On
both the module waits for `crossplane`, and the chart for the access to be
Ready: on aws since Pod Identity hands credentials at admission only, on gcp
so that a member that never turns Ready holds the module visibly rather than
leaving a pod that writes nothing.

**Measured** on floci, 2026-09-24: an Ingress became an A record with its
`socle-` TXT; with `sync`, both went when the Ingress did. On the sandbox's
GKE Autopilot, 2026-10-07, in the layout before SOCLE-32 (`external-dns-module-gke`, labels `cloud: gcp`,
`platform: gke`, run by hand: no GKE in CI, and floci-gcp serves neither
Workload Identity nor Cloud DNS): the member Ready with the role and
principal GCP reports back, and an `ExternalName` Service's name resolvable
as a CNAME from `8.8.8.8`. Passed again on this layout, 2026-10-16 (artifact
`0.0.0-feat-gcp-parity.d896756`, 97 s).

</details>
