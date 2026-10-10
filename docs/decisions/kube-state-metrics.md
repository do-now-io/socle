---
title: kube-state-metrics decisions
description: The decisions behind the kube-state-metrics module, one per section, each with its status.
sidebar:
  order: 10
---

kube-state-metrics joins the monitoring stack so that the socle's Kubernetes
and Flux alerts are awesome-prometheus-alerts' rules as written, rather than
rules invented on OpenTelemetry's names. The collectors stay the only sender:
otel_gateway scrapes it. The stack-wide decision it amends is
[SOCLE-31](socle.md#socle-31-the-socles-dashboards-on-opentelemetry-names).

## KUBE-STATE-METRICS-01: kube-state-metrics for object state, scraped by otel_gateway

**accepted** · 2026-10-10 · [`oci/catalog/kube-state-metrics/resourceset.yaml`](../../oci/catalog/kube-state-metrics/resourceset.yaml), [`oci/catalog/otel-gateway/resourceset.yaml`](../../oci/catalog/otel-gateway/resourceset.yaml)

**Context.** #91 asks for a default alerting comparable to
kube-prometheus-stack's, on every cluster the socle runs. Its Kubernetes
rules, and awesome-prometheus-alerts', read kube-state-metrics' names. The
socle had only the `k8s_cluster` receiver's, for which nobody publishes alert
rules: Grafana's receiver-only path states "Alerts aren't supported yet",
Grafana, New Relic, Datadog and victoria-metrics-k8s-stack all keep
kube-state-metrics beside their collectors, OpenTelemetry's maintainers
decline kube-state-metrics parity (contrib #21234) and the k8s metric
semantic conventions are still in development, renames announced. The
receiver also lacks container waiting and terminated reasons, HPA and
claim phases, and Flux objects.

**Decision.** A catalog module, `kube_state_metrics`, on by default on every
cloud: kube-state-metrics, one replica, scraped by otel_gateway with a job of
its own on both ports. Not node-exporter: the node side stays on kubeletstats.

**Consequences.** The upstream Kubernetes rules apply as written, on names
that do not move. Object state is collected twice, by `k8s_cluster` for the
dashboards and by kube-state-metrics for the rules; migrating the dashboards
is not part of this. One more pod: 10m CPU and 64Mi requested. The series it
adds count against VictoriaMetrics' hourly limit. The job, not the
`prometheus.io/scrape` annotation: one annotation names one port, and the
annotation job labels every series with the scraped pod's namespace, which
here is not the object's.

**Sources.** #91; Grafana Kubernetes Monitoring documentation (OpenTelemetry
receivers); open-telemetry/opentelemetry-collector-contrib#21234; the k8s
semantic conventions migration guide; victoria-metrics-k8s-stack chart.

## KUBE-STATE-METRICS-02: Secrets not collected

**accepted** · 2026-10-10 · [`oci/catalog/kube-state-metrics/resourceset.yaml`](../../oci/catalog/kube-state-metrics/resourceset.yaml)

**Context.** The chart's default collectors include `secrets`, and its
ClusterRole then grants `list` and `watch` on every Secret of the cluster,
values included, to count them. No rule reads `kube_secret_*`.

**Decision.** `collectorsExclude: [secrets]`; the chart drops the grant with
the collector.

**Consequences.** No metric about Secrets. A client who wants them sets the
list back through `values`, and takes the grant with it.

**Sources.** kube-state-metrics chart 8.6.0, `templates/role.yaml`.

## KUBE-STATE-METRICS-03: Flux readiness through kube-state-metrics' custom resource state

**accepted** · 2026-10-10 · [`oci/catalog/kube-state-metrics/resourceset.yaml`](../../oci/catalog/kube-state-metrics/resourceset.yaml)

**Context.** awesome-prometheus-alerts' FluxCD rules read
`gotk_resource_info`, which the Flux project produces with kube-state-metrics'
custom resource state (fluxcd/flux2-monitoring-example); the controllers'
own metrics carry no readiness. Every catalog module is a Flux Operator
`ResourceSet`, which that configuration does not cover.

**Decision.** The Flux project's configuration for the kinds the socle's Flux
runs by default, without the image automation kinds, plus `ResourceSet` with
the same metric and labels; `list` and `watch` on those kinds only.

**Consequences.** The upstream FluxCD rules apply as written, and one
socle-written rule of the same shape covers a module that does not converge.
A client who adds the image automation controllers adds their kinds through
`values`.

**Sources.** fluxcd/flux2-monitoring-example, `kube-state-metrics-config.yaml`;
awesome-prometheus-alerts, FluxCD section.
