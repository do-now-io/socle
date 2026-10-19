---
title: gateway-api decisions
description: The decisions behind the gateway-api module, one per section, each with its status.
sidebar:
  order: 10
---

The socle exposes services through Gateway API and ships no Ingress: CRDs from
upstream pinned by commit, and two shared Cilium Gateways, `public` and
`private`; on gcp, the same two Gateways on GKE's own classes and nothing
else (GATEWAY-API-05). GATEWAY-API-02 supersedes the exposure decisions in [aws](aws.md) and [azure](azure.md).

## GATEWAY-API-01: The CRDs from upstream, pinned by commit, and one operator restart

**accepted** · 2026-09-24 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`oci/catalog/gateway-api/cilium/operator-restart.yaml`](../../oci/catalog/gateway-api/cilium/operator-restart.yaml)

**Decision.** A Flux `GitRepository` on `kubernetes-sigs/gateway-api` pinned
to v1.6.3 (`c083613`), sparse to `config/crd/standard`, applied with
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

**accepted**, its consequence on gcp **superseded by [GATEWAY-API-05](#gateway-api-05-on-gcp-the-shared-gateways-on-gkes-classes-and-no-crd-of-the-socles)** · 2026-09-30, superseded 2026-10-16 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf)

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

## GATEWAY-API-05: On gcp, the shared Gateways on GKE's classes, and no CRD of the socle's

**accepted** · 2026-10-16 · [`oci/clusters/gcp/gateway-api/patch.yaml`](../../oci/clusters/gcp/gateway-api/patch.yaml), [`oci/clusters/gcp/kustomization.yaml`](../../oci/clusters/gcp/kustomization.yaml)

**Decision.** `gateway_api` is offered on gcp. gcp's patch removes the
module's `crds` step, behind a `test` op on its name, and appends a
`gateways` step: `public` on `inputs.gateway.className`
(`gke-l7-global-external-managed`) with the Certificate Manager map in its
`networking.gke.io/certmap` annotation, `private` on `gke-l7-rilb` with the
regional certificate in its `https` listener's `tls.options`
(`networking.gke.io/cert-manager-certs`), `http` on 80 redirected to https
on both. The child `ResourceSet` `dependsOn` GKE's two classes being
`Accepted`.

**Context.** GKE installs and upgrades the standard-channel CRDs with the
cluster ([GCP-08](gcp.md#gcp-08-exposure-through-gkes-gateway-controller))
and serves only its own classes; a Flux `Kustomization` applying upstream's
CRDs would take over objects GKE manages. A patch cannot reach inside the
`crds` step's template, so the step goes whole: a `remove` on
`/spec/steps/0`, which the `test` op turns into a build failure the day the
module's first step is anything else ([SOCLE-32](socle.md#socle-32-what-only-one-cloud-has-that-cloud-adds-to-the-module-as-steps)).
An emptied step left in place, or a catalog condition on the cloud, would
have needed `inputs.cloud` in `oci/catalog/`. Google's load balancer has a
forwarding rule and target proxy per protocol, so the redirect on 80 does not
loop as Cilium's would on aws (GATEWAY-API-02).

**Consequences.** Every module that routes through a shared Gateway does so
on gcp too. On gcp, disabling the module never touches a CRD. The module's
CRD tests are labelled `cloud: aws`; `gateway-api-health-gke` (`platform: gke`) is
gcp's proof, run by hand against the sandbox. Measured on GKE Autopilot
(2026-10-07): the redirect answers `301 https://<host>:443/`, the public
Gateway served the Google-managed certificate about 10 minutes after its
route attached. Again on 2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`): Grafana answered 200
over https about 7 minutes after its `HTTPRoute` was created, a 404 `fault
filter abort` from the load balancer before.

**Sources.** [Secure a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway) · [GatewayClass capabilities](https://cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities) · [Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways) · kustomize JSON 6902 patches (`test`, `remove`).
