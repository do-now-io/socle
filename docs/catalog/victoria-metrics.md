# Catalog module `victoria_metrics` — the metrics storage

The first module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)): VictoriaMetrics single-node, where
the OpenTelemetry collectors write every metric and Grafana reads them back. It
is a catalog module like any other, on all four clouds, and the module
contract is `docs/flux-catalog.md` §3 and §6 — argocd is the template this one
copies.

| Question | Position |
| --- | --- |
| What | The official `victoria-metrics-single` chart, `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-single:0.48.0` (VictoriaMetrics v1.153.0), one `HelmRelease` in namespace `victoria-metrics` |
| Where | Every cloud, the same template, no cloud patch |
| Default | **On**, like every monitoring module but traces |
| Shape | One pod, a `Deployment` with strategy `Recreate`, and a standalone PVC — not the chart's default StatefulSet |
| Storage | 20Gi on the cluster's default StorageClass; `storage_size = ""` for an `emptyDir`. **A socle EKS has no StorageClass today** (below) |
| Retention | 15 days |
| Ingest | OTLP over HTTP at `/opentelemetry/v1/metrics`, names converted to the Prometheus form |
| Cardinality | At most 100 000 new series an hour, then new series are dropped with a log line |
| Exposure | The chart's headless `ClusterIP` Service, `victoria-metrics.victoria-metrics.svc:8428`. No route, no auth: only in-cluster clients reach it |
| Cloud access | None — no bucket, no key, no role, so no Crossplane dependency and no foundations change |
| Client surface | `retention`, `storage_size`, plus `values`: the client's own chart values, merged over the socle's, the client winning; secrets through `values_secret`, a Secret he owns |

## What is installed

One `ResourceSet` (`oci/catalog/victoria-metrics/resourceset.yaml`),
`resourcesTemplate`, five objects, each carrying the per-resource reconcile
toggle on `inputs.modules.victoria_metrics.enabled`:

1. `Namespace/victoria-metrics`.
2. `OCIRepository/victoria-metrics-chart` in it — the chart pinned exactly,
   Helm layer copied, refreshed hourly.
3. `ConfigMap/victoria-metrics-socle-values` — the socle's own chart values,
   the table below, as a YAML document.
4. `ConfigMap/victoria-metrics-client-values` — `kube.victoria_metrics.values`
   as YAML, `{}` by default.
5. `HelmRelease/victoria-metrics` — `interval: 10m`, install and upgrade
   remediation with three retries. **No `spec.values`**: `valuesFrom` lists
   the socle's document, the client's, then the client's Secret when named
   (`optional: true`), in that order.

Both values ConfigMaps carry `reconcile.fluxcd.io/watch: Enabled`, which Flux
recommends for every `valuesFrom` reference: helm-controller upgrades the
release the moment one changes — a new `retention`, a client value — rather
than at its next `interval` (10m). The client labels his own Secret the same
way if he wants the same.

The socle's values, all in `victoria-metrics-socle-values`, and why:

| Value | Setting | Why |
| --- | --- | --- |
| `server.fullnameOverride` | `victoria-metrics` | A constant Service name: the collectors and Grafana are wired to `victoria-metrics.victoria-metrics.svc:8428`, never to a chart-derived name. A client who overrides it in `values` breaks that wiring |
| `server.mode` | `deployment` | The chart's default StatefulSet renders the claim as a `volumeClaimTemplate`, which Helm cannot change after install: a new `storage_size` would fail every upgrade. In `deployment` mode the chart renders a standalone PVC and a `Recreate` strategy, right for an RWO volume |
| `server.retentionPeriod` | `retention` | The chart defaults it to `1` (one month); the socle states it |
| `server.persistentVolume.enabled` / `.size` | `true` / `storage_size`, or `false` when `storage_size` is empty | Empty is the chart's `emptyDir` |
| `server.persistentVolume.storageClassName` | unset | The cluster's default class, the foundations' choice |
| `server.extraArgs."opentelemetry.usePrometheusNaming"` | `true` | OTLP names become Prometheus ones (dots to underscores, unit and `_total` suffixes), so a scraped Cilium or Flux metric reads as its upstream dashboards expect |
| `server.extraArgs."storage.maxHourlySeries"` | `"100000"` | The cardinality guard of `docs/monitoring.md` §3. A string on purpose (below) |
| `server.podAnnotations` | `prometheus.io/scrape: "true"`, `prometheus.io/port: "8428"` | So the `otel_gateway` module scrapes VictoriaMetrics' own metrics |
| `server.resources.requests` | cpu 50m, memory 128Mi | Measured idle on floci at 1–2m and 12Mi; the requests leave room for the collectors' ingest, measured by the next PR. No limits, as argocd. Without a limit, `-memory.allowedPercent` (60 %) is taken of the node's memory: caches may grow that far, but only as the data demands |
| `server.securityContext`, `podSecurityContext` | chart defaults (enabled) | Non-root, as the chart ships it |

## What the client may set — `kube.victoria_metrics`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `true` | bool | Off garbage-collects the release **and the namespace, claim included: the data is deleted** |
| `retention` | `"15d"` | string | How long samples are kept. Validated: a whole number of hours, days, weeks or years (`48h`, `15d`, `4w`, `1y`), and at least a day — VictoriaMetrics refuses less. Bare months and fractions are refused, though the binary takes them: nobody needs them to say how long |
| `storage_size` | `"20Gi"` | string | The claim's size, in `Gi` or `Ti`. `""` renders no claim at all: the data lives in an `emptyDir` and goes when the pod moves |
| `values` | `{}` | object | Any value of the `victoria-metrics-single` chart. Merged over the socle's values, the client's winning. No secret material (below) |
| `values_secret` | `""` | string | Name of a Secret in `victoria-metrics`, created by the client, with a `values.yaml` key. Merged last |

Kinds are enforced by the catalog-wide kind check, and each named attribute
has its own validation, so one mistake gives one diagnostic.

### Changing `storage_size`

- **Growing** works where the class allows expansion
  (`allowVolumeExpansion: true`): Helm patches the claim's request, the CSI
  driver grows the volume. Where it does not, the API server refuses the patch
  and the release fails its upgrade — the claim's size is then the first
  install's.
- **Shrinking** is refused by the API server, always.
- **To or from `""`** replaces the volume: `""` deletes the claim with the
  release's next upgrade, and setting a size again creates a new, empty one.

### Numeric flags are written as strings

Helm reads `values` as JSON numbers and renders them in Go's shortest form, so
`1000000` reaches the container as `--storage.maxHourlySeries=1e+06`, which an
integer flag (`flag.Int64`, parsed by `strconv.ParseInt`) refuses at start.
Measured with `helm template` on the pinned chart: `100000` renders as
written, `1000000` as `1e+06`; the refusal is read from the flag's type, not
run. The socle's own document writes `"100000"`, and a client writes
`"storage.maxHourlySeries" = "300000"`, not `300000`. The plan does not refuse
a number: below a million it is right, and the rule is written here and in
`prod.tfvars.example`.

### Secrets refused in `values`

`values` lands in the OpenTofu state, in the `ResourceSetInputProvider` and in
a ConfigMap. VictoriaMetrics takes its credentials as flags and, through
`envflag`, as `VM_*` environment variables, so plan refuses:

- an `server.extraArgs` flag named like a password, an auth key or a token —
  `httpAuth.password`, `deleteAuthKey`, `snapshotAuthKey`, `forceMergeAuthKey`
  and the rest of the `*AuthKey` family;
- an `server.env` entry with a literal `value` whose name looks like a
  credential (`VM_httpAuth_password`, …) — `valueFrom` a Secret is fine;
- a `Secret` among `extraObjects`.

Those go in the client's Secret, named in `values_secret`, merged last and
marked `optional` so the release does not stall before it exists.

A typical client block:

```hcl
kube = {
  victoria_metrics = {
    retention    = "30d"
    storage_size = "50Gi"
    values = {
      server = {
        extraArgs = { "storage.maxHourlySeries" = "300000" }
        resources = { requests = { memory = "1Gi" } }
      }
    }
  }
}
```

**Not configurable:** the chart version, the namespace, and — by convention,
not by refusal — `server.fullnameOverride`.

## Per cloud

The template carries no cloud patch. What differs is the default
StorageClass under the claim:

| Cloud | Default class | Consequence |
| --- | --- | --- |
| AWS | **None.** `opentofu/aws` installs no EBS CSI driver — an EKS-managed add-on left to the factory (`opentofu/aws/cluster.tf`, `docs/aws/eks-managed-scope.md`) — and EKS marks no class default since 1.30 | The claim stays `Pending`, the pod never starts, and the root `ResourceSet` does not turn Ready. **An AWS client sets `storage_size = ""`** until the driver exists; `opentofu/clusters/aws/prod.tfvars.example` does. A foundations/factory gap, tracked on its own |
| GCP | `standard-rwo` (Persistent Disk CSI, managed by GKE) | To confirm when a GCP e2e exists |
| Azure | `managed-csi` (Azure Disk CSI, managed by AKS) | Same |
| Scaleway | `scw-bssd` (Block Storage CSI, managed by Kapsule) | Same |

Choosing a per-cloud default in the template — `""` on aws — was considered
and refused: it would hide the gap rather than close it, and flip silently the
day the driver lands.

## Templating notes

- The socle's document keeps its `<< if >>` block over the persistence keys
  inside the block scalar, as argocd does; the operator templates the text
  before YAML parses it. The empty lines it leaves make the operator emit the
  document as a quoted string rather than a block — cosmetic, and the same in
  argocd's.
- `<< if inputs.modules.victoria_metrics.storage_size >>`: an empty string is
  false in the operator's templates, so "set" and "non-empty" are one test.
- No template delimiters in the comments inside `resourcesTemplate`: the
  operator templates comments too (the trap argocd's note measured).

## Measured

**Render** (`flux-operator build rset` 0.60.0 with `oci/.ci/inputs-sample.yaml`):

| Inputs | Result |
| --- | --- |
| sample: `storage_size: 20Gi`, a client `storage.maxHourlySeries: "50000"`, `values_secret` set | 5 objects; the HelmRelease has no `spec.values` and `valuesFrom` = socle, client, Secret |
| `storage_size: ""`, `values_secret: ""` | the socle document has `persistentVolume.enabled: false`; `valuesFrom` = socle, client only |
| `enabled: false` | no objects generated (the CLI omits disabled resources; on/off is proven on the cluster) |

**Merge, locally** — `helm template` of the pinned chart with the rendered
socle document, then the rendered client document:

- with the sample: a `PersistentVolumeClaim` of `20Gi`, a `Deployment` with
  strategy `Recreate` mounting it, and the args `--opentelemetry.usePrometheusNaming`,
  `--retentionPeriod=15d`, `--storage.maxHourlySeries=50000` — the client's
  value over the socle's `100000`, the socle's sibling flag and the chart's
  own (`--envflag.enable`, `--loggerFormat=json`) intact;
- with `storage_size: ""`: no claim, an `emptyDir` volume;
- with a client `1000000` as a number: `--storage.maxHourlySeries=1e+06`.

**Flags, upstream** — at v1.153.0, `-storage.maxHourlySeries` is defined in
`app/vmstorage/main.go`, the single-node build's own storage: open source, not
enterprise. `-opentelemetry.usePrometheusNaming` and the
`/opentelemetry/v1/metrics` path are documented in the OpenTelemetry
integration guide.

`tofu test` in `opentofu/bootstrap`: 105 runs, 15 of them for this module —
`enabled` refusing a string, `retention` refusing a number, `15days`, `12h`
and `0d`, `storage_size` refusing a number and `20GB`, `values` refusing a
string, an `httpAuth.password` flag, a `deleteAuthKey` flag, a literal
`VM_httpAuth_password` and a Secret among `extraObjects`, `values_secret`
refusing an invalid name; defaults asserted; `""` with `48h`, and `1Ti` with
`values` carrying a credential through `valueFrom`, flowing through as
written. Each refusal was checked to raise its own message and only that one.

**e2e** (floci k3s, `ubuntu-latest` runner, `publish-artifact.yaml`) — run
<https://github.com/do-now-io/socle/actions/runs/36575864306>, tag
`0.0.0-feat-catalog-victoria-metrics.6484a76`, both jobs green on the first
run. `wait-converged.sh` reads `EXPECT_VICTORIA_METRICS`:

| Job | Step | Measured |
| --- | --- | --- |
| `e2e-aws-root` | real root applied, then `resourceset/victoria-metrics` Ready and the Deployment Available | **1 s** after argocd's 51 s — its one image pulled meanwhile |
| both | the claim | `Bound`, `local-path`, `20Gi` |
| both | a sample written through `/api/v1/import`, read back through `/api/v1/query` via the API server's service proxy | `socle_e2e_probe=42` |
| `e2e-aws-root` | live args, `tests/floci.tfvars` overriding the socle's value | `--storage.maxHourlySeries=50000`, with `--opentelemetry.usePrometheusNaming`, `--retentionPeriod=15d` and the chart's `--envflag.*`, `--loggerFormat=json` intact |
| `e2e-aws-catalog` | live args, no client value | `--storage.maxHourlySeries=100000`, the socle's own |
| both | idle, `kubectl top` | **1–2m CPU, 12Mi** — the requests were lowered to 50m/128Mi from it |
| `e2e-aws-catalog` | disabled with hello and argocd | HelmRelease NotFound within the 10 s step |
| `e2e-aws-catalog` | re-enabled | Ready again with a **new** claim `Bound` **20 s** after hello |

Job totals: `e2e-aws-root` 2m46s, `e2e-aws-catalog` 12m43s — of which
Crossplane's step is 5m06s and external-dns' four 2m54s; this module's own
steps add about half a minute.

**What floci cannot prove:** a cloud StorageClass, volume expansion, and the
EKS gap itself — floci's k3s brings its own class.

## Open questions for the coordinator

1. **The EKS StorageClass gap.** Every stateful module the socle ships from
   now on inherits it. The fix is the EBS CSI driver on the cluster, which
   the AWS documents leave to "the factory" — a layer that does not exist
   yet. Until it does, is the driver a catalog module (its role through
   Crossplane, like external-dns), or a foundations add-on after all?
2. **Renovate does not see the chart pin**, the same open point as argocd's:
   `spec.ref.tag` sits in a string.
3. **Memory on the e2e runner.** This module is 12Mi idle, nothing to
   budget. The figure that matters is under ingest, once the collectors
   write to it; if the stack's six modules together crowd the runner, the
   monitoring note's §7 rule applies — a module that cannot converge on floci
   is covered by `e2e-aws-catalog` only, with the reason written down.
