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

**accepted**, its context on where the shared Gateways exist **superseded by [GATEWAY-API-05](gateway-api.md#gateway-api-05-on-gcp-the-shared-gateways-on-gkes-classes-and-no-crd-of-the-socles)** · 2026-09-30, superseded 2026-10-16 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

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

## ARGOCD-03: Requests on every container, disk included, on every cloud

**accepted** · 2026-10-16 · [`oci/catalog/argocd/resourceset.yaml`](../../oci/catalog/argocd/resourceset.yaml)

**Decision.** Every container states a cpu, a memory and an
ephemeral-storage request: 64Mi of disk each, 1Gi for the repo server and
its `copyutil` init container (which takes the repo server's requests); the
`redis-secret-init` hook 50m / 64Mi / 32Mi; Redis 50m / 64Mi, not 32Mi.
With `ha`, each Redis's `sentinel` and `split-brain-fix` sidecars 10m /
32Mi / 64Mi, and the `config-init` init containers of Redis and HAProxy
10m / 32Mi / 32Mi.

**Context.** GKE Autopilot gives a container that leaves a request out 500m
CPU, 2 GiB and 1 GiB of disk, makes the disk request the limit, and wants
at most 6.5 GiB of memory a vCPU: 50m with 32Mi is under its 1 GiB a vCPU
floor. The chart leaves the hook and the Redis HA sidecars and init
containers empty. The repo server clones the client's repositories and
renders their charts under `/tmp`, and `copyutil` copies the argocd binary
into an `emptyDir`.

**Consequences.** The same requests on every cloud. On Autopilot a repo
server past 1Gi is evicted: a client with large repositories raises it in
`values`.

**Sources.** [Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests);
the argo-cd chart 10.9.2 and its redis-ha subchart's values; PR #84.
