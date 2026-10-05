---
title: argocd decisions
description: The decisions behind the argocd module, one per section, each with its status.
sidebar:
  order: 10
---

The argocd module ships the client's applications; Flux converges the socle.
It is on by default and small, and its route is the socle's object. How its
values merge is [SOCLE-06](socle.md#socle-06-the-clients-values-win).

## ARGOCD-01: On by default, non-HA

**accepted** · 2026-09-24 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

**Decision.** `kube.argocd.enabled` defaults to `true`: one replica of each
component, requests and no limits; `ha = true` turns on the chart's HA layout.
Local `admin` stays on, Dex and notifications off.

**Context.** ArgoCD is what a client gets a socle for. The chart's HA layout
adds three Redis pods with hard anti-affinity, which needs three nodes; a
socle starts on a small node group, and the e2e runs on a one-node k3s.

**Consequences.** 500m CPU and 544Mi requested in all; no limits, because a
memory limit OOM-kills the controller on a large estate. `ha` on fewer than
three nodes leaves Redis Pending, documented rather than refused. SSO is the
client's, through `values`.

**Sources.** The `argo-cd` chart 10.9.2 `values.yaml`; convergence measured on floci, on the module page.

## ARGOCD-02: The socle owns the HTTPRoute, not the chart

**accepted** · 2026-09-30 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

**Decision.** The route `argocd/argocd-server` lives in a child ResourceSet,
rendered only when `domain`, `gateway` and `inputs.gateway.shared` are set,
and `dependsOn` its Gateway being `Accepted`; it targets the `private`
Gateway by default.

**Context.** The chart's own `server.httproute` would ship with the release,
possibly before the Gateway API CRDs exist, and a failed install stalls
ArgoCD. The shared Gateways exist only on aws and azure
([GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)).

**Consequences.** A missing Gateway leaves only the route pending. The
`argocd` CLI needs `--grpc-web`: there is no `GRPCRoute`. grafana follows the
same shape.

**Sources.** The `argo-cd` chart's `server.httproute` template; flux-operator `ResourceSet` `dependsOn`.
