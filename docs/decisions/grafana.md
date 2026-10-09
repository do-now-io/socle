---
title: grafana decisions
description: The decisions behind the grafana module, one per section, each with its status.
sidebar:
  order: 10
---

Grafana reads every module's dashboards and the three Victoria backends. It
reads no Secret, and its logs plugin comes from grafana.com. Its route follows
[ARGOCD-02](argocd.md#argocd-02-the-socle-owns-the-httproute-not-the-chart).

## GRAFANA-01: A socle ClusterRole limited to ConfigMaps

**accepted** · 2026-09-30 · [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Decision.** The module renders `ClusterRole/grafana-dashboards` (`get`,
`watch`, `list` on ConfigMaps only) and sets `rbac.useExistingClusterRole` to
it; the sidecar is told `resource: configmap`.

**Context.** Dashboards are ConfigMaps loaded from every namespace by the
chart's sidecar. With a sidecar on, the chart grants read on `configmaps`
**and `secrets`** cluster-wide, and no value narrows it.

**Consequences.** Grafana reads no Secret. A dashboard in a Secret is not
supported.

**Sources.** The grafana chart 13.2.6, `templates/clusterrole.yaml` and `rbac.useExistingClusterRole`.

## GRAFANA-02: The VictoriaLogs plugin downloaded at start

**accepted** · 2026-09-30 · [`oci/catalog/grafana/resourceset.yaml`](../../oci/catalog/grafana/resourceset.yaml)

**Decision.** While victoria-logs is on, the values list
`victoriametrics-logs-datasource@0.32.0` under `plugins`; Grafana downloads it
at pod start.

**Context.** VictoriaLogs has no built-in datasource type, unlike metrics
(Prometheus) and traces (Jaeger); its plugin is distributed from grafana.com.
Baking it in would mean a socle-built image.

**Consequences.** The upstream image stays as published. Without egress to
grafana.com, Grafana has no logs datasource; metrics and traces are unaffected.

**Sources.** Grafana plugin preinstall (`GF_PLUGINS_PREINSTALL_SYNC`); the VictoriaLogs Grafana datasource 0.32.0.
