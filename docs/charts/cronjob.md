---
title: cronjob
description: A scheduled task, deployed with the socle's conventions and compliant with every kyverno_policies policy.
sidebar:
  order: 2
---

`cronjob` deploys one of your scheduled tasks: a `CronJob` that starts a Job
on a schedule, whose pod runs until its work is done. It shares
[webapp](webapp.md)'s blocks and their values, in the same shape: the image,
the environment, the resources, the restricted profile, the volumes, and the
objects it creates (ConfigMaps, Secrets, ExternalSecrets, disks, its
ServiceAccount). Every pod it renders passes every
[kyverno_policies](../catalog/kyverno-policies.md) policy in its `restricted`
profile, all of them enforced.

## What it renders

| Object | When | Name |
| --- | --- | --- |
| `CronJob` | always | `<release>` |
| `ServiceAccount`, token not mounted | always | `<release>` |
| `ConfigMap`, `Secret`, `ExternalSecret`, `PersistentVolumeClaim` | one per entry, as in webapp | `<release>-<name>` |

No Service, route, autoscaler or budget: nothing calls a task.

## The values

The contract is [`values.yaml`](../../charts/cronjob/values.yaml) and
[`values.schema.json`](../../charts/cronjob/values.schema.json); the shared
keys are [webapp](webapp.md#the-values)'s. The task's own:

| Key | Default | |
| --- | --- | --- |
| `schedule` | required | cron's format |
| `timeZone` | `Etc/UTC` | no hour shift twice a year unless asked |
| `suspend` | `false` | no new Job while `true` |
| `concurrencyPolicy` | `Forbid` | a run still going at the next time skips it |
| `successfulJobsHistoryLimit`, `failedJobsHistoryLimit` | `3`, `1` | Jobs, and their logs, kept |
| `startingDeadlineSeconds` | unset | how late a missed run may start |
| `backoffLimit` | `0` | a failed run is not replayed unless you decide to |
| `activeDeadlineSeconds` | required | without it, a task that hangs runs forever |
| `restartPolicy` | `Never` | a failure stays visible, with its pod |
| `podAnnotations` | `{}` | on every Job's pod; AppArmor and legacy seccomp ones refused |

## Good to know

- **Deploy it as webapp**: the same ArgoCD Application, `chart: cronjob`
  ([webapp](webapp.md#deploy-it-with-argocd)).
- **The image as webapp's**: a `tag` may carry its digest,
  `uat@sha256:<64 hex>`, as Argo CD Image Updater's `digest` strategy writes
  it ([webapp](webapp.md#good-to-know)).
- **No Reloader**: every run starts a new pod, which reads the ConfigMaps and
  Secrets as they are.
- **On GKE Autopilot, a long task** asks not to be evicted while the
  autoscaler packs pods onto fewer nodes:
  `podAnnotations: { cluster-autoscaler.kubernetes.io/safe-to-evict: "false" }`
  makes its pod an extended-duration pod, for up to seven days. Not on spot
  nodes, which stay preemptible.
- **A disk in `persistence`** is attached by one Job's pod at a time:
  `concurrencyPolicy: Forbid` keeps it so.

<details>
<summary>Under the hood</summary>

**Built from** [`charts/cronjob`](../../charts/cronjob) and the
[`socle-lib`](../../charts/socle-lib) library chart. **Proven** as webapp
is; on floci and on the GKE sandbox (`charts-gke`), its first Job completes
with every policy enforced.
**Published** at each release as `oci://ghcr.io/do-now-io/charts/cronjob`,
signed.

</details>
