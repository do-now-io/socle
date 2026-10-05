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

Turn it on with the zones it may write to (on aws, crossplane brings its role):

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

## Good to know

- **The credential depends on the cloud.** aws with crossplane on: the
  module's own role (`route53` must be in `aws.crossplane.allowed_services`).
  gcp: Workload Identity, DNS roles on `external-dns/external-dns`. azure: a
  Secret `external-dns-azure` with an `azure.json` key. scaleway: a Secret
  `external-dns-scaleway` with `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`. Create
  the Secret after the first apply: the namespace comes with the module.
- **Only the `external-dns.kubernetes.io/` annotations work.** The older
  `external-dns.alpha.kubernetes.io/` ones most tutorials show are ignored.
- **`tofu plan` refuses** an empty `domain_filters` when on, malformed
  filters or owner ids, and credentials written in `values`. Use
  `values_secret` or a Secret.
- **Turn it off before crossplane**, never in the same apply: the role's
  finalizers would hold the namespace.
- **Upgrades**: the chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `external-dns` 1.22.0 (external-dns 0.22.0) from
`https://kubernetes-sigs.github.io/external-dns/`, in `external-dns` (Pod
Security `restricted`), as the ServiceAccount `external-dns/external-dns` on
every cloud. On aws with crossplane on, `Role/external-dns` and
`PodIdentityAssociation/external-dns` beside it.

**What the socle sets**: sources `service`, `ingress`, and `gateway-httproute`
when gateway-api is on; a TXT registry with the `socle-` prefix; reaction on
events, so a new route resolves within seconds; the provider of the cloud.
Your `values` are merged over these
([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)).

**Cloud access**: on aws with crossplane on, the role `<cluster>-external-dns`
may change records only when every name is under a `domain_filters` entry
([EXTERNAL-DNS-01](../decisions/external-dns.md#external-dns-01-route-53-writes-scoped-by-record-name)),
and read every zone of the account. Elsewhere, the credential is yours.

**Ordering**: waits for the `crossplane` ResourceSet; on aws the chart is
applied only once the role and its association are Ready, since Pod Identity
hands credentials at admission only.

**Measured** on floci, 2026-09-24: an Ingress became an A record with its
`socle-` TXT; with `sync`, both went when the Ingress did.

**Decisions**: [external-dns decisions](../decisions/external-dns.md).

</details>
