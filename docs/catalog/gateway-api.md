---
title: gateway-api
description: Gateway API CRDs, the cilium GatewayClass and the shared public and private Gateways.
category: networking
requires: []
---

The socle exposes services through Gateway API, never Ingress. This module
brings the standard CRDs, the `cilium` GatewayClass and the two shared
Gateways your routes attach to: `public` and `private`. **On by default**, on
aws, azure and scaleway (no Gateways on scaleway; gcp uses GKE's own).

## Getting started

It is already on; on aws the Gateways also wait for the foundations'
`aws.gateway_certificate`, on azure `https` for your `gateway-tls` Secret:

```hcl kube-start="gateway_api"
kube = {
  gateway_api = {
    gateways = true
  }
}
```

Then `kubectl -n gateway-system get gateway` lists `public` and `private`, each with its address.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. Off orphans the CRDs: your routes survive, unserved. |
| `gateways` | `true` | The two shared Gateways. `false` keeps the CRDs and the class; existing Gateways go with their load balancers. |

The module has no chart, so no `values` and no `values_secret`. The CRDs are
[Gateway API v1.6.1](https://gateway-api.sigs.k8s.io/).

### Every setting

```hcl kube-full="gateway_api"
kube = {
  gateway_api = {
    enabled  = true # on by default; false orphans the CRDs
    gateways = true # the shared public and private Gateways; false keeps the CRDs and the class
  }
}
```

## Good to know

- **Attach a route to a Gateway's `https` listener**: `parentRefs: [{ name:
  public, namespace: gateway-system, sectionName: https }]`. argocd and
  grafana attach to `private` by default; [external-dns](external-dns.md)
  publishes HTTPRoute hostnames.
- **On aws, set `aws.gateway_certificate = { domain = "acme.example" }`** in
  the foundations. They issue an ACM certificate for `domain` and
  `*.domain`, validated in its Route 53 zone; the load balancers terminate
  TLS. Port 443 only: no port 80.
- **On azure, create `gateway-system/gateway-tls`**, the certificate the
  Gateways serve. Port 80 redirects to https meanwhile.
- **Per cloud**: scaleway gets the CRDs only, since its Cilium cannot serve
  Gateway API; on gcp the module is refused at plan and GKE's Gateway API is
  used instead (`gateway_api_enabled` in the foundations).
- **Upgrades**: the CRDs move with `socle_version`, from `github.com`, which
  the cluster must reach. A CRD a release drops is removed.

<details>
<summary>Under the hood</summary>

**Installed**: no chart. Gateway API v1.6.1's `config/crd/standard`, pinned to
commit `8bb74df`, through `GitRepository/gateway-api` in `flux-system`; then
`GatewayClass/cilium`; then `Gateway/public` and `Gateway/private` in
`gateway-system` (and on azure `HTTPRoute/https-redirect`).

**What the socle sets**: once the CRDs exist, a Job restarts the Cilium
operator once per cluster, since it looks for them only at start.
The Gateways' annotations ask the cloud for a load balancer, internal for
`private`.

**Cloud access**: none. The cloud's own controller creates the load balancers.

**Ordering**: CRDs, then the class, then the Gateways. A module's route waits
for its Gateway to be `Accepted`.

**Measured** on k3s with Cilium 1.20.2, 2026-09-24: the class `Accepted` 17 s
after the operator restart, the node Ready throughout.

</details>
