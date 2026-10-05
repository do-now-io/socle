---
title: grafana decisions
description: The decisions behind the grafana module, one per section, each with its status.
sidebar:
  order: 10
---

Grafana reads every module's dashboards and the three Victoria backends. Two
decisions bound it: it reads no Secret of the cluster, and its logs plugin
comes from grafana.com. Its route follows argocd's,
[ARGOCD-02](argocd.md#argocd-02-the-socle-owns-the-httproute-not-the-chart).

## GRAFANA-01: A socle ClusterRole limited to ConfigMaps

**accepted** · 2026-09-30 · [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Context.** Dashboards travel with the module whose metrics they read, as
ConfigMaps labelled `grafana_dashboard`, loaded by the chart's sidecar from
every namespace. As soon as any sidecar is on, the chart grants its
ServiceAccount `get`, `watch` and `list` on `configmaps` **and `secrets`**,
cluster-wide, and no value narrows the rule (`templates/clusterrole.yaml`):
Grafana would read every Secret of every client.

**Decision.** The module renders its own `ClusterRole/grafana-dashboards`,
`get`, `watch` and `list` on ConfigMaps only, and sets
`rbac.useExistingClusterRole` to it. The sidecar is told
`resource: configmap`.

**Consequences.** The chart creates no ClusterRole and binds its
ServiceAccount to the socle's. A dashboard in a Secret is not supported. The
ClusterRole goes with the module.

**Sources.** The grafana chart 13.2.6, `templates/clusterrole.yaml` and
`rbac.useExistingClusterRole`.

## GRAFANA-02: The VictoriaLogs plugin downloaded at start

**accepted** · 2026-09-30 · [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Context.** VictoriaMetrics and VictoriaTraces have built-in Grafana
datasource types: Prometheus and Jaeger. VictoriaLogs has none; its
datasource is a plugin, `victoriametrics-logs-datasource`, signed by Grafana
and distributed from grafana.com. Baking it into an image would mean a
socle-built Grafana image.

**Decision.** While victoria-logs is on, the socle's values list
`victoriametrics-logs-datasource@0.32.0` under `plugins`; Grafana downloads
it when the pod starts.

**Consequences.** The upstream image stays as published. A cluster with no
egress to grafana.com gets Grafana without its logs datasource; metrics and
traces are unaffected. The plugin's pin moves with the socle.

**Sources.** Grafana plugin preinstall (`GF_PLUGINS_PREINSTALL_SYNC`); the
VictoriaLogs Grafana datasource 0.32.0.
