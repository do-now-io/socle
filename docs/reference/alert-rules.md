---
title: Alert rules
description: Every alert rule group the socle loads, where each comes from, its alert count, and the upstream groups it turns off, with the reason.
sidebar:
  order: 6
---

With [monitoring](../catalog/monitoring.md)'s alerting on, vmalert loads
every `VMRule` in the cluster: nothing to write, nothing to turn on one by
one. Most come from upstream, the rules kube-prometheus-stack installs and
VictoriaMetrics' for the stack itself, downloaded by the chart's sync job at
the tags the socle pins; a few are the socle's, for what upstream does not
cover. Measured on k3s, 2026-10-12: 211 rules loaded and healthy, 158 of them
alerting, with logs on; 209 since the chart 0.96.0, which drops the two
`kube-prometheus-general.rules`.

**Severity** is upstream's. `info` goes to the socle's `null` receiver, and a
`critical` alert holds back the `warning` of the same name and namespace.
Route `severity="critical"` to your on-call. A noisy alert is muted with a
route of yours to `null`.

## From kube-prometheus

[kube-prometheus](https://github.com/prometheus-operator/kube-prometheus)
v0.19.0, the source of kube-prometheus-stack's rules, on what vmagent scrapes:
kube-state-metrics, node-exporter, the kubelets and cAdvisor.

| Group | Alerts | Watches |
| --- | --- | --- |
| `kubernetes-apps` | 17 | pods crash-looping or not ready, Deployments, StatefulSets, DaemonSets and Jobs short of what they want, HPAs maxed out |
| `kubernetes-resources` | 8 | CPU and memory overcommitted, quotas nearly or fully used, CPU throttling |
| `kubernetes-storage` | 5 | PersistentVolumes filling up or out of inodes, in error |
| `kubernetes-system` | 2 | version mismatch, client errors |
| `kubernetes-system-kubelet` | 16 | nodes not ready or unreachable, too many pods, evictions, kubelet down, PLEG and pod start latency, certificates |
| `node-exporter` | 26 | filesystems filling, out of inodes, network errors, clock skew, memory and CPU saturation, read-only filesystems |
| `node-network` | 1 | a network interface flapping |
| `kube-state-metrics` | 4 | kube-state-metrics' own list and watch errors, shards |
| `alertmanager.rules` | 9 | Alertmanager failing to reload or to send |
| `general.rules` | 2 | `Watchdog`, `InfoInhibitor`; its `TargetDown` is replaced by the socle's |

Recording rules feed them and Grafana's dashboards: `k8s.rules.*`,
`node-exporter.rules`, `node.rules`, `kubelet.rules`,
`kube-prometheus-node-recording.rules`. The chart turns
`kube-prometheus-general.rules` (`count:up1`, `count:up0`) off since 0.96.0;
no dashboard reads them.

## From VictoriaMetrics

VictoriaMetrics v1.154.0, the operator v0.75.0, VictoriaLogs v1.53.0 and
VictoriaTraces v0.10.0, for the stack itself.

| Group | Alerts | Watches |
| --- | --- | --- |
| `vmsingle` | 11 | disk running out, churn, slow inserts, the series guard |
| `vm-health` | 12 | restarts, errors, too many logs, memory |
| `vmagent` | 15 | remote-write failures, dropped samples; `TooManyScrapeErrors` off |
| `vmalert` | 12 | rules failing to evaluate or to reload, notifications failing |
| `vmoperator` | 3 | the operator's reconcile errors |
| VictoriaLogs' groups | | with `logs` on: VictoriaLogs' health and ingestion |
| VictoriaTraces' groups | | with `traces` on: VictoriaTraces' health and ingestion |

## The socle's

For what no upstream source covers, as `VMRule`s in the module that owns the
metric, checked with `vmalert -dryRun` in CI.

| Group | Alerts | Ships in | Watches |
| --- | --- | --- | --- |
| `socle-flux` | 4 | `oci/catalog/monitoring/rules/flux.yaml` | Kustomizations, HelmReleases and sources not `Ready`, from awesome-prometheus-alerts; catalog modules (ResourceSets) not `Ready` |
| `socle-targets` | 1 | `oci/catalog/monitoring/rules/targets.yaml` | `TargetDown`, kube-prometheus' less the targets of a node that is cordoned, not `Ready` or already deleted |
| `opentelemetry-collector` | 13 | `oci/catalog/otel-gateway/rules/opentelemetry-collector.yaml` | both collectors down, out of memory, refusing or failing to send, their queues full; awesome-prometheus-alerts as written |

## The modules'

Each in the module's `monitoring/` folder, present only while the module and
`monitoring` are both on ([MONITORING-12](../decisions/monitoring.md)).

| Module | Rules | From |
| --- | --- | --- |
| `argocd` | 9 | awesome-prometheus-alerts, `argocd/embedded-exporter.yml`: applications out of sync or unhealthy, sync and git fetch failures, slow reconciliation |
| `argocd_image_updater` | 2 | the socle: image updates failing, registry requests failing |
| `crossplane` | 2 | the socle: managed resources not Ready, not Synced |
| `external_dns` | 2 | the socle: no successful sync for an hour, source or registry errors |
| `external_secrets` | 2 | the socle: an ExternalSecret not Ready, a store not Ready |
| `karpenter` | 5 | the socle: an EC2NodeClass or a NodePool not Ready, a NodePool near its limits, EC2 calls failing, pods no NodePool can place |
| `keda` | 3 | the chart's example (scaler errors), and the socle: ScaledObject and ScaledJob errors |
| `kyverno` | 3 | the chart's examples: admission latency, policy execution latency |
| `reloader` | 1 | the socle: a reload that failed |
| `velero` | 4 | the chart's examples: a backup failed, failing for 12 hours, none in 25 hours (hourly and daily schedules), partial failures |

## Off, and why

| Upstream group | Why |
| --- | --- |
| `etcd`, `kube-apiserver-slos`, `kube-apiserver-burnrate.rules`, `kube-apiserver-histogram.rules`, `kubernetes-system-apiserver`, `kubernetes-system-controller-manager`, `kubernetes-system-scheduler`, `kube-scheduler.rules`, `kubernetes-system-kube-proxy` | The control plane is the cloud's: not scraped, so nothing to read |
| `kube-apiserver-availability.rules` | Recording rules over the API server's metrics, which are not scraped |
| `prometheus`, `prometheus-operator`, `config-reloaders` | No Prometheus, no prometheus-operator |
| `windows` | No Windows nodes |

| Upstream alert | Why |
| --- | --- |
| `TargetDown` (`general.rules`) | A ratio per job that counts the targets of a node going away until the node is gone: with Autopilot or Karpenter replacing nodes, one dying node after another kept a job past 10 % down. The socle's `socle-targets` replaces it |
| `TooManyScrapeErrors` (`vmagent`) | Every failed scrape cluster-wide, a dying node's included, with no label to tell them apart; what it means, `TargetDown` says per job |
