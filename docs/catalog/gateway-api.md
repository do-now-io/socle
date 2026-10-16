---
title: gateway-api
description: Gateway API CRDs, the cilium GatewayClass and the shared public and private Gateways — on GKE's own classes on gcp.
category: networking
requires: []
---

The socle exposes services through Gateway API, never Ingress. This module
brings the standard CRDs, the `cilium` GatewayClass and the two shared
Gateways your routes attach to: `public` and `private`. **On by default**, on
aws, azure, gcp and scaleway (no Gateways on scaleway; on gcp only the
Gateways, on GKE's own CRDs and classes).

## Getting started

It is already on; on aws the Gateways also wait for the foundations'
`aws.gateway_certificate`, on gcp for `gcp.gateway_certificate`, on azure
`https` for your `gateway-tls` Secret:

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
- **On gcp, set `gcp.gateway_certificate = { domains, dns_zone }`** in the
  foundations. They issue Google-managed Certificate Manager certificates,
  DNS-authorised in that Cloud DNS zone: a map for `public`, a global
  external Application Load Balancer (`gke-l7-global-external-managed`), and
  a regional certificate for `private`, a regional internal one
  (`gke-l7-rilb`) in the foundations' proxy-only subnetwork. The load
  balancers terminate TLS; port 80 redirects to https. The first HTTPS answer
  comes minutes after the Gateway: about 10 on the sandbox.
- **On gcp, a backend must answer 200 on `/`**: GKE's health check accepts
  nothing else unless a `HealthCheckPolicy` beside the route says otherwise.
- **Per cloud**: scaleway gets the CRDs only, since its Cilium cannot serve
  Gateway API; on gcp the CRDs and the classes are GKE's
  (`gateway_api_enabled` in the foundations) and the module brings only the
  Gateways.
- **Upgrades**: the CRDs move with `socle_version`, from `github.com`, which
  the cluster must reach. A CRD a release drops is removed.

<details>
<summary>Under the hood</summary>

**Installed**: no chart. Gateway API v1.6.1's `config/crd/standard`, pinned to
commit `8bb74df`, through `GitRepository/gateway-api` in `flux-system`; then
`GatewayClass/cilium`; then `Gateway/public` and `Gateway/private` in
`gateway-system` (and on azure and gcp `HTTPRoute/https-redirect`). On gcp
only the Gateways and the redirect: gcp's patch removes the CRD step,
because GKE installs and upgrades those CRDs itself.

**What the socle sets**: once the CRDs exist, a Job restarts the Cilium
operator once per cluster, since it looks for them only at start.
The Gateways' annotations ask the cloud for a load balancer, internal for
`private`. Their shape is each cloud's own, a step the cloud appends in
`oci/clusters/<cloud>/gateway-api/patch.yaml`; the CRDs and the class are
the module's, the same everywhere. Scaleway has none: without the `cilium`
class there, the socle never creates the shared Gateways. On gcp there is no
Service: GKE builds a Google load balancer from each Gateway, by its class;
`public` names its certificate map in the `networking.gke.io/certmap`
annotation and has no `tls` block, `private` names its regional certificate
in its `https` listener's `tls.options`
(`networking.gke.io/cert-manager-certs`), as
[Secure a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway)
documents. No key exists in the cluster.

**Cloud access**: none. The cloud's own controller creates the load balancers.

**Ordering**: CRDs, then the class, then the Gateways; on gcp the Gateways
wait for GKE's two classes to be `Accepted`. A module's route waits for its
Gateway to be `Accepted`. The module is Ready once the Gateways are applied,
not once their load balancers exist.

**Measured** on k3s with Cilium 1.20.2, 2026-09-24: the class `Accepted` 17 s
after the operator restart, the node Ready throughout. On GKE Autopilot,
2026-10-07: the redirect answers `301 https://<host>:443/` (the `:443` is
GKE's), and the public Gateway served the Google-managed certificate about
10 minutes after its route attached. `gateway-api-health-gke` (`platform: gke`) is
the proof, run by hand against the sandbox; port 80 and the private
Gateway's reach are checked there with `curl`. Passed again on this layout,
2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`, 40 s): Grafana's route answered 200 on
`https://grafana.<domain>/api/health` about 7 minutes after its `HTTPRoute`
was created, and `http` a 301 to https; until then the load balancer answers
404 `fault filter abort`.

</details>
