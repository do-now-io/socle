---
title: <Group> decisions
description: The decisions behind <the AWS foundations | the external-dns module | the socle>, one per section, each with its status.
sidebar:
  order: 10
---

<!--
A decision file groups the decisions of one cloud (aws, gcp, azure,
scaleway), one catalog module (its folder name), or the socle itself
(socle.md: what is neither). Copy this file to docs/decisions/<group>.md.
Files starting with `_` are not published.

Rules (CONTRIBUTING.md, Documentation, rule 3):
- One `##` section per decision, numbered within the file: <GROUP>-NN, never
  renumbered, never reused.
- Status is `accepted` only when the code implements the decision;
  otherwise `proposed`. A decision the code no longer follows is
  `superseded by <GROUP>-NN`, linking the section that replaces it.
- An accepted section is not edited, except to mark it superseded. A changed
  decision is a new section.
- Evidence links the code that implements it, relative to this file.
-->

One paragraph: what this group covers, and the one or two decisions a reader
should know first.

## AWS-01: EKS Standard, not Auto Mode

**accepted** · 2026-09-08 · [`opentofu/aws/cluster.tf`](../../opentofu/aws/cluster.tf)

**Context.** What forces the decision: the constraint, the options weighed,
the facts and their sources. No conclusion yet.

**Decision.** What is decided, in one or two sentences.

**Consequences.** What follows, good and bad, and what it costs.

**Sources.** The research, the upstream documentation, the issue or PR.
