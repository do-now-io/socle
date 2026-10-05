---
title: victoria-logs decisions
description: The decisions behind the victoria-logs module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the logs storage. It takes the shape of victoria-metrics
([VICTORIA-METRICS-01](victoria-metrics.md#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset))
and the stack-level decisions of
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).
Collecting container logs makes the node agent run as root: that decision is
otel-agent's,
[OTEL-AGENT-03](otel-agent.md#otel-agent-03-root-to-read-container-logs-with-nothing-else).
The module page is [victoria-logs](../catalog/victoria-logs.md).

## VICTORIA-LOGS-01: Seven days, on victoria-metrics' shape

**accepted** · 2026-09-30 · [`oci/catalog/victoria-logs/resourceset.yaml`](../../oci/catalog/victoria-logs/resourceset.yaml)

**Context.** The `victoria-logs-single` chart defaults `retentionPeriod` to
one month, over the binary's own seven days, and to a StatefulSet. A
reference estate writes about 30 GiB of logs a month, about 7 GiB a week
before compression; Kubernetes events land here too.

**Decision.** Seven days (`retention = "7d"`) on a 20Gi claim, stated in the
socle's values; `server.mode: deployment` with a standalone claim and
`Recreate`, as victoria-metrics. The chart's Vector subchart stays off:
OpenTelemetry is the collection layer.

**Consequences.** The claim can be resized after install. Seven days of a
cluster's logs, enough for an incident, not an archive: a client who needs
longer raises `retention` and `storage_size` together.

**Sources.** The `victoria-logs-single` 0.13.9 chart values; VictoriaLogs
retention documentation.
