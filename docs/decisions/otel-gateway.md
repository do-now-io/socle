---
title: otel-gateway decisions
description: The decisions behind the otel-gateway module, one per section, each with its status.
sidebar:
  order: 10
---

The cluster-level collector carries what applications push over OTLP, and
the Kubernetes events; it scrapes nothing
([OTEL-GATEWAY-05](#otel-gateway-05-otlp-and-events-only-its-telemetry-scraped-by-vmagent)).
The stack-wide decisions are
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

## OTEL-GATEWAY-01: Scraping by annotation, no ServiceMonitor

**superseded by [MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** In v1 the gateway scrapes every running pod annotated
`prometheus.io/scrape: "true"`, on the port, path and scheme its annotations
name. No `ServiceMonitor`, no `PodMonitor`, no target allocator.

**Context.** Reading ServiceMonitors takes two more releases, the
`prometheus-operator-crds` chart and the target allocator. Cilium falls back to
annotations while its ServiceMonitors are off, and Flux annotates its own pods.

**Consequences.** A chart that ships only a `ServiceMonitor` is not scraped
until its pods are annotated or the client adds a scrape job through `values`.
One replica scrapes every target; sharding would also need the target
allocator.

**Sources.** The `opentelemetry-collector` and `opentelemetry-target-allocator` charts; Cilium's metrics documentation; measured on floci, 2026-09-29.

## OTEL-GATEWAY-02: One replica, HA through values

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** One replica by default; a client who wants HA sets
`replicaCount` through `values`.

**Context.** Two replicas of `k8s_cluster` report every object twice unless a
leader election runs, which the chart turns on with more than one replica.

**Consequences.** 5–6m CPU and 45–50Mi measured on one node. While the pod
restarts, applications' OTLP is refused and their SDKs retry or drop it.

**Sources.** The chart's `clusterMetrics` preset and its leader election.

## OTEL-GATEWAY-03: A 1Gi memory limit, so GOMEMLIMIT applies

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** Requests 100m CPU and 128Mi, a memory limit of 1Gi.

**Context.** As for the agent
([OTEL-AGENT-01](otel-agent.md#otel-agent-01-a-memory-limit-so-gomemlimit-applies)),
`GOMEMLIMIT` follows the memory limit. This one replica carries the cluster's
object state, every scrape and every application's OTLP.

**Consequences.** The gateway refuses data before it is killed. A cluster that
outgrows 1Gi raises the limit through `values`, or runs more replicas.

**Sources.** Measured on floci, 2026-09-29: 45–50Mi on one node.

## OTEL-GATEWAY-04: What the alert rules read from k8s_cluster, and both collectors' health in one place

**superseded by [OTEL-GATEWAY-05](#otel-gateway-05-otlp-and-events-only-its-telemetry-scraped-by-vmagent)** · 2026-10-12 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml), [`oci/catalog/otel-gateway/rules/otel-gateway.yaml`](../../oci/catalog/otel-gateway/rules/otel-gateway.yaml)

**Context.** The Kubernetes rules (ALERTING-05) need what kube-state-metrics
is usually run for. `k8s_cluster` 0.160.0 has it behind switches off by
default: every node condition and allocatable type, the containers' status
reason and last termination, the pods' status reason, the claims' and
volumes' phases. Flux readiness is the Flux Operator's own
`flux_resource_info` and `flux_resourceset_info`, on a pod annotated for
scraping; the first is computed with the FluxReport, which finds Flux's CRDs
by `app.kubernetes.io/part-of`, a label the socle's common labels overwrote
until now (measured: "no Flux CRDs found", no `flux_resource_info`). Both
collectors send their own telemetry.

**Decision.** Those switches on, with `get`, `list` and `watch` on claims and
volumes, which the preset's ClusterRole lacks. The FluxInstance's common
labels leave `app.kubernetes.io/part-of` to Flux. The Kubernetes, Flux and
collector rules ship here, the collector rules once for both collectors.

**Consequences.** One collection layer, no kube-state-metrics. The opt-in
metrics are marked experimental upstream and may be renamed. With
otel_gateway off, the agent's health is not watched; the agent's CPU rule,
which reads the nodes' allocatable CPU from here, returns nothing.

**Sources.** k8sclusterreceiver 0.160.0 metadata and README; the Flux
Operator's monitoring guide; measured on floci, 2026-10-12.

## OTEL-GATEWAY-05: OTLP and events only, its telemetry scraped by vmagent

**accepted** · 2026-10-12 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml), [`oci/catalog/otel-gateway/rules/opentelemetry-collector.yaml`](../../oci/catalog/otel-gateway/rules/opentelemetry-collector.yaml)

**Context.** The monitoring module's vmagent scrapes the cluster and every
annotated pod ([MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)).
`k8s_cluster` and the gateway's own scrape would collect state the stack
already has, under names its rules do not read. awesome-prometheus-alerts'
collector rules select on `job` and `instance`, which only a Prometheus scrape
writes.

**Decision.** The gateway keeps its OTLP receivers, `k8s_attributes` and,
while monitoring's logs are on, the Kubernetes events; no `k8s_cluster`, no
`prometheus` receiver. Its pod is annotated for scraping on port 8888, as the
agent's is. Both collectors' rules ship here as a `VMRule`, in
awesome-prometheus-alerts' form with the `_total` suffix the collector's
endpoint writes, `OpentelemetryCollectorDown` included, applied once the
VMRule CRD exists. The FluxInstance still leaves `app.kubernetes.io/part-of`
to Flux, so `flux_resource_info` exists for the socle's Flux rules.

**Consequences.** With otel_gateway off, the agent's health is not watched.
One replica stays the default: two would read every Kubernetes event twice.

**Sources.** awesome-prometheus-alerts `_data/rules.yml` at 822af1e; the
`opentelemetry-collector` chart 0.173.1; measured on k3s, 2026-10-12.

## OTEL-GATEWAY-06: A disk request, on every cloud

**accepted** · 2026-10-16 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Decision.** The gateway asks 64Mi of ephemeral storage beside its 100m /
128Mi: its rotated logs and scratch. Its exporters queue in memory.

**Context.** GKE Autopilot reserves 1 GiB of disk for a container that
states none, and makes the request the limit
([MONITORING-13](monitoring.md#monitoring-13-requests-on-every-container-disk-included-on-every-cloud)).

**Consequences.** A client who adds a `file_storage` queue raises the
request in `values`.

**Sources.** [Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests).
