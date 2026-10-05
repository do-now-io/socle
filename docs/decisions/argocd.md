---
title: argocd decisions
description: The decisions behind the argocd module, one per section, each with its status.
sidebar:
  order: 10
---

The argocd module is the second layer of the socle's GitOps: Flux converges
the socle, ArgoCD ships the client's applications. Two decisions shape it: it
is on by default and small, and its route is the socle's object rather than
the chart's. How its values merge is the socle's rule,
[SOCLE-06](socle.md#socle-06-the-clients-values-win).

## ARGOCD-01: On by default, non-HA

**accepted** · 2026-09-24 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

**Context.** ArgoCD is what a client gets a socle for: the layer he deploys
his own applications with. Every other module that is on by default either
serves the socle (gateway_api, the monitoring stack) or proves it (hello).
The chart's defaults run one replica of each component; its HA layout adds
the `redis-ha` subchart, three Redis pods with a hard anti-affinity, which
needs three nodes. A socle cluster starts on a small bootstrap node group,
and the e2e runs on a one-node k3s.

**Decision.** `kube.argocd.enabled` defaults to `true`. The default layout is
one replica of each component with requests and no limits; `ha = true` turns
on the chart's documented HA layout as one switch. Local `admin` stays on,
Dex and notifications off.

**Consequences.** Every cluster gets ArgoCD without a line of tfvars, for
500m CPU and 544Mi of memory requested in all. No limits, because a memory limit OOM-kills the controller on a large
estate. `ha` on a cluster of fewer than three nodes leaves Redis Pending; the
validation cannot know the node count, so it is documented on the module
page rather than refused. SSO is the client's, through `values`, until the
socle configures one.

**Sources.** The `argo-cd` chart 10.9.2 `values.yaml` and its HA section;
the module's convergence measured on floci, on the module page.

## ARGOCD-02: The socle owns the HTTPRoute, not the chart

**accepted** · 2026-09-30 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

**Context.** The chart can render its own `HTTPRoute`
(`server.httproute`). It would be applied with the release, possibly before
the Gateway API CRDs exist on a cold cluster; a failed install stalls the
release, and ArgoCD with it. The shared Gateways exist only on aws and azure,
and on aws only once the foundations issued their certificate
([GATEWAY-API-02](gateway-api.md#gateway-api-02-shared-public-and-private-gateways-on-cilium)).

**Decision.** The route is a socle object, `argocd/argocd-server`, in a child
ResourceSet, `argocd-route`, rendered only when `domain`, `gateway` and
`inputs.gateway.shared` are all set, and which `dependsOn` its Gateway being
`Accepted`. It attaches to the `https` listener of the Gateway
`kube.argocd.gateway` names, `private` by default, and sends `domain` to
`argocd-server:80`.

**Consequences.** The release never depends on the Gateway API; a missing
Gateway leaves only the route pending. `private` by default, because ArgoCD
is an operator's tool, not an internet service. The `argocd` CLI needs
`--grpc-web`: there is no `GRPCRoute`. grafana follows the same shape.

**Sources.** The `argo-cd` chart's `server.httproute` template; flux-operator
`ResourceSet` `dependsOn` with `readyExpr`.
