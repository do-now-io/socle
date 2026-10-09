---
title: alerting decisions
description: The decisions behind the alerting module, one per section, each with its status.
sidebar:
  order: 10
---

Alerting is per cluster, off by default, and in this version evaluates the
socle's rules only; the client says where alerts go. The full design note,
with every measurement, is in the history of `docs/catalog/alerting.md`
(#59).

## ALERTING-01: vmalert and Alertmanager, one module, per cluster

**accepted** · 2026-10-07 · [`oci/catalog/alerting/resourceset.yaml`](../../oci/catalog/alerting/resourceset.yaml)

**Decision.** The `victoria-metrics-alert` chart installs one vmalert and one
Alertmanager in `alerting`. Off by default; on requires `victoria_metrics`,
a receiver and, unless `watchdog = false`, `receivers_secret`.

**Context.** Neither component is useful alone. On by default, every
cluster's plan would be refused for want of a receiver only the client knows.
Without a datasource no rule can fire, and silence would read as "all is
well". No VictoriaMetrics operator: no `VMRule`.

**Consequences.** No central Alertmanager; a client can still point vmalert
at one. No high availability: one vmalert, one Alertmanager, silences lost
with the pod unless `alertmanager.persistentVolume` is set.

**Sources.** #59 · vmalert and Alertmanager documentation at the pinned
versions.

## ALERTING-02: The socle's rules only, gathered from the socle's namespaces

**accepted** · 2026-10-07 · [`oci/catalog/alerting/resourceset.yaml`](../../oci/catalog/alerting/resourceset.yaml), [`.github/scripts/check-rules.sh`](../../.github/scripts/check-rules.sh)

**Decision.** Each module ships the rules for the metrics it produces, as
ConfigMaps labelled `vmalert_rules: "1"` under `oci/catalog/<module>/rules/`.
A `k8s-sidecar` gathers them from a fixed list of the socle's namespaces into
vmalert's rule directory. Every rule file passes `vmalert -dryRun` in CI.
Rules in `values` are refused at plan.

**Context.** vmalert reads its rule files all or nothing: measured on floci,
one bad file freezes every change while it runs and keeps it from starting
(`level=fatal`, `CrashLoopBackOff`). A client ConfigMap read from any
namespace would let one typo silence every alert.

**Consequences.** A client writes no rule in this version; application
alerts are #82. A rule made in Grafana's UI fires in Grafana only and is lost
with its pod: possible, unsupported, documented. The socle alerts on
`vmalert_config_last_reload_successful == 0`.

**Sources.** vmalert `app/vmalert/config` · awesome-prometheus-alerts,
rewritten for OpenTelemetry's names (#45, #91).

## ALERTING-03: The routing plan in OpenTofu, the keys in a Secret

**accepted** · 2026-10-07 · [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf)

**Decision.** `receivers` and `route` are named attributes, checked at plan.
Keys are files from `receivers_secret`, read through Alertmanager's `*_file`
fields; a literal key is refused. `alertmanager.config` in `values` is
refused.

**Context.** The socle prepends the watchdog's receiver and route, and Helm
replaces lists: a client's `alertmanager.config.receivers` in `values` would
drop them. The plan lands in the OpenTofu state; a Slack webhook URL is a
key.

**Consequences.** What `values_secret` holds, OpenTofu never reads: a client
rewriting Alertmanager's configuration there takes these checks off
themselves.

**Sources.** Alertmanager configuration reference, v0.34.1.

## ALERTING-04: A watchdog to a dead man's switch, on by default

**accepted** · 2026-10-07 · [`oci/catalog/alerting/rules/alerting.yaml`](../../oci/catalog/alerting/rules/alerting.yaml)

**Decision.** An always-firing `Watchdog` rule, routed to the URL in the
`watchdog-url` key of `receivers_secret`. Required unless the client writes
`watchdog = false`. The Secret is mounted without `optional`.

**Context.** The stack shares the fate of what it watches: with
VictoriaMetrics down every rule fails to evaluate and nothing fires. Only a
service outside the cluster can notice the pings stopping.

**Consequences.** A ping every 6 minutes, not 5: Alertmanager checks the
5-minute `repeat_interval` at its 1-minute `group_interval` (measured). A
silence on the Watchdog raises a false alarm. A missing Secret keeps
Alertmanager from starting rather than silently dropping the watchdog.

**Sources.** #59, measured on floci 2026-10-07.
