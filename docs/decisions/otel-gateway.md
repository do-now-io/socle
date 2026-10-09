---
title: otel-gateway decisions
description: The decisions behind the otel-gateway module, one per section, each with its status.
sidebar:
  order: 10
---

The cluster-level collector: it scrapes by annotation, from one replica, with
no `ServiceMonitor` support. The stack-wide decisions are
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

## OTEL-GATEWAY-01: Scraping by annotation, no ServiceMonitor

**accepted** · 2026-09-29 · [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

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
