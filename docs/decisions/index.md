---
title: Decisions
description: What a decision file is, the files grouped by socle, cloud and module, and how a decision's status changes.
sidebar:
  label: Overview
  order: 0
---

Every deliberate choice of the socle is written down once: what forced it,
what it costs, whether the code follows it. Other pages link here for the why.

## What a decision file is

One file per group: the socle itself, each cloud, each catalog module. Each
decision is a `##` section numbered within its file, `<GROUP>-NN`
(`SOCLE-04`, `AWS-01`, `ARGOCD-02`), never renumbered and never reused. A
section gives its **status**, **date** and implementing code, then the
**decision**, its **context**, its **consequences** (cost included) and its
**sources**.

## The files

**The socle**

- [Socle decisions](socle.md): how inputs become a converged catalog,
  distribution and releases, testing, the rules every module follows, the
  monitoring stack.

**The clouds**

- [AWS decisions](aws.md)
- [GCP decisions](gcp.md)
- [Azure decisions](azure.md)
- [Scaleway decisions](scaleway.md)

**The catalog modules**

[argocd](argocd.md) · [crossplane](crossplane.md) ·
[external-dns](external-dns.md) · [external-secrets](external-secrets.md) ·
[gateway-api](gateway-api.md) · [grafana](grafana.md) ·
[keda](keda.md) · [kyverno](kyverno.md) ·
[kyverno-policies](kyverno-policies.md) · [otel-agent](otel-agent.md) ·
[otel-gateway](otel-gateway.md) · [reloader](reloader.md) ·
[velero](velero.md) · [victoria-logs](victoria-logs.md) ·
[victoria-metrics](victoria-metrics.md) ·
[victoria-traces](victoria-traces.md)

## Status, and how a decision changes

| Status | Means |
| --- | --- |
| `accepted` | the code implements it; the evidence links to that code |
| `proposed` | decided or argued, not implemented yet; the consequences say what is missing |
| `superseded by <GROUP>-NN` | the code no longer follows it; the link names the section that replaced it |

An accepted section is never edited, except to mark it superseded. A
decision that changes is a new section, with its own number and date, and
the old one points to it. A decision that holds on some clouds and not
others says so in its status line.

A new file starts from
[`docs/decisions/_template.md`](https://github.com/do-now-io/socle/blob/main/docs/decisions/_template.md);
the rules are in [CONTRIBUTING](../contributing.md#the-rules).
