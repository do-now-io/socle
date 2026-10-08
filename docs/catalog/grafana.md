---
title: grafana
description: One read-only Grafana with a datasource for each enabled Victoria backend and every module's dashboards.
category: observability
requires: []
---

Grafana is where you read the monitoring stack: a read-only datasource for
each Victoria backend that is on, and every dashboard a module ships. **On by
default**, on every cloud. How the stack fits together:
[Observability](../architecture/observability.md).

## Getting started

It is already on. Give it a host, on the private Gateway:

```hcl title="terraform.tfvars" kube-start="grafana"
kube = {
  grafana = {
    domain  = "grafana.acme.example"
    gateway = "private"
  }
}
```

Then `kubectl -n grafana get httproute grafana` shows your host.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. |
| `domain` | `""` | The host Grafana is served at. Empty: no URL, no route. |
| `gateway` | `"private"` | The shared Gateway the route uses: `private`, `public` or `""`. |
| `values` | `{}` | Any [`grafana` chart](https://artifacthub.io/packages/helm/grafana-community/grafana) value: SSO, datasources, plugins, persistence; yours win. |
| `values_secret` | `""` | A Secret in `grafana` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="grafana"
kube = {
  grafana = {
    enabled = true      # on by default
    domain  = ""        # "" = no root_url and no route; a host serves the UI
    gateway = "private" # the route's shared Gateway: "private", "public" or ""

    # Any value of the grafana chart 13.2.6; yours win over the socle's.
    values = {
      persistence = { enabled = true, size = "5Gi" } # keeps dashboards made by hand
    }

    # A Secret you create in grafana, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, such as
    # grafana.ini."auth.generic_oauth".client_secret.
    values_secret = "grafana-values"
  }
}
```

## Good to know

- **Log in as `admin`** with the chart's random password:
  `kubectl -n grafana get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d`.
  No SSO until you set one in `values`. Without the shared Gateways (gcp,
  scaleway): `kubectl -n grafana port-forward svc/grafana 3000:80`.
- **Ship a dashboard as a ConfigMap labelled `grafana_dashboard: "1"`**, in
  any namespace. A dashboard in a Secret is not loaded.
- **Nothing is persisted**: a restart loses dashboards made by hand. Set
  `persistence` in `values` if you build them there.
- **Add a datasource under your own key**, such as
  `datasources: { "client.yaml": ... }`: Helm replaces lists, so writing
  `datasources.yaml` replaces the socle's.
- **The VictoriaLogs plugin is downloaded from grafana.com at start.**
  Without egress there, no logs datasource.
- **`tofu plan` refuses passwords and client secrets in `values`.** Use
  `values_secret`, `admin.existingSecret` or `envValueFrom`. Upgrades: the
  chart and the plugin move with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `grafana` 13.2.6 (Grafana 13.2.2, distroless) from
`oci://ghcr.io/grafana-community/helm-charts/grafana`, in the `grafana`
namespace, with `ClusterRole/grafana-dashboards`. With a `domain`, a `gateway`
and the shared Gateways, `HTTPRoute/grafana`, which waits for its Gateway to
be `Accepted`.

**What the socle sets**: read-only datasources for VictoriaMetrics (the
default), VictoriaLogs and VictoriaTraces, each only while its backend is on;
a dashboard sidecar reading ConfigMaps only;
no persistence, no analytics; requests with no limits. Your `values` are
merged over these.

**Cloud access**: none; egress to grafana.com for the plugin.

**Measured** on floci k3s, 2026-09-30: Grafana 302–308Mi with both
collectors' dashboards; a backend turned off drops its datasource in 4 s.

</details>
