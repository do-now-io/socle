---
title: victoria-metrics decisions
description: The decisions behind the victoria-metrics module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the metrics storage. The one to know first: the
backend runs as a Deployment on a standalone claim, so `storage_size` can
change after install
([VICTORIA-METRICS-01](#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset));
victoria-logs and victoria-traces follow it. The stack-level decisions, among
them a PVC by default with `storage_size = ""` for an `emptyDir`, are in
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).
The module page is [victoria-metrics](../catalog/victoria-metrics.md).

## VICTORIA-METRICS-01: A Deployment and a standalone claim, not a StatefulSet

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Context.** The Victoria single-node charts default to a StatefulSet, whose
`volumeClaimTemplates` Helm cannot change after install: a new
`storage_size` would fail every upgrade. The charts also have a `deployment`
mode, which renders a standalone `PersistentVolumeClaim` and a `Recreate`
strategy.

**Decision.** `server.mode: deployment`, strategy `Recreate`, the claim
standalone.

**Consequences.** Growing the claim works where the StorageClass allows
expansion; shrinking is refused by the API server; `""` drops the claim. An
upgrade stops the one pod before starting the next, which an RWO volume
requires anyway.

**Sources.** `helm template` of `victoria-metrics-single` 0.48.0 in both
modes, 2026-09-29.

## VICTORIA-METRICS-02: Numeric flags as strings

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Context.** Helm reads values as JSON numbers and renders them in Go's
shortest form: `1000000` reaches the container as
`--storage.maxHourlySeries=1e+06`, which an integer flag (parsed by
`strconv.ParseInt`) refuses at start. `100000` renders as written.

**Decision.** The socle writes every numeric flag as a string
(`storage.maxHourlySeries: "100000"`), and tells the client to do the same.
The plan does not refuse a number: below a million it is right.

**Consequences.** A client who writes a large number gets a pod that does
not start, with the flag's error in its log. The rule is on the module page
and in `opentofu/clusters/aws/prod.tfvars.example`.

**Sources.** `helm template` of the pinned chart, 2026-09-29; the flag's type
in VictoriaMetrics v1.153.0.

## VICTORIA-METRICS-03: A cardinality guard of 100 000 new series an hour

**accepted** · 2026-09-29 · [`oci/catalog/victoria-metrics/resourceset.yaml`](../../oci/catalog/victoria-metrics/resourceset.yaml)

**Context.** Storage is local, not billed per sample: the risk of a label
explosion is a full disk or an exhausted memory, not a bill.
`-storage.maxHourlySeries` is open source, defined in the single-node
build's own storage (`app/vmstorage/main.go` at v1.153.0).

**Decision.** `-storage.maxHourlySeries=100000` by default, overridable
through `values`.

**Consequences.** Past the limit, new series are dropped with a log line;
existing series keep being written. A cluster that legitimately creates more
raises it.

**Sources.** VictoriaMetrics single-node flags documentation.
