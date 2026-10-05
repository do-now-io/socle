---
title: victoria-traces decisions
description: The decisions behind the victoria-traces module, one per section, each with its status.
sidebar:
  order: 10
---

The traces storage is off by default until VictoriaTraces is GA. It takes the
shape of victoria-metrics
([VICTORIA-METRICS-01](victoria-metrics.md#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset)).

## VICTORIA-TRACES-01: Off by default until VictoriaTraces is GA

**accepted** · 2026-09-30 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `victoria_traces.enabled` defaults to `false`; a client turns it
on knowing an upgrade may drop stored traces.

**Context.** VictoriaTraces' roadmap still lists "finalize the data structure
and commit to backward compatibility" before GA: an upgrade may change the
storage format.

**Consequences.** By default the gateway has no traces pipeline and Grafana no
Jaeger datasource. Turning it on by default, at GA, is a decision of its own.

**Sources.** The VictoriaTraces roadmap, read 2026-09-28.
