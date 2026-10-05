---
title: gateway-api decisions
description: The decisions behind the gateway-api module, one per section, each with its status.
sidebar:
  order: 10
---

The socle exposes services through Gateway API and ships no Ingress. Two
decisions shape it: the CRDs come from upstream, pinned by commit, with one
restart of Cilium's operator; and every route attaches to one of two shared
Gateways served by Cilium, `public` and `private`. GATEWAY-API-02 supersedes
the per-cloud exposure decisions in [aws decisions](aws.md) and
[azure decisions](azure.md).

## GATEWAY-API-01: The CRDs from upstream, pinned by commit, and one operator restart

**accepted** · 2026-09-24 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`oci/catalog/gateway-api/cilium/operator-restart.yaml`](../../oci/catalog/gateway-api/cilium/operator-restart.yaml)

**Context.** Every client should get Gateway API by default. On aws and azure
the socle installs Cilium before Flux, from the bootstrap module
([SOCLE-02](socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)),
with Gateway API on. Measured on Cilium 1.20.2: with no CRDs at start, the
operator is Ready, switches its Gateway controller off and never looks again
(`discoverCRDsWithRetry` retries transient errors only). Four ways to bring
the CRDs were measured:

| Option | Before Flux | Pinned | Cost |
| --- | --- | --- | --- |
| `http` data source feeding a local chart | yes | sha256 postcondition | 6.4 MB of OpenTofu state; GitHub must answer at every plan; a second provider |
| Republished into `ghcr.io` at publish time | yes | at publish | a package and a CI step; clients need registry credentials in the helm provider while it is private |
| Upstream `GitRepository` and one restart | no | commit SHA | about 150 lines of templates; clusters reach `github.com`; one operator restart per cluster |
| Vendored file | yes | digest check | 20116 lines in the repository |

**Decision.** A Flux `GitRepository` on `kubernetes-sigs/gateway-api`, pinned
to the commit of the release the pinned Cilium minor documents (v1.6.1,
`8bb74df`), sparse-checked out to `config/crd/standard`, applied by a
`Kustomization` with `deletionPolicy: Orphan`. Where the socle's Cilium
serves Gateway API, a second `Kustomization`, `gateway-api-cilium`, depends
on the CRDs, creates the `cilium` GatewayClass and runs a Job that restarts
the Cilium operator once. The Cilium chart does not create the class.

**Consequences.** Nothing vendored, and what reaches the cluster cannot
change under the socle: a commit is content-addressed. The socle's own
composition still comes only from its signed OCI artifact; this
`GitRepository` pulls a read-only third-party dependency and carries no
composition ([SOCLE-15](socle.md#socle-15-the-socles-composition-comes-from-oci-only-third-party-crds-from-a-pinned-upstream)). Clusters need egress to `github.com`. The restart Job needs a
Role with `patch` on one Deployment, flagged by Trivy and ignored in
`.trivyignore.yaml`. Disabling the module never deletes a client's Gateway.

**Sources.** Cilium 1.20 Gateway API documentation; the Cilium operator's
CRD discovery; the v1.6.1 `standard-install.yaml`, which yields the same 12
objects.

## GATEWAY-API-02: Shared public and private Gateways, on Cilium

**accepted** · 2026-09-30 · [`oci/catalog/gateway-api/resourceset.yaml`](../../oci/catalog/gateway-api/resourceset.yaml), [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf)

**Context.** Modules and clients need somewhere to attach routes. One Gateway
per route means one load balancer per route. On aws an ALB through the AWS
Load Balancer Controller, and on azure the app-routing add-on, were each
cloud's own answer, with a controller of their own. Cilium already runs on
aws and azure and implements Gateway API. On aws the foundations can issue
an ACM certificate, which only an AWS load balancer can use; Azure's load
balancer is L4 only. Cilium serves every listener of a Gateway from one
Envoy listener, and splits route tables by transport, plain or TLS, never by
port. Measured on EKS with listeners on 80 and 443 behind TLS-terminating
NLBs: `http://argocd.<domain>` served ArgoCD in clear instead of
redirecting, and `https://<unknown>.<domain>` redirected to itself.

**Decision.** Two Gateways in `gateway-system`, `public` and `private`, on
the `cilium` class, each one `LoadBalancer` Service annotated for the
cloud's own controller. Routes attach to their `https` listener on 443, from
every namespace. On aws the NLB terminates TLS with the foundations' ACM
certificate and forwards plain HTTP; there is no port 80, and the Gateways
exist only once the certificate does. On azure Envoy terminates TLS with a
Secret the client creates, and `http` on 80 redirects to https. They exist
where `inputs.gateway.shared` is true: the module and `gateways` on, the
class `cilium`, and on aws a certificate.

**Consequences.** Two load balancers per cluster, whatever the number of
routes. No private key in the cluster on aws, and ACM renews the
certificate. A plain-HTTP request on aws gets no answer instead of a
redirect. The NLB applies AWS's default TLS policy. The `public` listener
accepts routes from every namespace. Not on gcp, where GKE serves its own
classes, nor on scaleway, where no controller serves a class yet.

**Sources.** Cilium Gateway API documentation; Kubernetes in-tree AWS load
balancer annotations; the EKS measurement above.

## GATEWAY-API-03: The gateway class name is a bootstrap input, per cloud

**accepted** · 2026-09-24 · [`opentofu/bootstrap/main.tf`](../../opentofu/bootstrap/main.tf)

**Context.** A template that exposes something must name a GatewayClass. A
shared alias is not possible: GKE serves only its own GatewayClasses.

**Decision.** The bootstrap module computes `inputs.gateway.className`:
`cilium` on aws and azure when the socle's Cilium has Gateway API on,
`gke-l7-global-external-managed` on gcp, `""` on scaleway and wherever
nothing serves Gateway API. A template renders no Gateway when it is empty.

**Consequences.** Templates test one input, never the cloud. On gcp the value
assumes the foundations kept `gateway_api_enabled`, which the bootstrap
module cannot see. A regional or internal class on gcp is a template's
choice, not a second input.

**Sources.** GKE Gateway API GatewayClasses.

## GATEWAY-API-04: Envoy Gateway as the Scaleway controller

**proposed** · 2026-09-24

**Context.** Kapsule's Cilium is operated by Scaleway and cannot enable
Gateway API. The module installs the CRDs there, so the API exists, but no
class serves it, and no Gateway or route is rendered.

**Decision.** Proposed: a catalog module running Envoy Gateway,
`oci://docker.io/envoyproxy/gateway-helm` v1.9.1 with `crds.enabled=false`,
its own CRDs from upstream the same way, keyed on scaleway, setting
`inputs.gateway.className` to `envoy-gateway`.

**Consequences.** Scaleway would get the shared Gateways like aws and azure,
at the cost of a second Gateway API implementation to maintain.

**Sources.** Envoy Gateway v1.9.1 Helm chart.
