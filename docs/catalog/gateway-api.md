---
title: gateway-api
description: Gateway API CRDs, the cilium GatewayClass and the shared public and private Gateways.
category: networking
requires: []
---

The socle exposes services through Gateway API, never Ingress. This module
brings the Gateway API standard CRDs, the `cilium` GatewayClass where the
socle runs Cilium, and the two Gateways that the catalog's modules and your
own routes attach to: `public`, internet-facing, and `private`, internal. It
is **on by default**, on aws, azure and scaleway.

## What it installs

| | |
| --- | --- |
| Chart | None. The CRDs come from `https://github.com/kubernetes-sigs/gateway-api`, Gateway API v1.6.1, pinned to commit `8bb74df` (branch `release-1.6`), `config/crd/standard` only |
| Namespace | `flux-system` for the Flux objects; `gateway-system` for the Gateways |
| Objects | `GitRepository/gateway-api` and `Kustomization/gateway-api-crds` (the 10 standard CRDs and the safe-upgrades `ValidatingAdmissionPolicy` with its binding); where the socle's Cilium serves Gateway API, `Kustomization/gateway-api-cilium` (`GatewayClass/cilium` and a Job that restarts the Cilium operator once); where the shared Gateways exist, the child `ResourceSet/gateway-api-gateways` (`Namespace/gateway-system`, `Gateway/public`, `Gateway/private`, and on azure `HTTPRoute/https-redirect`) |

**The one operator restart.** Cilium is installed before Flux, by the
bootstrap module, with Gateway API on and no CRDs yet
([SOCLE-02](../decisions/socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)).
Its operator checks for the CRDs once, at start, switches its Gateway
controller off, and never looks again. So once the CRDs are established,
`gateway-api-cilium` creates the class and runs
`cilium-operator-restart-for-gateway-api`, a Job in `flux-system` that runs
`kubectl rollout restart deployment/cilium-operator` under a Role limited to
`get` and `patch` on that one Deployment. The Job completes and stays, so the
operator restarts once per cluster. The restart does not touch the
datapath. The class is created here, not by the Cilium chart
(`gatewayAPI.gatewayClass.create: "false"`): the chart would render it only
when the CRD already exists, giving one object two owners
([GATEWAY-API-01](../decisions/gateway-api.md#gateway-api-01-the-crds-from-upstream-pinned-by-commit-and-one-operator-restart)).

**The shared Gateways**, in `gateway-system`:

| Gateway | Exposure | aws | azure |
| --- | --- | --- | --- |
| `public` | internet-facing | NLB in the public subnets | public Azure load balancer |
| `private` | internal to the network | internal NLB in the private subnets | internal Azure load balancer |

| Listener | aws | azure |
| --- | --- | --- |
| `https`, port 443, routes from every namespace | `HTTP`: the NLB terminates TLS with the foundations' ACM certificate for `domain` and `*.domain`, and forwards plain HTTP | `HTTPS`: Envoy terminates TLS with the Secret `gateway-system/gateway-tls`, which you create |
| `http`, port 80, routes from `gateway-system` only | none | `https-redirect` answers every request with a 301 to https |

Cilium creates one `LoadBalancer` Service per Gateway and copies
`spec.infrastructure.annotations` onto it, where the cloud's own service
controller reads them; there is no AWS Load Balancer Controller. On aws:
`aws-load-balancer-type: nlb`, cross-zone load balancing, `ssl-cert` and
`ssl-ports: "443"`, and `aws-load-balancer-internal` on `private`. On azure:
`azure-load-balancer-internal` on `private`. On azure the `https` listener is
not programmed until `gateway-tls` exists; the redirect answers meanwhile.

A route of yours attaches to a Gateway and its `https` listener:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: shop, namespace: shop }
spec:
  parentRefs:
    - { name: public, namespace: gateway-system, sectionName: https }
  hostnames: ["shop.acme.example"]
  rules:
    - backendRefs: [{ name: shop, port: 80 }]
```

[argocd](argocd.md) and [grafana](grafana.md) attach their own routes to
`private` by default, through their `gateway` attribute.
[external-dns](external-dns.md) publishes the hostnames of HTTPRoutes when
this module is on.

## What you can set

Under `kube.gateway_api` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. `false` removes the Flux objects and the Gateways, and orphans the CRDs: your routes survive, unserved. |
| `gateways` | `true` | The two shared Gateways. `false` keeps the CRDs and the class, and creates no Gateway; existing ones are deleted with their load balancers. |

The module has no chart, so no `values` and no `values_secret`. It is refused
at plan on gcp. The Gateways need an `aws.gateway_certificate` in the
foundations on aws:

```hcl
# opentofu/clusters/aws, in your tfvars
aws = {
  # ...
  gateway_certificate = { domain = "acme.example" }
  # or, for a subdomain served from its parent's zone:
  # gateway_certificate = { domain = "sbx.acme.example", zone = "acme.example" }
}
```

The foundations issue the certificate and validate it by DNS in the public
Route 53 zone of that name; ACM renews it. No private key exists in the
cluster or in the OpenTofu state.

## Per cloud

| Cloud | CRDs | GatewayClass | Shared Gateways |
| --- | --- | --- | --- |
| aws | this module | `cilium` | once the foundations issued `gateway_certificate`; HTTPS on 443 only, no port 80 ([GATEWAY-API-02](../decisions/gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)) |
| azure | this module | `cilium` | always; HTTPS on 443 with your `gateway-tls` Secret, HTTP on 80 redirecting |
| scaleway | this module | none: Kapsule's Cilium is operated by Scaleway and cannot serve Gateway API | none |
| gcp | GKE's own | GKE's `gke-l7-global-external-managed` and the other GKE classes | none; the module is not offered |

On gcp the foundations' `gateway_api_enabled` (default `true`) sets GKE's
Gateway API to the standard channel; GKE installs and upgrades the CRDs and
runs the controller. The class is also absent on aws and azure when you turn
off Cilium's Gateway API (`cilium.gateway_api = false`), and with it the
Gateways.

The bootstrap module tells every template what exists, under
`inputs.gateway`: `className` (`cilium`, the GKE class on gcp, `""` where
nothing serves Gateway API), `shared` (the two Gateways exist),
`namespace` (`gateway-system`) and `certificateArn` (aws). A module that
routes tests `shared`.

## Cloud access

None. The load balancers are created by the cloud's own controller for the
Gateways' Services.

## Ordering

No requirement. The Gateways are applied once the class exists:
`gateway-api-gateways` `dependsOn` `gateway-api-cilium`, which `dependsOn`
`gateway-api-crds`. A module's route `dependsOn` its Gateway being
`Accepted`, so a release never waits for Gateway API.

## Upgrade notes

Moving Gateway API is one commit and its version in the template, to the
release the pinned Cilium minor documents. The CRDs are applied by Flux with
`prune: true`: a CRD a new release drops from `config/crd/standard` is
removed. Turning the module off orphans them
([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off));
turning it back on adopts them. The clusters must reach `github.com`.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-24 | `config/crd/standard` at `8bb74df` against the v1.6.1 release asset | The same 12 objects as `standard-install.yaml`: 10 CRDs, the `ValidatingAdmissionPolicy` and its binding |
| 2026-09-24 | Cilium 1.20.2 in a k3s with no CNI and no kube-proxy, Gateway API on and no CRDs | The operator logged "Required GatewayAPI resources are not found" and stayed off after the CRDs arrived; `gateway-api-cilium` applied, the class `Accepted` 17 s later, the node Ready throughout |
| 2026-09-30 | EKS, both Gateways with listeners on 80 and 443 behind TLS-terminating NLBs | `http://argocd.<domain>` served ArgoCD in clear instead of redirecting, and `https://<unknown>.<domain>` redirected to itself: the reason aws has no port 80 |

Its decisions: [gateway-api decisions](../decisions/gateway-api.md).
