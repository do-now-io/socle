---
title: metrics-server decisions
description: The decisions behind the metrics_server module, one per section, each with its status.
sidebar:
  order: 10
---

metrics-server is the socle's on aws, where EKS installs none, and absent
elsewhere, where the cloud operates one. The full design note, with every
measurement, is in the history of `docs/catalog/metrics-server.md` (#52).

## METRICS-SERVER-01: The socle's on aws only, on by default

**accepted** · 2026-10-06 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf) (`catalog_clouds`), [`oci/clusters/aws/kustomization.yaml`](../../oci/clusters/aws/kustomization.yaml)

**Decision.** The upstream chart, in its own `metrics-server` namespace, on
by default, offered on aws only. Not the EKS add-on.

**Context.** Without it `kubectl top` fails (`Metrics API not available`)
and every HPA on CPU or memory stays blind, discovered under load. GKE and
AKS operate metrics-server, Kapsule ships one in `kube-system`; two cannot
coexist (one `APIService` per group and version, fixed cluster-wide RBAC
names). The same project on every cloud is the socle's
([AWS-02](aws.md#aws-02-vpc-cni-and-kube-proxy-refused-aws-only-add-ons-stay-eks-add-ons)).

**Consequences.** Refused at plan on gcp, azure and scaleway;
`check-catalog-clouds.sh` keeps the overlays in step.

**Sources.** GKE HPA troubleshooting · AKS support policies · Scaleway's
documentation (not verified by us).

## METRICS-SERVER-02: Kubelet certificates always checked

**accepted** · 2026-10-06 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Decision.** `--kubelet-insecure-tls` is refused at plan, in
`values.defaultArgs` and `values.args`. The API server to metrics-server leg
keeps the chart's self-signed certificate and `insecureSkipTLSVerify`.

**Context.** The socle owns the nodes: a kubelet certificate that does not
validate is the socle's to fix. Measured on EKS: they validate as they are.
For the other leg, the chart's Helm-generated certificate expires after a
year with nothing to renew it, and cert-manager is not in the catalog.

**Consequences.** `tls.*` and `apiService.*` stay free, so a client running
cert-manager can raise the check. Revisited when cert-manager joins the
catalog.

**Sources.** metrics-server 0.9.0 and its chart 3.14.0.

## METRICS-SERVER-03: One replica by default, `ha` for two

**accepted** · 2026-10-06 · [`oci/catalog/metrics-server/resourceset.yaml`](../../oci/catalog/metrics-server/resourceset.yaml)

**Decision.** One replica, `system-cluster-critical`, tolerating
`CriticalAddonsOnly`, requests without limits. `ha = true`: two replicas, a
preferred anti-affinity on the node, `maxUnavailable: 1`.

**Context.** An outage freezes HPAs and holds every namespace deletion
(measured on floci: an empty namespace `Terminating` for five minutes,
`NamespaceDeletionDiscoveryFailure`), but stops no workload. A required
anti-affinity would leave a one-node cluster unable to schedule the second
replica.

**Consequences.** About a minute of outage on a drain, up to five on a node
lost. The e2e runs the generic suite before any module's test, so a module's
namespace is never deleted while metrics-server starts. Pinning to the
bootstrap nodes is decided with Karpenter (#53).

**Sources.** Measured on floci and on a demo EKS, 2026-10-06.
