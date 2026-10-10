---
title: Alert rules
description: Every alert rule the socle ships, by module and severity, where each comes from, and the upstream rules it does not take, with the reason.
sidebar:
  order: 6
---

The socle's alert rules ship with the modules whose metrics they read, and
fire once [alerting](../catalog/alerting.md) is on: nothing to write, nothing
to turn on one by one. They are taken from
[awesome-prometheus-alerts](https://samber.github.io/awesome-prometheus-alerts/)
(`_data/rules.yml` at `822af1e`), the alert named as it names it. Above each
rule, its rule file says the upstream section and rule it comes from, and
where the socle departs from it.

**Severity.** `critical` for a node lost, or data lost or about to be;
`warning` for everything else. Upstream `info` rules are not taken. Route
`severity="critical"` to your on-call.

## The rules, by module

**Origin**: *upstream* is awesome-prometheus-alerts' expression as written;
*translated* is its rule rewritten on the names OpenTelemetry stores;
*socle* has no upstream counterpart.

### kube_state_metrics: Kubernetes objects and Flux

| Alert | Severity | Origin |
| --- | --- | --- |
| `KubernetesNodeNotReady` | critical | upstream |
| `KubernetesNodeNetworkUnavailable` | critical | upstream |
| `KubernetesNodeMemoryPressure` | warning | upstream (critical there) |
| `KubernetesNodeDiskPressure` | warning | upstream (critical there) |
| `KubernetesNodeSchedulingDisabled` | warning | upstream |
| `KubernetesNodeOutOfPodCapacity` | warning | upstream |
| `KubernetesPodCrashLooping` | warning | upstream |
| `KubernetesPodNotHealthy` | warning | upstream (critical there) |
| `KubernetesContainerOomKiller` | warning | upstream |
| `KubernetesContainerWaiting` | warning | upstream |
| `KubernetesDeploymentReplicasMismatch` | warning | upstream |
| `KubernetesDeploymentRolloutStuck` | warning | upstream |
| `KubernetesDeploymentGenerationMismatch` | warning | upstream (critical there) |
| `KubernetesReplicasetReplicasMismatch` | warning | upstream |
| `KubernetesStatefulsetDown` | warning | upstream (critical there) |
| `KubernetesStatefulsetReplicasMismatch` | warning | upstream |
| `KubernetesStatefulsetGenerationMismatch` | warning | upstream (critical there) |
| `KubernetesStatefulsetUpdateNotRolledOut` | warning | upstream |
| `KubernetesDaemonsetRolloutStuck` | warning | upstream |
| `KubernetesDaemonsetMisscheduled` | warning | upstream |
| `KubernetesJobFailed` | warning | upstream |
| `KubernetesJobNotStarting` | warning | upstream |
| `KubernetesJobSlowCompletion` | warning | upstream (critical there) |
| `KubernetesCronjobTooLong` | warning | upstream, expression fixed: its `absent()` matched no Job |
| `KubernetesCronjobFailing` | warning | upstream (critical there) |
| `KubernetesPersistentvolumeclaimPending` | warning | upstream |
| `KubernetesPersistentvolumeError` | critical | upstream |
| `KubernetesHpaScaleInability` | warning | upstream |
| `KubernetesHpaMetricsUnavailability` | warning | upstream |
| `KubernetesPoddisruptionbudgetNotEnoughHealthyPods` | warning | upstream |
| `KubernetesResourcequotaExceeded` | warning | upstream |
| `KubernetesKubeStateMetricsListWatchErrors` | warning | upstream (critical there) |
| `FluxKustomizationFailure` | warning | upstream |
| `FluxHelmreleaseFailure` | warning | upstream |
| `FluxSourceIssue` | warning | upstream |
| `FluxResourcesetFailure` | warning | socle: a catalog module not `Ready` for 15 minutes |

### otel_agent: nodes, volumes, the agent itself

| Alert | Severity | Origin |
| --- | --- | --- |
| `HostOutOfMemory` | warning | translated: available over available plus working set |
| `HostHighCpuLoad` | warning | translated: cores used over the capacity kube-state-metrics reports |
| `HostOutOfDiskSpace` | warning | translated (critical there): the node filesystem the kubelet evicts on |
| `HostDiskMayFillIn24Hours` | warning | translated |
| `KubernetesVolumeOutOfDiskSpace` | critical | translated: kubeletstats volumes, joined to their claim |
| `KubernetesVolumeFullInFourDays` | warning | translated |
| `KubernetesVolumeOutOfInodes` | critical | translated (warning there) |
| `KubernetesVolumeInodesFullInFourDays` | warning | translated (critical there) |
| `OpentelemetryCollectorHighMemoryUsage` | warning | translated: one collector is one `service_instance_id` |
| `OpentelemetryCollectorReceiverRefusedMetricPoints` | critical | upstream: the alerts go blind |
| `OpentelemetryCollectorReceiverRefusedSpans`, `…RefusedLogRecords` | warning | upstream (critical there): no alert reads them |
| `OpentelemetryCollectorOtlpReceiverErrors` | warning | upstream (critical there) |
| `OpentelemetryCollectorExporterFailedSpans`, `…MetricPoints`, `…LogRecords` | warning | upstream |
| `OpentelemetryCollectorExporterQueueNearlyFull` | warning | translated, as high memory usage |
| `OpentelemetryCollectorExporterEnqueueFailedSpans`, `…MetricPoints`, `…LogRecords` | warning | upstream |

### otel_gateway: the gateway itself

The same twelve OpenTelemetry Collector rules as otel_agent, on the
gateway's own telemetry.

### victoria_metrics and alerting

| Alert | Severity | Origin |
| --- | --- | --- |
| `VictoriaMetricsDiskAlmostFull` | warning | socle |
| `VictoriaMetricsSeriesLimitNear` | warning | socle |
| `VictoriaMetricsSeriesDropped` | critical | socle |
| `Watchdog` | none | socle: always firing, for the dead man's switch |
| `AlertingRulesNotReloaded` | warning | socle |
| `AlertingRuleFails` | warning | socle |
| `AlertmanagerNotificationsFailing` | warning | socle |

## The upstream rules not taken

### Kubernetes

| Upstream rule | Why not |
| --- | --- |
| API server errors, API client errors, API server terminating requests, API server latency | The API server is not scraped: the control plane is managed, and its request histograms would weigh heavily on VictoriaMetrics' hourly series limit |
| Client certificate expires soon, expires next week | The same: API server metrics |
| Version mismatch | Reads `kubernetes_build_info` from the API server and kubelets, which are not scraped; and true through every ring upgrade |
| CronJob suspended | Suspending is deliberate; the rule cannot tell it from forgotten, and would fire until resumed |
| HPA scale maximum, HPA underutilized | `info`: capacity planning, not a failure |

### Host and hardware

Written on node-exporter, which the socle does not run: the nodes are read
through the kubelet.

| Upstream rule | Status |
| --- | --- |
| Host out of memory, Host high CPU load, Host out of disk space, Host disk may fill in 24 hours | Translated, above |
| Host memory under memory pressure | Covered by `KubernetesNodeMemoryPressure`: the condition the kubelet acts on |
| Host OOM kill detected | Covered by `KubernetesContainerOomKiller`, per container |
| Host CPU steal noisy neighbor, Host CPU high iowait, Host CPU load saturation, Host swap is filling up, Host unusual disk IO, Host disk IO saturation, Host unusual disk read latency, Host unusual disk write latency, Host rebooted | Not covered yet: OpenTelemetry's `hostmetrics` receiver can give these without the node's root filesystem; a follow-up |
| Host out of inodes, Host inodes may fill in 24 hours | Not covered: the kubelet's node filesystem figures carry no inodes |
| Host clock skew, Host clock not synchronising | Not covered: no OpenTelemetry source |
| Host conntrack limit | Not covered: conntrack is per network namespace, out of a pod's sight |
| Host file descriptors limit warning, critical | Not covered: no OpenTelemetry source |
| Host Network Receive Errors, Transmit Errors, unusual network throughput in, out | Not covered: the kubelet counts errors but no packets, and no link speed |
| Host context switching high | Not covered: no OpenTelemetry source |
| Host filesystem device error | Not covered: no OpenTelemetry source |
| Host kernel version deviations | Not taken: true through every ring upgrade |
| Host node overtemperature alarm, Host physical component too hot, Host software RAID insufficient drives, Host software RAID disk failure, Host EDAC Correctable and Uncorrectable Errors detected, Host Network Bond Degraded, Host systemd service crashed, Host systemd service crash looping, Host textfile collector scrape error | Not applicable: managed virtual machines |
| Host CPU is underutilized, Host Memory is underutilized | Not taken: capacity planning, not a failure |

### FluxCD

| Upstream rule | Why not |
| --- | --- |
| Flux Image Issue | The image automation controllers are not installed (`flux_components`) |

### OpenTelemetry Collector

| Upstream rule | Why not |
| --- | --- |
| OpenTelemetry Collector down | A collector scrapes itself and cannot report itself gone; its Deployment and DaemonSet are watched by `KubernetesDeploymentReplicasMismatch` and `KubernetesDaemonsetRolloutStuck` |
| Processor refused spans, metric points | The collector no longer reports them (0.160.0 counts items in and out); what the memory limiter refuses, the receivers report as refused |
