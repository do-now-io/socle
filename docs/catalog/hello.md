---
title: hello
description: podinfo, a smoke test that your socle renders, converges and garbage-collects.
category: platform
requires: []
---

hello runs [podinfo](https://github.com/stefanprodan/podinfo), a small web
application whose page shows a message and a colour. It proves that your
inputs reach the cluster, that a module converges and that turning one off
removes it. It is **on by default** in every client cluster; turn it off once
you trust the pipeline.

## What it installs

| | |
| --- | --- |
| Chart | `podinfo` `6.15.0` from `oci://ghcr.io/stefanprodan/charts/podinfo` |
| Namespace | `hello` |
| Objects | `Namespace/hello`, `OCIRepository/podinfo-chart`, `HelmRelease/podinfo` |

The release sets two chart values: `replicaCount` from `replicas`, and
`ui.message`, which reads `<message> — <cluster name> on <cloud>`.

## What you can set

Under `kube.hello` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. `false` removes the release and its namespace. |
| `replicas` | `1` | podinfo's replica count. |
| `message` | `"hello from socle"` | The message on podinfo's page; the cluster name and the cloud are appended. |

hello has no `values` and no `values_secret`: it exists to show the inputs
flowing, not to be configured. A value of the wrong type, such as
`replicas = "two"`, is refused at plan.

To see it:

```sh
kubectl -n hello port-forward svc/podinfo 9898:9898   # then http://localhost:9898
```

## Per cloud

The same template on every cloud. Each `oci/clusters/<cloud>/` overlay
patches one value, podinfo's UI colour: `#FF9900` on aws, `#4285F4` on gcp,
`#0078D4` on azure, `#4F0599` on scaleway. The colour shows a cloud-specific
detail carried by an overlay; the message shows one carried by the inputs.

## Cloud access

None.

## Ordering

None.

## Upgrade notes

Nothing to adapt: the module has no free-form values.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-22 | floci k3s v1.34.1, GitHub `ubuntu-latest` runner | `enabled = false`: the HelmRelease gone in 1 s; back on, Ready again in about 76 s; the second `tofu plan` empty |
| 2026-09-30 | floci 2.1.0, GitHub `ubuntu-latest` runner | A value patched into the inputs reached podinfo in 13 s |

The socle's end-to-end tests also use podinfo as a client application: the
otel_gateway test posts an OTLP gauge from podinfo's pod and reads it back
enriched with `k8s_deployment_name=podinfo`.
