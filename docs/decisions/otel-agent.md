---
title: otel-agent decisions
description: The decisions behind the otel-agent module, one per section, each with its status.
sidebar:
  order: 10
---

The node-level collector. While it collects container logs it runs as root,
with nothing else ([OTEL-AGENT-03](#otel-agent-03-root-to-read-container-logs-with-nothing-else)).
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

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

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

**accepted** · 2026-09-30 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

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
