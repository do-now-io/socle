---
title: otel-agent decisions
description: The decisions behind the otel-agent module, one per section, each with its status.
sidebar:
  order: 10
---

The node-level collector ships the containers' logs, and nothing else; it
runs as root to read them, with nothing else
([OTEL-AGENT-06](#otel-agent-06-the-containers-logs-only-while-monitoring-stores-them)).
The node's metrics are vmagent's
([MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)).
The stack-wide decisions are [SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).

## OTEL-AGENT-01: A memory limit, so GOMEMLIMIT applies

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Decision.** Requests 50m CPU and 128Mi, and a memory limit of 512Mi.

**Context.** Socle modules set no limits by default, but the chart derives
`GOMEMLIMIT` and the `memory_limiter` threshold (80 %) from the memory limit.
Without one, the collector grows until evicted instead of refusing data.

**Consequences.** Under pressure the agent refuses data before its limit. A
busy node loses data rather than memory; the client raises the limit through
`values`.

**Sources.** The `opentelemetry-collector` chart 0.173.1 values; measured idle on floci at 3–5m CPU and 33Mi, 2026-09-29.

## OTEL-AGENT-02: The kubelet call skips certificate verification

**superseded by [MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Decision.** `insecure_skip_verify: true` on the `kubeletstats` receiver; the
call still carries the ServiceAccount token, authorized for `nodes/stats`.

**Context.** Kubelet serving certificates are self-signed on EKS and on most
managed clusters. Signing them with the cluster CA would be a foundations
change on every cloud.

**Consequences.** The agent does not authenticate the kubelet: an address
answering in its place would be believed. The scope is a read-only stats call
from inside the node.

**Sources.** The `kubeletstats` receiver's documentation; the chart's `kubeletMetrics` preset.

## OTEL-AGENT-03: Root to read container logs, with nothing else

**superseded by [OTEL-AGENT-06](#otel-agent-06-the-containers-logs-only-while-monitoring-stores-them)** · 2026-09-30 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Decision.** While container logs are collected (`victoria_logs` on and
`kube.otel_agent.logs` true), the agent runs as `runAsUser: 0`, every
capability dropped, no privilege escalation, read-only root filesystem, and
mounts `/var/log/pods` read-only; no checkpoints. Otherwise it stays non-root
with no `hostPath`.

**Context.** containerd writes logs as root, mode 0640, and a non-root
container has no effective capability. Group-readable logs would be a kubelet
setting on every cloud; checkpoints would need a writable `hostPath`.

**Consequences.** The one socle module running as root, only while it collects
logs. A restarted agent loses the lines written while it was down. Under the
Baseline Pod Security Standard, `logs = false` is the switch.

**Sources.** Measured on floci, 2026-09-30: a line in VictoriaLogs 6 s after the pod's creation; with `victoria_logs` off, no `runAsUser` and no `hostPath`.

## OTEL-AGENT-04: No receiver port on the node

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Decision.** Every receiver port off; the `otlp`, `jaeger` and `zipkin`
receivers removed. The agent receives nothing.

**Context.** The chart opens six receiver ports by default, as `hostPort`s in
daemonset mode. Applications need one OTLP endpoint, the otel-gateway's
Service.

**Consequences.** No port opens on any node. Applications send OTLP to
`otel-gateway.otel-gateway.svc`, one hop further than a node-local agent.

**Sources.** The `opentelemetry-collector` chart 0.173.1 values.

## OTEL-AGENT-05: Volume metrics for the claims only, their name from the kubelet's pod list

**superseded by [MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)** · 2026-10-12 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml), [`oci/catalog/otel-agent/rules/otel-agent.yaml`](../../oci/catalog/otel-agent/rules/otel-agent.yaml)

**Context.** The PersistentVolumeClaim rules (#91) need how full each claim
is. kubeletstats' `volume` group reports every volume of every pod; it labels
a volume's type and claim only through `extra_metadata_labels`, which reads
the kubelet's pod list. The receiver documents `nodes/pods` for it: the
kubelet's fine-grained authorization, on by default since Kubernetes 1.33,
grants that list alone, where older kubelets asked for `nodes/proxy`, which
also opens exec into the node's pods.

**Decision.** The `volume` group with `extra_metadata_labels:
[k8s.volume.type]`, `get` on `nodes/pods`, and a filter that keeps the
`persistentVolumeClaim` volumes only.

**Consequences.** Each claim's fill reaches VictoriaMetrics under its own
name (`k8s_persistentvolumeclaim_name`), nothing else's: a pod's token,
ConfigMap and emptyDir volumes would be five series each. On a kubelet before
1.33 the pod list is refused and the volume rules have nothing to read. The
inode counts are stored as `*_ratio`: kubeletstats gives them the unit `1`.

**Sources.** kubeletstats receiver 0.160.0 README (Role-based access
control); measured on floci k3s 1.34, 2026-10-12: the claim named, no
refusal.

## OTEL-AGENT-06: The containers' logs only, while monitoring stores them

**accepted** · 2026-10-12 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** vmagent now scrapes the kubelets, cAdvisor and node-exporter
([MONITORING-02](monitoring.md#monitoring-02-vmagent-is-the-one-place-metrics-are-scraped)):
`kubeletstats` would collect the same twice, under names no upstream rule
reads. What only a node-local agent does is read `/var/log/pods`, which
containerd writes as root, mode 0640.

**Decision.** No metrics pipeline and no `kubeletstats`; `file_log` with
`k8s_attributes` to the monitoring module's VictoriaLogs. The release is
rendered only while `monitoring` and its `logs` are on. The agent runs as
`runAsUser: 0`, every capability dropped, no privilege escalation, read-only
root filesystem, `/var/log/pods` mounted read-only, no checkpoints. Its own
telemetry is scraped by vmagent through its `prometheus.io/scrape`
annotation. `kube.otel_agent.logs` is gone: off is `enabled = false`, or
`monitoring.logs.enabled = false`.

**Consequences.** Under the Baseline Pod Security Standard, the agent is
turned off rather than run without logs. A restarted agent loses the lines
written while it was down.

**Sources.** Measured on floci, 2026-09-30 (a line in VictoriaLogs 6 s
after the pod's creation); #91.

## OTEL-AGENT-07: On gcp, the logs without the chart's preset, and a priority for the agent

**accepted** · 2026-10-16 · [`oci/clusters/gcp/otel-agent/patch.yaml`](../../oci/clusters/gcp/otel-agent/patch.yaml)

**Decision.** On gcp the module's cloud step turns the chart's
`logsCollection` preset off and writes what it would have: one read-only
`hostPath` on `/var/log/pods` and the `file_log` receiver as chart 0.173.1
renders it, listed in the logs pipeline. It also creates
`PriorityClass/socle-node-agent` (value 1000000,
`PreemptLowerPriority`, `globalDefault: false`) before the workload step,
and sets the chart's `priorityClassName` to it.

**Context.** Autopilot admits a `hostPath` only under `/var/log`, read-only.
The preset always mounts `/var/lib/docker/containers` as well, a path
containerd never writes to, and Autopilot refuses the whole pod for it. A
DaemonSet pod is bound to its node: on a full one (Autopilot's 32 pods, or
its CPU and memory) it stays `Pending`, and the module never `Ready` —
measured on the GKE sandbox. With a priority above an ordinary pod's 0 it
preempts one, which the autoscaler places elsewhere. The system classes
(2000000000 and up) are the cluster's; GKE allows a custom class up to
1000000000.

**Consequences.** The collector's rendered configuration on gcp is the
preset's, byte for byte. A client's `priorityClassName` in `values` wins;
the class then stays unused. The class goes with the module.

**Sources.** [Autopilot security
measures](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security);
the opentelemetry-collector chart 0.173.1's `logsCollection` preset;
[cluster autoscaler, pod eviction
order](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/cluster-autoscaler);
`otel-agent-health-gke`, sandbox, PR #84 (the test's `to_number(priority)` and its
`globalDefault` read, both fixed there), passed again on 2026-10-16 (artifact
`0.0.0-feat-gcp-parity.d896756`).

## OTEL-AGENT-08: A disk request, on every cloud

**accepted** · 2026-10-16 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Decision.** The agent asks 64Mi of ephemeral storage beside its 50m /
128Mi: its rotated logs and scratch, nothing else is written.

**Context.** GKE Autopilot sizes a DaemonSet container that leaves its disk
out at 100Mi, and makes the request the limit
([MONITORING-13](monitoring.md#monitoring-13-requests-on-every-container-disk-included-on-every-cloud)).

**Consequences.** The per-node price on Autopilot is 50m / 128Mi / 64Mi.

**Sources.** [Resource requests in Autopilot](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-resource-requests).
