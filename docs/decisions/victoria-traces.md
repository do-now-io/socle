---
title: victoria-traces decisions
description: The decisions behind the victoria-traces module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the traces storage. The one to know: it is off by
default until VictoriaTraces is GA
([VICTORIA-TRACES-01](#victoria-traces-01-off-by-default-until-victoriatraces-is-ga)).
It takes the shape of victoria-metrics
([VICTORIA-METRICS-01](victoria-metrics.md#victoria-metrics-01-a-deployment-and-a-standalone-claim-not-a-statefulset))
and the stack-level decisions of
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).
The module page is [victoria-traces](../catalog/victoria-traces.md).

## VICTORIA-TRACES-01: Off by default until VictoriaTraces is GA

**accepted** · 2026-09-30 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Context.** VictoriaTraces' roadmap still lists "finalize the data
structure and commit to backward compatibility" before GA. Until then, an
upgrade may change the storage format and drop the traces stored so far.
Every other monitoring module is on by default.

**Decision.** `victoria_traces.enabled` defaults to `false`. A client turns it
on knowing an upgrade may drop stored traces.

**Consequences.** By default, the gateway has no traces pipeline and Grafana
no Jaeger datasource: an application's traces are not stored. Turning it on
by default, at GA, is a decision of its own.

**Sources.** The VictoriaTraces roadmap, read 2026-09-28.
