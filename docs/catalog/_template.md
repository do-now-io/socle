---
title: <module>
description: One line, for the client — what the module gives them, not how it is built.
category: networking # networking | security | gitops | observability | autoscaling | secrets | backup | platform
requires: # only what the module does not work without; each also appears in its ResourceSet's spec.dependsOn
  - module: crossplane
    clouds: [aws] # omit for every cloud
    why: its IAM role is a Crossplane managed resource
---

<!--
The page of one catalog module, for the client who turns it on. Copy this file
to docs/catalog/<module>.md (the folder name under oci/catalog/). Design
rationale goes to docs/decisions/<module>.md, which the site does not publish; no PR history, no test counts,
no questions for a reviewer. Files starting with `_` are not published.
-->

Two sentences: what it is, and when to turn it on. Whether it is on by
default.

## Getting started

One sentence, then the block a client copies: the module on, and the two or
three settings they set first. `kube-start` names the catalog.tf key; the
build refuses an attribute the module does not have.

```hcl title="terraform.tfvars" kube-start="<catalog key>"
kube = {
  <catalog key> = {
    enabled = true
  }
}
```

## What it installs

| | |
| --- | --- |
| Chart | `<chart>` `<version>` from `<repository>` |
| Namespace | `<namespace>` |
| Objects | what the ResourceSet renders, in one line |

## What you can set

Under `kube.<module>` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on. |
| `values` | `{}` | Any chart value; yours win over the socle's. |
| `values_secret` | `{}` | Chart values that are secrets: kept out of the state. |

What is refused at plan, and why.

### Every setting

Every attribute, at its default, and how chart values and secrets go in.
`kube-full` names the catalog.tf key; the build refuses a block that lists
more or fewer attributes than catalog.tf. Attributes sit at four spaces.

```hcl title="terraform.tfvars" kube-full="<catalog key>"
kube = {
  <catalog key> = {
    enabled       = false            # what it does
    values        = { }              # real keys of the chart, at its pinned version
    values_secret = "<module>-values" # what the Secret holds
  }
}
```

## Per cloud

What differs on aws, gcp, azure and scaleway, and where it is not offered.

## Cloud access

What the module may do in your cloud account, and how it gets that access.
"None" when it needs none.

## Ordering

What it requires, and what it only waits for.

## Upgrade notes

What to know when the socle moves this module to a new chart version.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-10-01 | floci, k3s | converged in 42 s; 120 MiB at idle |
