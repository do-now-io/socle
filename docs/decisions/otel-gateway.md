---
title: otel-gateway decisions
description: The decisions behind the otel-gateway module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the cluster-level collector. The one to know first:
scraping is by `prometheus.io/*` annotation, from one replica, with no
`ServiceMonitor` support
([OTEL-GATEWAY-01](#otel-gateway-01-scraping-by-annotation-no-servicemonitor)).
The decisions that hold for the whole monitoring stack are in
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).
The module page is [otel-gateway](../catalog/otel-gateway.md).

## OTEL-GATEWAY-01: Scraping by annotation, no ServiceMonitor

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Context.** Charts from the ecosystem ship `ServiceMonitor` and `PodMonitor`
objects, and clients write them. Reading them takes the
`prometheus-operator-crds` chart plus the OpenTelemetry target allocator,
two more releases. Cilium falls back to `prometheus.io/*` annotations while
its ServiceMonitors are off, which they are in the socle; Flux annotates its
own pods.

**Decision.** In v1 the gateway scrapes every running pod annotated
`prometheus.io/scrape: "true"`, on the port, path and scheme its annotations
name, through the Prometheus receiver's pod discovery. No `ServiceMonitor`, no
`PodMonitor`, no target allocator.

**Consequences.** Two fewer releases. A chart that only ships a
`ServiceMonitor` is not scraped until its pods are annotated, or until the
client adds a scrape job through `values`. One replica scrapes every target;
the target allocator is also what would shard that when one replica is not
enough.

**Sources.** The `opentelemetry-collector` and `opentelemetry-target-allocator`
charts; Cilium's metrics documentation. Measured on floci, 2026-09-29: the
Flux controllers, both collectors, podinfo and VictoriaMetrics scraped by
annotation.

## OTEL-GATEWAY-02: One replica, HA through values

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Context.** `k8s_cluster` reports every object of the cluster; two replicas
report each one twice unless a leader election runs, which the chart turns
on with more than one replica. A restart of a single replica loses the OTLP
applications send meanwhile.

**Decision.** One replica by default. A client who wants HA sets
`replicaCount` through `values`.

**Consequences.** The default stays small: 5–6m CPU and 45–50Mi measured on
one node. While the pod restarts, applications' OTLP is refused and the
client's SDKs retry or drop it. Kubernetes events are reported once.

**Sources.** The chart's `clusterMetrics` preset and its leader election.

## OTEL-GATEWAY-03: A 1Gi memory limit, so GOMEMLIMIT applies

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Context.** As for the agent
([OTEL-AGENT-01](otel-agent.md#otel-agent-01-a-memory-limit-so-gomemlimit-applies)),
the chart derives `GOMEMLIMIT` from the memory limit and `memory_limiter` its
threshold. This one replica carries the whole cluster's object state, every
scrape and every application's OTLP.

**Decision.** Requests 100m CPU and 128Mi memory, a memory limit of 1Gi.

**Consequences.** The gateway refuses data before it is killed. A cluster
whose scrapes and OTLP outgrow 1Gi raises the limit through `values`, or runs
more replicas.

**Sources.** Measured on floci, 2026-09-29: 45–50Mi on one node.
