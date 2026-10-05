---
title: gateway-api decisions
description: The decisions behind the gateway-api module, one per section, each with its status.
sidebar:
  order: 10
---

The socle exposes services through Gateway API and ships no Ingress: CRDs from
upstream pinned by commit, and two shared Cilium Gateways, `public` and
`private`. GATEWAY-API-02 supersedes the exposure decisions in [aws](aws.md) and [azure](azure.md).

## GATEWAY-API-01: The CRDs from upstream, pinned by commit, and one operator restart

**accepted** · 2026-09-24 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`oci/catalog/gateway-api/cilium/operator-restart.yaml`](../../oci/catalog/gateway-api/cilium/operator-restart.yaml)

**Decision.** A Flux `GitRepository` on `kubernetes-sigs/gateway-api` pinned
to v1.6.1 (`8bb74df`), sparse to `config/crd/standard`, applied with
`deletionPolicy: Orphan`. Where the socle's Cilium serves Gateway API, a
second `Kustomization` creates the `cilium` GatewayClass and restarts the
Cilium operator once.

**Context.** Cilium is installed before Flux
([SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap));
measured on 1.20.2, an operator started without the CRDs switches its Gateway
controller off for good. The other options cost 6.4 MB of OpenTofu state, a
private republished package, or 20116 vendored lines.

**Consequences.** Nothing vendored, and a commit cannot change; it carries no
composition ([SOCLE-15](socle.md#socle-15-the-socles-composition-comes-from-oci-only-third-party-crds-from-a-pinned-upstream)).
Clusters need egress to `github.com`; the restart Job's `patch` Role is
ignored in `.trivyignore.yaml`. Disabling the module never deletes a Gateway.

**Sources.** Cilium 1.20 Gateway API documentation; the operator's CRD discovery; the v1.6.1 `standard-install.yaml`.

## GATEWAY-API-02: Shared public and private Gateways, on Cilium

**accepted** · 2026-09-30 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf)

**Decision.** Two Gateways in `gateway-system`, `public` and `private`, on the
`cilium` class, each one `LoadBalancer` Service; routes from every namespace
attach to `https` on 443. On aws the NLB terminates TLS with the foundations'
ACM certificate, with no port 80; on azure Envoy terminates TLS with a
client Secret and 80 redirects. Gated by `inputs.gateway.shared`.

**Context.** One Gateway per route means one load balancer per route, and the
ALB controller or app-routing add-on each brought their own controller.
Cilium serves all listeners from one Envoy listener: measured on EKS behind
TLS-terminating NLBs, port 80 served ArgoCD in clear instead of redirecting.

**Consequences.** Two load balancers per cluster; on aws no private key in the
cluster and ACM renews, but plain HTTP gets no answer. Not on gcp (GKE's own
classes) nor scaleway (no controller yet).

**Sources.** Cilium Gateway API documentation; Kubernetes in-tree AWS load balancer annotations; the EKS measurement.

## GATEWAY-API-03: The gateway class name is a bootstrap input, per cloud

**accepted** · 2026-09-24 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf)

**Decision.** The bootstrap module computes `inputs.gateway.className`:
`cilium` on aws and azure when Cilium serves Gateway API,
`gke-l7-global-external-managed` on gcp, `""` elsewhere, where templates
render no Gateway.

**Context.** A shared alias is not possible: GKE serves only its own GatewayClasses.

**Consequences.** Templates test one input, never the cloud. On gcp the value
assumes the foundations kept `gateway_api_enabled`, which the bootstrap
module cannot see.

**Sources.** GKE Gateway API GatewayClasses.

## GATEWAY-API-04: Envoy Gateway as the Scaleway controller

**proposed** · 2026-09-24

**Decision.** Proposed: a catalog module running Envoy Gateway
(`oci://docker.io/envoyproxy/gateway-helm` v1.9.1, `crds.enabled=false`),
keyed on scaleway, setting `inputs.gateway.className` to `envoy-gateway`.

**Context.** Kapsule's Cilium is operated by Scaleway and cannot enable
Gateway API: the CRDs exist there but no class serves them.

**Consequences.** Scaleway would get the shared Gateways, at the cost of a
second Gateway API implementation to maintain.

**Sources.** Envoy Gateway v1.9.1 Helm chart.
