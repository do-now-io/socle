# Catalog module `grafana` — the one place to read

The fourth module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md) §5), and the one that makes the first
three readable. It provisions a read-only datasource for each backend that is
on, and it loads every dashboard a module ships. It names no module: a
dashboard travels with the module whose metrics it reads, as a ConfigMap
labelled `grafana_dashboard`. With this PR, metrics are readable end to end:
[`victoria_metrics`](victoria-metrics.md) stores what
[`otel_agent`](otel-agent.md) and [`otel_gateway`](otel-gateway.md) collect,
and Grafana shows it on their two dashboards.

| Question | Position |
| --- | --- |
| What | The `grafana` chart from **`grafana-community`**, `oci://ghcr.io/grafana-community/helm-charts/grafana:13.2.6` (Grafana 13.2.2, the upstream distroless image), one `HelmRelease` in namespace `grafana` |
| Where | Every cloud, the same template, no cloud patch |
| Default | **On** |
| Datasources | **VictoriaMetrics** as the built-in Prometheus type, uid `victoria-metrics`, default, read-only — present only while `victoria_metrics` is on. Logs and traces add theirs in their own PRs |
| Dashboards | The dashboard sidecar, reading **ConfigMaps only**, in every namespace, labelled `grafana_dashboard: "1"`. Today: *Kubernetes / Nodes and pods* (otel_agent), *Kubernetes / Workloads* (otel_gateway) |
| RBAC | **A ClusterRole of the socle's, ConfigMaps only.** The chart's own reads every Secret of the cluster (below) |
| Identity | Local `admin`, the chart's **random password** in `Secret/grafana`; no SSO |
| Persistence | None: everything shown is provisioned |
| Exposure | `ClusterIP`, `grafana.grafana.svc:80`. The HTTPRoute is the Gateway API follow-up, as argocd's |
| Client surface | `domain`, plus `values` and `values_secret` as every module |

## What is installed

> **With `victoria_logs` on**, Grafana also provisions a read-only
> `VictoriaLogs` datasource and installs its plugin, pinned at 0.32.0 and
> downloaded from grafana.com at start: [victoria-logs.md](victoria-logs.md).

One `ResourceSet` (`oci/catalog/grafana/resourceset.yaml`), `resourcesTemplate`,
six objects, each carrying the reconcile toggle on
`inputs.modules.grafana.enabled`:

1. `Namespace/grafana`.
2. **`ClusterRole/grafana-dashboards`**: `get`, `watch` and `list` on
   `configmaps`, nothing else.
3. `OCIRepository/grafana-chart`, pinned exactly.
4. `ConfigMap/grafana-socle-values` and
5. `ConfigMap/grafana-client-values`, both labelled
   `reconcile.fluxcd.io/watch: Enabled`.
6. `HelmRelease/grafana`: no `spec.values`; `valuesFrom` = socle, client,
   then the client's Secret when named (`optional: true`).

### Why the socle brings its own ClusterRole

The chart grants its ServiceAccount `get`, `watch` and `list` on
**`configmaps` and `secrets`, cluster-wide**, as soon as any sidecar is on,
and no value narrows the rule (`templates/clusterrole.yaml`). So Grafana would
read every Secret of every client: repository keys, cloud credentials,
TLS keys. The socle sets `rbac.useExistingClusterRole: grafana-dashboards`
instead. The chart then creates no ClusterRole of its own and binds its
ServiceAccount to the socle's, which reads ConfigMaps and nothing else. The
sidecar is told `resource: configmap`, so it never asks for a Secret it may
not read. A dashboard in a Secret is not supported, deliberately.

### The socle's values

| Value | Setting | Why |
| --- | --- | --- |
| `fullnameOverride` | `grafana` | Constant names: `Deployment`, `Service`, `Secret/grafana` |
| `rbac.useExistingClusterRole` | `grafana-dashboards` | Above |
| `persistence.enabled` | `false` | Everything is provisioned; a restart loses only hand-made changes. `values` turns it on |
| `testFramework.enabled` | `false` | The chart's `helm test` pod, which Flux never runs |
| `grafana.ini.analytics` | `check_for_updates: false`, `reporting_enabled: false` | No call home from a client's cluster |
| `grafana.ini.server` | `domain`, `root_url: https://<domain>`, only when `domain` is set | Redirects and links; the HTTPRoute reads the same host later |
| `datasources` | VictoriaMetrics, under `<< if inputs.modules.victoria_metrics.enabled >>` | The Prometheus type needs no plugin download; `timeInterval: 30s`, the gateway's scrape cadence |
| `sidecar.dashboards` | on, label `grafana_dashboard` = `"1"`, `searchNamespace: ALL`, `resource: configmap` | Any module or client ships a dashboard by labelling a ConfigMap |
| `resources.requests` | 50m / 256Mi; the sidecar 10m / 64Mi | Measured on floci at about 300Mi with both dashboards loaded, the sidecar at 72Mi. No limits, as argocd |

## What the client may set — `kube.grafana`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release, the namespace and the ClusterRole |
| `domain` | `""` | string | The host Grafana is served at, e.g. `grafana.acme.example`. Validated like argocd's: empty or a lowercase FQDN, no scheme, port or path |
| `values` | `{}` | object | Any value of the chart: SSO (`grafana.ini."auth.*"`), more datasources, plugins, persistence, a second replica with a database. Merged over the socle's, the client's winning |
| `values_secret` | `""` | string | Name of a Secret in `grafana`, created by the client, with a `values.yaml` key. Merged last |

**Adding a datasource replaces the socle's.** Helm replaces lists. A client
adding his own datasource under the same file, `datasources.yaml`, writes the
list in full, VictoriaMetrics included. He can also put it under another key,
`datasources: { "client.yaml": … }`, which leaves the socle's file alone.

### Secrets refused in `values`

The plan refuses:

- `adminPassword`. The admin's password stays the chart's random one, or
  comes from `admin.existingSecret`.
- `grafana.ini` `security.admin_password` and `security.secret_key`,
  `database.password`, `smtp.password`, and an `auth.*` section's
  `client_secret`.
- A datasource's `password` or `basicAuthPassword`, and a **literal**
  `secureJsonData` value.
- An `env` entry named like a credential: the chart's `env` is always
  literal, and `envValueFrom` is the chart's way to read a Secret.
- A `Secret` among `extraObjects`.

Values Grafana resolves itself are accepted in `secureJsonData`: `$VAR` or
`${VAR}` (set through `envValueFrom`), and `$__env{…}` or `$__file{…}`.

## Reaching it

```sh
kubectl -n grafana get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n grafana port-forward svc/grafana 3000:80    # then http://localhost:3000, user admin
```

## Per cloud

Nothing. On EKS it depends on nothing the cluster lacks: no volume, no cloud
identity.

## Measured

**Render and merge, locally** (`flux-operator build rset` 0.60.0 with the
sample, `helm template` of the pinned chart):

- the chart creates **no ClusterRole**, and its `ClusterRoleBinding` points at
  `grafana-dashboards`;
- the sidecar runs with `RESOURCE=configmap`, `NAMESPACE=ALL`,
  `LABEL=grafana_dashboard` and `LABEL_VALUE=1`;
- the provisioned `datasources.yaml` holds exactly VictoriaMetrics (uid
  `victoria-metrics`, `prometheus`, default, not editable);
- `grafana.ini` has `domain` and `root_url` from the sample's
  `grafana.example.com`, with analytics off;
- the sample's client `resources.requests.memory: 160Mi` wins over the socle's request,
  and the 50m request is kept;
- the image is `grafana/grafana:13.2.2-distroless`;
- the `Service` is port 80 → `grafana`.

`tofu test`: 131 runs, 11 of them for this module: `enabled` refusing a
string, `domain` refusing a scheme and a bare label, and `values` refusing
`adminPassword`, `secret_key`, an OAuth `client_secret`, a literal datasource
secret, a credential env and a Secret among `extraObjects`; an invalid
`values_secret`; and a domain with `admin.existingSecret`, `envValueFrom`,
`${PG_PASSWORD}` and `$__file{…}` flowing through as written. Each refusal was
checked to raise its own message only.

**e2e** (floci k3s, `ubuntu-latest` runner) — run
<https://github.com/do-now-io/socle/actions/runs/36687650472>, tag
`0.0.0-feat-catalog-grafana.d3c9745`, both jobs green:

| Job | Step | Measured |
| --- | --- | --- |
| both | `resourceset/grafana` Ready and the Deployment rolled out | **1 s** after the collectors |
| both | `/api/health` | `database: ok`, version 13.2.2 |
| both | `/api/datasources` | exactly one: VictoriaMetrics, `prometheus`, `http://victoria-metrics.victoria-metrics.svc:8428`, default |
| both | the collectors' dashboards, by uid | *Kubernetes / Nodes and pods*, 11 panels; *Kubernetes / Workloads*, 15 panels |
| both | `count(k8s_pod_cpu_usage)` through Grafana's datasource proxy | **20** |
| `e2e-aws-root` | live resources, `tests/floci.tfvars` then setting 160Mi | `cpu: 50m, memory: 160Mi` — the client's value. The e2e now sets 320Mi over the socle's 256Mi |
| both | `kubectl top` | Grafana **302–308Mi**, 7–8m CPU; the sidecar 72Mi, 1m. The socle's 128Mi request was too low: raised to 256Mi after this run |
| `e2e-aws-catalog` | `victoria_metrics` disabled | the provisioning names no datasource **4 s** later, the pod rolled |
| `e2e-aws-catalog` | `victoria_metrics` re-enabled | VictoriaMetrics provisioned again 1 s after it was Ready |
| `e2e-aws-catalog` | disabled with the collectors, then re-enabled | HelmRelease and `ClusterRole/grafana-dashboards` NotFound; Ready again with its ClusterRole after **24 s** |

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e moved
into the modules — `docs/flux-catalog.md` §8). The table above is the bash phase
this module shipped with; the same proof now runs on every push in the `root`
job (`health`) and the module's own job (`health`, then `module`): `grafana-health` asserts the Deployment, the ClusterRole and the provisioning ConfigMap, then through Grafana's API (`grafana.sh`, a port-forward): exactly the datasources the socle provisions, the VictoriaLogs datasource healthy, both collectors' dashboards loaded, `k8s_pod_cpu_usage` read through the datasource proxy; `grafana-module` patches the memory request (320Mi over 256Mi), then off (release and ClusterRole gone) and on; `grafana-floci` (`platform: floci`) asserts no `grafana-route` ResourceSet without a shared Gateway.

The same run is the gateway's first green one. Its OTLP probe, from podinfo,
came back enriched with `k8s_deployment_name=podinfo`. The workloads
dashboard's twelve metrics all had series. Jobs: `e2e-aws-root` 4m06s,
`e2e-aws-catalog` 13m42s.

## Open questions for the coordinator

1. **The admin password lives in a Secret the chart generates.** Rotating it
   means deleting that Secret. SSO (`auth.generic_oauth`, its client secret
   in `values_secret`) is the follow-up, as for argocd.
2. **One replica, SQLite in an `emptyDir`.** Fine while everything is
   provisioned. A client who builds dashboards by hand wants `persistence`,
   and HA wants an external database; both are `values`.
