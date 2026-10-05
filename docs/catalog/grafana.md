---
title: grafana
description: One read-only Grafana with a datasource for each enabled Victoria backend and every module's dashboards.
category: observability
requires: []
---

Grafana is where you read the monitoring stack: a read-only datasource for
each Victoria backend that is on, and every dashboard a module ships. It is
**on by default**, on every cloud. How the stack fits together:
[Observability](../architecture/observability.md).

## What it installs

| | |
| --- | --- |
| Chart | `grafana` `13.2.6` (Grafana 13.2.2, the distroless image) from `oci://ghcr.io/grafana-community/helm-charts/grafana` |
| Namespace | `grafana` |
| Objects | `Namespace/grafana`, `ClusterRole/grafana-dashboards`, `OCIRepository/grafana-chart`, `ConfigMap/grafana-socle-values`, `ConfigMap/grafana-client-values`, `HelmRelease/grafana`; with a `domain`, a `gateway` and the shared Gateways, the child `ResourceSet/grafana-route` holding `HTTPRoute/grafana` |

Datasources, provisioned read-only, each present only while its backend is
on:

| Datasource | uid | Type | URL |
| --- | --- | --- | --- |
| VictoriaMetrics, the default | `victoria-metrics` | built-in `prometheus`, `timeInterval: 30s` | `http://victoria-metrics.victoria-metrics.svc:8428` |
| VictoriaLogs | `victoria-logs` | the `victoriametrics-logs-datasource` plugin, pinned at 0.32.0 | `http://victoria-logs.victoria-logs.svc:9428` |
| VictoriaTraces | `victoria-traces` | built-in `jaeger` | `http://victoria-traces.victoria-traces.svc:10428/select/jaeger` |

**The VictoriaLogs plugin is downloaded from grafana.com when the pod
starts.** A cluster without egress to grafana.com gets Grafana without its
logs datasource ([GRAFANA-02](../decisions/grafana.md#grafana-02-the-victorialogs-plugin-downloaded-at-start)).

Dashboards: the sidecar loads every ConfigMap labelled
`grafana_dashboard: "1"`, in any namespace. The modules ship theirs that way,
and so can you. ConfigMaps only: a dashboard in a Secret is not loaded, and
Grafana reads no Secret of the cluster
([GRAFANA-01](../decisions/grafana.md#grafana-01-a-socle-clusterrole-limited-to-configmaps)).

The socle's values:

| Value | Setting |
| --- | --- |
| `fullnameOverride` | `grafana`: the Service is `grafana.grafana.svc:80` |
| `rbac.useExistingClusterRole` | `grafana-dashboards`: `get`, `watch`, `list` on ConfigMaps, nothing else |
| `persistence.enabled` | `false`: everything shown is provisioned; a restart loses only what was made by hand |
| `testFramework.enabled` | `false` |
| `grafana.ini.analytics` | `check_for_updates: false`, `reporting_enabled: false` |
| `grafana.ini.server` | `domain` and `root_url: https://<domain>`, when `domain` is set |
| `sidecar.dashboards` | label `grafana_dashboard` = `"1"`, `searchNamespace: ALL`, `resource: configmap` |
| `service.type` | `ClusterIP` |
| Requests | 50m / 256Mi; the sidecar 10m / 64Mi. No limits |

The admin account is local, its password the chart's random one, in
`Secret/grafana`. No SSO.

```sh
kubectl -n grafana get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n grafana port-forward svc/grafana 3000:80   # then http://localhost:3000, user admin
```

## What you can set

Under `kube.grafana` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. `false` removes the release, the namespace and the ClusterRole. |
| `domain` | `""` | The host Grafana is served at, such as `grafana.acme.example`: `root_url` and the route's hostname. Empty means no route. |
| `gateway` | `"private"` | The shared Gateway the route attaches to: `private`, `public`, or `""` for no route. |
| `values` | `{}` | Any `grafana` chart value: SSO (`grafana.ini."auth.*"`), more datasources, plugins, persistence. Yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). |
| `values_secret` | `""` | The name of a Secret you create in `grafana`, with a `values.yaml` key, merged last. OpenTofu never reads it. |

**Adding a datasource.** Helm replaces lists. A datasource under the socle's
file, `datasources.yaml`, means writing that file's list in full, the
socle's entries included. Under another key, such as
`datasources: { "client.yaml": ... }`, it leaves the socle's file alone.

Refused at plan:

- `domain` that is not empty or a lowercase FQDN: no scheme, no port, no path.
- `gateway` other than `private`, `public` or `""`.
- In `values`: `adminPassword`; `grafana.ini` `security.admin_password`,
  `security.secret_key`, `database.password`, `smtp.password`, and an
  `auth.*` section's `client_secret`; a datasource's `password` or
  `basicAuthPassword`, and a literal `secureJsonData` value; an `env` entry
  named like a credential; a `Secret` among `extraObjects`. Use instead
  `admin.existingSecret`, `envValueFrom`, a `secureJsonData` reference
  Grafana resolves itself (`$VAR`, `${VAR}`, `$__env{...}`, `$__file{...}`), or
  `values_secret`.
- `values_secret` that is not a valid Secret name.

## Per cloud

The same template on every cloud, with no overlay patch. It needs no volume
and no cloud identity. The route exists where the shared Gateways do, aws and
azure ([gateway-api](gateway-api.md)).

## Cloud access

None. Egress to grafana.com for the VictoriaLogs plugin, while
victoria-logs is on.

## Ordering

No requirement. Each datasource follows its backend's `enabled`; a backend
turned off removes its datasource and rolls the pod. The route waits for its
Gateway: `grafana-route` `dependsOn` the Gateway being `Accepted`, as
[argocd](argocd.md)'s does.

## Upgrade notes

The chart comes from `grafana-community`, pinned exactly; its pin and the
plugin's move with `socle_version`. Nothing is persisted, so an upgrade
loses only dashboards made by hand. A client who builds dashboards by hand
sets `persistence` in `values`; a second replica needs an external database.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-30 | floci k3s, GitHub `ubuntu-latest` runner, both collectors' dashboards loaded | Grafana 302–308Mi and 7–8m CPU, the sidecar 72Mi and 1m: the socle's request was raised from 128Mi to 256Mi |
| 2026-09-30 | same | `victoria_metrics` turned off: its datasource gone from the provisioning 4 s later, the pod rolled; turned back on: provisioned again 1 s after the backend was Ready. Grafana off then on: Ready again with its ClusterRole in 24 s |

Its decisions: [grafana decisions](../decisions/grafana.md).
