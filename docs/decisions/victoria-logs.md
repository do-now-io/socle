---
title: victoria-logs decisions
description: The decisions behind the victoria-logs module, one per section, each with its status.
sidebar:
  order: 10
---

The logs storage takes the shape of victoria-metrics
([VICTORIA-METRICS-01](victoria-metrics.md#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset)).
Collecting container logs makes the node agent run as root:
[OTEL-AGENT-03](otel-agent.md#otel-agent-03-root-to-read-container-logs-with-nothing-else).

## VICTORIA-LOGS-01: Seven days, on victoria-metrics' shape

**accepted** · 2026-09-30 · [`oci/catalog/victoria-logs/resourceset.yaml`](../../oci/catalog/victoria-logs/resourceset.yaml)

**Decision.** Seven days (`retention = "7d"`) on a 20Gi claim;
`server.mode: deployment` with a standalone claim and `Recreate`. The chart's
Vector subchart stays off: OpenTelemetry collects.

**Context.** The chart defaults to one month and a StatefulSet. A reference
estate writes about 30 GiB of logs a month, about 7 GiB a week before
compression; Kubernetes events land here too.

**Consequences.** Enough for an incident, not an archive: a client who needs
longer raises `retention` and `storage_size` together.

**Sources.** The `victoria-logs-single` 0.13.9 chart values; VictoriaLogs retention documentation.
