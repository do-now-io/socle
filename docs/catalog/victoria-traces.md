# Catalog module `victoria_traces` — the third signal, off by default

The sixth and last module of the monitoring stack (#43, design in
[`docs/monitoring.md`](../monitoring.md)): VictoriaTraces single-node, for the
applications' traces. **It is off by default.** VictoriaTraces is still
pre-GA: its roadmap lists "finalize the data structure and commit to backward
compatibility" before GA, so an upgrade may drop stored traces
(`docs/monitoring.md` §10, question 7). A client turning it on accepts that.

Like [`victoria_logs`](victoria-logs.md), it carries its wiring into the
modules that exist, under a test on `inputs.modules.victoria_traces.enabled`:

- a traces pipeline in [`otel_gateway`](otel-gateway.md);
- a Jaeger datasource in [`grafana`](grafana.md).

Nothing in [`otel_agent`](otel-agent.md): traces come from applications, not
from nodes.

| Question | Position |
| --- | --- |
| What | The official `victoria-traces-single` chart, `oci://ghcr.io/victoriametrics/helm-charts/victoria-traces-single:0.1.11` (VictoriaTraces v0.11.0), one `HelmRelease` in namespace `victoria-traces` |
| Default | **Off** |
| Shape | `server.mode: deployment`, a standalone PVC, strategy `Recreate`: the victoria_metrics reason |
| Storage | 10Gi on the default StorageClass, `""` for an `emptyDir`; the EKS caveat of victoria_metrics applies |
| Retention | 7 days |
| Ingest | OTLP/HTTP at `/insert/opentelemetry/v1/traces` on `:10428`, protobuf only, which is what the gateway's `otlp_http` exporter sends. Applications speak to the gateway, never to this |
| Query | The Jaeger query API under `/select/jaeger` |
| Exposure | Headless `ClusterIP`, `victoria-traces.victoria-traces.svc:10428` |
| Cloud access | None |
| Client surface | `enabled`, `retention`, `storage_size`, `values`, `values_secret` |

## What is installed

When enabled, the victoria_logs objects under the `victoria-traces` names:
`Namespace`, `OCIRepository` pinned at 0.1.11, `victoria-traces-socle-values`
and `-client-values` (labelled `reconcile.fluxcd.io/watch`), and a
`HelmRelease` with no `spec.values`. The socle's values are:

- `fullnameOverride: victoria-traces` and `mode: deployment`;
- `retentionPeriod` from `retention`;
- persistence from `storage_size`;
- the `prometheus.io/*` annotations on `:10428`;
- requests of 50m / 128Mi, and an ephemeral-storage request that follows
  `storage_size`: 64Mi with a claim, **2Gi** without — the `emptyDir`
  counts against it, and GKE Autopilot makes it the limit (a pod past it is
  evicted, its data lost; on EKS it is first evicted under DiskPressure).
  Raise it in `values` to keep more.

When disabled — the default — the operator applies nothing.

## What it brings to the other modules

- **`otel_gateway`**: a `traces` pipeline, `otlp` → `k8s_attributes` →
  `memory_limiter` → `batch` → `otlp_http/victoria-traces`. The applications'
  traces get their sender's workload as the metrics and logs do.
- **`grafana`**: a read-only `VictoriaTraces` datasource, uid
  `victoria-traces`, of the **built-in Jaeger type**, at
  `…:10428/select/jaeger`. There is nothing to download.

## What the client may set — `kube.victoria_traces`

| Attribute | Default | Type | Meaning |
| --- | --- | --- | --- |
| `enabled` | `false` | bool | On deploys it and wires the gateway and Grafana; off removes all three, traces included |
| `retention` | `"7d"` | string | Whole hours, days, weeks or years, at least a day |
| `storage_size` | `"10Gi"` | string | `Gi` or `Ti`; `""` for an `emptyDir` |
| `values` | `{}` | object | Any `victoria-traces-single` value, the client's winning; the victoria_metrics secret refusals |
| `values_secret` | `""` | string | A Secret in `victoria-traces` with a `values.yaml` key, merged last |

```hcl
kube = {
  victoria_traces = { enabled = true }   # on EKS today: storage_size = "" as well
}
```

## Measured

**Render and merge, locally** (`flux-operator build rset`, `helm template`,
`victoria_traces` on and off). With it on:

- the gateway has a `traces` pipeline `otlp` → `otlp_http/victoria-traces`;
- Grafana has three datasources, VictoriaTraces as `jaeger` on
  `/select/jaeger`;
- the chart renders a `Deployment` with `--retentionPeriod=7d`, a 10Gi claim
  and a Service on 10428.

With it off, there is no `traces` pipeline, two datasources, and the operator
generates no object.

`tofu test`: 5 refusal cases and 1 positive for this module, default off
asserted.

**e2e** (floci k3s, `ubuntu-latest` runner) — run
<https://github.com/do-now-io/socle/actions/runs/36695409779>, tag
`0.0.0-feat-catalog-victoria-traces.9590ad5`, both jobs green on the first
run:

| Job | Step | Measured |
| --- | --- | --- |
| both | the default path | `resourceset/victoria-traces` Ready, no namespace, no traces exporter in the gateway |
| `e2e-aws-catalog` | turned on | Ready on a `Bound` claim after **26 s**; the gateway exports traces and Grafana provisions the Jaeger datasource |
| `e2e-aws-catalog` | one OTLP/JSON span posted by podinfo to the gateway | its trace found by id through `/select/jaeger/api/traces/<id>` after **24 s**; `/api/services` lists `socle-e2e` |
| `e2e-aws-catalog` | `kubectl top` | VictoriaTraces **2m CPU, 10Mi** with one trace |
| `e2e-aws-catalog` | turned off | HelmRelease NotFound, no traces pipeline, no Jaeger datasource |

**e2e, through Chainsaw** (`tests/e2e/chainsaw-test.yaml`, since the e2e moved
into the modules — `docs/flux-catalog.md` §8). The table above is the bash phase
this module shipped with; the same proof now runs on every push in the `root`
job (`health`) and the module's own job (`health`, then `module`): `victoria-traces-health` asserts the disabled shape and no traces pipeline in the gateway; `victoria-traces-module` turns it on (Bound claim, the gateway's `otlp_http/victoria-traces` exporter, Grafana's Jaeger datasource), posts one span through podinfo and finds it by trace id through the Jaeger API (`vt.sh`), then turns it off.

The checks live in `.github/scripts/e2e/victoria-traces.sh` (`on`, `off`).
Jobs: `e2e-aws-root` 4m34s, `e2e-aws-catalog` 16m31s. The catalog job now
carries the whole stack, Crossplane's step included.

## Open questions for the coordinator

1. **When to turn it on by default.** At VictoriaTraces GA, with a storage
   format upstream commits to. The switch is one default in `catalog.tf` and
   the e2e's default-path assertion.
2. **Sampling.** None: every span an application sends is kept. A tail- or
   probability-sampling processor is a client's `kube.otel_gateway.values`
   away. A socle default belongs with GA, and with a real application's
   volume to size it.
