---
title: victoria-metrics decisions
description: The decisions behind the victoria-metrics module, one per section, each with its status.
sidebar:
  order: 10
---

The metrics storage runs as a Deployment on a standalone claim, so
`storage_size` can change after install; victoria-logs and victoria-traces
follow it. The stack-wide decisions are [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

## VICTORIA-METRICS-01: A Deployment and a standalone claim, not a StatefulSet

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Decision.** `server.mode: deployment`, strategy `Recreate`, the claim
standalone.

**Context.** The charts default to a StatefulSet, whose
`volumeClaimTemplates` Helm cannot change: a new `storage_size` would fail
every upgrade.

**Consequences.** Growing the claim works where the StorageClass allows
expansion; shrinking is refused; `""` drops the claim. An upgrade stops the
one pod before starting the next, as an RWO volume requires anyway.

**Sources.** `helm template` of `victoria-metrics-single` 0.48.0 in both modes, 2026-09-29.

## VICTORIA-METRICS-02: Numeric flags as strings

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Decision.** The socle writes every numeric flag as a string
(`storage.maxHourlySeries: "100000"`) and tells the client to do the same; the
plan does not refuse a number.

**Context.** Helm renders `1000000` as `1e+06`, which an integer flag refuses
at start; below a million a number renders as written.

**Consequences.** A large number gives a pod that does not start, with the
flag's error in its log. The rule is on the module page and in
`opentofu/clusters/aws/prod.tfvars.example`.

**Sources.** `helm template` of the pinned chart, 2026-09-29; the flag's type in VictoriaMetrics v1.153.0.

## VICTORIA-METRICS-03: A cardinality guard of 100 000 new series an hour

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Decision.** `-storage.maxHourlySeries=100000` by default, overridable
through `values`.

**Context.** Storage is local: a label explosion means a full disk or
exhausted memory, not a bill. The flag is in the open-source single-node
build (`app/vmstorage/main.go` at v1.153.0).

**Consequences.** Past the limit, new series are dropped with a log line;
existing series keep being written.

**Sources.** VictoriaMetrics single-node flags documentation.
