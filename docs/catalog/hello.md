---
title: hello
description: podinfo, a smoke test that your socle renders, converges and garbage-collects.
category: platform
requires: []
---

hello runs [podinfo](https://github.com/stefanprodan/podinfo), a small web page
that proves your inputs reach the cluster, that a module converges and that
turning one off removes it. **On by default**, on every cloud; turn it off once
you trust the pipeline.

## Getting started

It is already on. Change its message to see an input reach the cluster:

```hcl kube-start="hello"
kube = {
  hello = {
    replicas = 2
    message  = "hello from acme"
  }
}
```

Then `kubectl -n hello port-forward svc/podinfo 9898:9898` and `http://localhost:9898` reads `hello from acme — <cluster name> on <cloud>`.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. |
| `replicas` | `1` | podinfo's replica count. |
| `message` | `"hello from socle"` | The message on podinfo's page; the cluster name and the cloud are appended. |

hello has no `values` and no `values_secret`: it exists to show inputs
flowing, not to be configured.

### Every setting

```hcl kube-full="hello"
kube = {
  hello = {
    enabled  = true               # on by default; false once you trust the pipeline
    replicas = 1                  # podinfo's replica count
    message  = "hello from socle" # the cluster name and the cloud are appended
  }
}
```

## Good to know

- **The page's colour is the cloud's**, set by each cloud's overlay: it shows
  a per-cloud detail carried by an overlay, as the message shows one carried
  by the inputs.
- **Turning it off removes the release and its namespace**: the quickest
  proof that garbage collection works.
- **Upgrades**: nothing to adapt; the chart moves with `socle_version`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `podinfo` 6.15.0 from
`oci://ghcr.io/stefanprodan/charts/podinfo`, in the `hello` namespace.

**What the socle sets**: `replicaCount` from `replicas`, and `ui.message` from
`message` with the cluster name and the cloud appended.

**Cloud access**: none.

**Measured** on floci 2.1.0, GitHub runner, 2026-09-30: a value patched into
the inputs reached podinfo in 13 s.

</details>
