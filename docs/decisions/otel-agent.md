---
title: otel-agent decisions
description: The decisions behind the otel-agent module, one per section, each with its status.
sidebar:
  order: 10
---

The decisions behind the node-level collector. The one to know first: while
it collects container logs, the agent runs as root, with every capability
dropped and a read-only `hostPath`
([OTEL-AGENT-03](#otel-agent-03-root-to-read-container-logs-with-nothing-else)).
The decisions that hold for the whole monitoring stack (one stack on every
cloud, OTLP everywhere, the socle's own dashboards) are in
[SOCLE-03](socle.md#socle-03-one-in-cluster-monitoring-stack-on-every-cloud).
The module page is [otel-agent](../catalog/otel-agent.md).

## OTEL-AGENT-01: A memory limit, so GOMEMLIMIT applies

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** The socle's modules set requests and no limits, by default. The
collector chart derives `GOMEMLIMIT` from the container's memory limit, and
the `memory_limiter` processor its threshold (80 %). Without a limit both read
the node's whole memory: the collector would grow until the node evicts it or
the kernel kills it, instead of refusing data first.

**Decision.** Requests 50m CPU and 128Mi memory, and a memory limit of
512Mi.

**Consequences.** Under pressure the agent refuses data before it reaches its
limit, and the Go runtime collects to stay under it. A node with more pods
than the limit allows for loses data rather than memory; a client raises the
limit through `values`.

**Sources.** The `opentelemetry-collector` chart 0.173.1 values; measured idle
on floci at 3–5m CPU and 33Mi, 2026-09-29.

## OTEL-AGENT-02: The kubelet call skips certificate verification

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** `kubeletstats` calls the kubelet at the node IP, port 10250.
Kubelet serving certificates are self-signed on EKS, and on most managed
clusters not signed by the CA a pod is given, so the call cannot verify
them. The alternative is kubelet serving certificates signed by the cluster
CA (`serverTLSBootstrap` and a CSR approver), a foundations change on every
cloud.

**Decision.** `insecure_skip_verify: true` on the `kubeletstats` receiver.
The call still carries the ServiceAccount token, which the kubelet
authorizes (`nodes/stats`).

**Consequences.** The call is encrypted and authenticated to the kubelet, but
the agent does not authenticate the kubelet: a node address answering in its
place would be believed. The scope is a read-only stats call from inside the
node.

**Sources.** The `kubeletstats` receiver's documentation; the chart's
`kubeletMetrics` preset.

## OTEL-AGENT-03: Root to read container logs, with nothing else

**accepted** · 2026-09-30 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** containerd writes each container's log under `/var/log/pods` as
root, mode 0640. Kubernetes gives a non-root container no effective
capability, so only root reads those files. The other way, log files readable
by a group the agent runs in, is a kubelet and runtime setting on every
cloud, not the socle's. The filelog receiver's checkpoints, which let a
restarted collector resume where it stopped, need a writable `hostPath`.

**Decision.** While container logs are collected (`victoria_logs` on and
`kube.otel_agent.logs` true), the agent runs as `runAsUser: 0`, with every
capability dropped, no privilege escalation and a read-only root filesystem,
and mounts `/var/log/pods` read-only. No checkpoints. Without logs, the agent
keeps the image's non-root user and has no `hostPath`.

**Consequences.** The agent reads the files as their owner and bypasses no
permission. It is the one socle module running as root, and only while it
collects logs. A restarted agent starts from the end of each file and loses
the lines written while it was down. A cluster under the Baseline Pod Security
Standard refuses the `hostPath`: `logs = false` is the switch.

**Sources.** Measured on floci, 2026-09-30: a container's line found in
VictoriaLogs 6 s after the pod's creation; with `victoria_logs` off, the live
DaemonSet had no `runAsUser` and no `hostPath`.

## OTEL-AGENT-04: No receiver port on the node

**accepted** · 2026-09-29 · [`oci/catalog/otel-agent/resourceset.yaml`](../../oci/catalog/otel-agent/resourceset.yaml)

**Context.** The collector chart opens six receiver ports by default (OTLP
gRPC and HTTP, three Jaeger, Zipkin), and in daemonset mode as `hostPort`s on
every node. Applications need one place to send OTLP, which the
otel-gateway's Service is.

**Decision.** Every receiver port off, and the `otlp`, `jaeger` and `zipkin`
receivers removed. The agent receives nothing.

**Consequences.** No port is opened on any node. An application sends its
OTLP to `otel-gateway.otel-gateway.svc`, one hop further than a node-local
agent would be.

**Sources.** The `opentelemetry-collector` chart 0.173.1 values.
