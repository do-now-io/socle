---
title: webapp
description: A web application that runs continuously and serves HTTP, deployed with the socle's conventions and compliant with every kyverno_policies policy.
sidebar:
  order: 1
---

`webapp` deploys one of your web applications: a container that runs
continuously and serves HTTP. It is a Helm chart you install yourself, from
your own GitOps repository, with your values. It writes the socle's
conventions once, so the catalog's modules work for your application without
configuration: routes on your Gateways, secrets from your secret manager,
rolling restarts on a changed secret, metrics scraped. Every pod it renders
passes every [kyverno_policies](../catalog/kyverno-policies.md) policy in its
`restricted` profile, all of them enforced.

It is not for a scheduled task ([cronjob](cronjob.md)), an application that
keeps state (a database: a StatefulSet), or a Secret several applications
read.

## What it renders

| Object | When | Name |
| --- | --- | --- |
| `Deployment` | always | `<release>` |
| `Service`, `ClusterIP` | always, the routes' backend | `<release>` |
| `ServiceAccount`, token not mounted | always | `<release>` |
| `HTTPRoute` | one per entry of `routes` | `<release>-<name>` |
| `ConfigMap` | one per entry of `configMaps` | `<release>-<name>` |
| `Secret`, from plaintext values | one per entry of `secrets` | `<release>-<name>` |
| `ExternalSecret`, and the `Secret` it writes | one per entry of `externalSecrets` | `<release>-<name>` |
| `PersistentVolumeClaim` | one per entry of `persistence` | `<release>-<name>` |
| `HorizontalPodAutoscaler` | `autoscaling.enabled` | `<release>` |
| `PodDisruptionBudget` | `podDisruptionBudget.enabled`, from two guaranteed pods | `<release>` |

The pods always run the restricted profile: not root, every capability
dropped, no privilege escalation, the `RuntimeDefault` seccomp profile, a
read-only root filesystem with an `emptyDir` on `/tmp`. No value loosens it.

## The values

The contract is [`values.yaml`](../../charts/webapp/values.yaml), every key
commented, and [`values.schema.json`](../../charts/webapp/values.schema.json)
holds it: a value that would break a policy or fail at apply time is refused
at render, naming the key.

- **Required, no default**: `image` (`registry`, `repository`, and a `tag`
  other than `latest` or a `digest`), `port`, `livenessProbe`,
  `readinessProbe`, `resources.requests` (`cpu`, `memory`),
  `securityContext.runAsUser`. Each application has its own, and a guessed
  one fails silently.
- **Kubernetes' own forms, copied as is**: `env`, `envFrom`, `volumes`,
  `volumeMounts`, `resources`, the routes' `parentRefs` and `rules`,
  `nodeSelector`, `tolerations`, `affinity`, `strategy`.
- **One way to read a ConfigMap or a Secret**, whoever created it: `env`,
  `envFrom` or `volumes`. One the chart creates is named `<release>-<name>`.
- **`commonEnv` and `commonEnvFrom`** for a values file several applications
  load: Helm replaces a list, so they are rendered first and the
  application's `env` and `envFrom` after, which win.

## Deploy it with ArgoCD

The chart from the registry, your values from your repository:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-shop
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: shop
  sources:
    - repoURL: ghcr.io/do-now-io/charts
      chart: webapp
      targetRevision: <socle version>
      helm:
        releaseName: shop
        valueFiles:
          - $values/apps/prod/values-common.yaml
          - $values/apps/prod/values-shop.yaml
    - repoURL: https://github.com/acme/infrastructure.git
      targetRevision: main
      ref: values
```

## Good to know

- **Set `releaseName`**: ArgoCD names the release after the Application
  otherwise, and every object follows (`prod-shop-config`, not
  `shop-config`).
- **A Secret several applications read is created once, outside the
  charts**: rendered by each, it would have one owner per application, each
  sync overwriting the others, and deleting one application would delete it
  for all. Reference it by name.
- **`secrets` keeps its values in plaintext** wherever the values file is,
  Git included: for a secret this application alone reads, where no secret
  manager is available.
- **Name a store**: `secretStoreRef` has no default. The socle's
  `ClusterSecretStore` `secret-manager` exists where
  [external_secrets](../catalog/external-secrets.md) creates it, on aws and
  gcp with crossplane on; elsewhere, your own store.
- **Name a Gateway**: a route's `parentRefs` has no default, since the
  Gateways' names and namespaces differ per cluster. Where
  [gateway_api](../catalog/gateway-api.md) creates them, on aws, azure and
  gcp: `public` or `private` in `gateway-system`, listener `https`.
- **Reloader** rolls the pods when a ConfigMap or Secret they read changes
  (`reloader.enabled`, on), with [reloader](../catalog/reloader.md) on.
- **A `ReadWriteOnce` disk** attaches to one node at a time: keep one
  replica, and `strategy.type: Recreate`.
- **A PodDisruptionBudget** renders only from two guaranteed pods
  (`replicas`, or `autoscaling.minReplicas`): with one, it would protect
  nothing or block every node drain.
- **A tag can carry its digest**: `tag: uat@sha256:<64 hex>` renders
  `<registry>/<repository>:uat@sha256:…`, which the node pulls by the
  digest: the tag says which build, the digest pins it. It is what Argo CD
  Image Updater's `digest` strategy writes in `image.tag`, to follow a tag
  you push again
  ([argocd-image-updater](../catalog/argocd-image-updater.md#good-to-know)).
  `latest` stays refused, with a digest too: follow a tag that names an
  environment (`uat`) instead.
- **Per cloud, gcp**: the shared Gateways are on GKE's own classes, so GKE's
  load balancer checks `/` on the serving port, not the pod's probes. An
  application that answers only on another path needs a `HealthCheckPolicy`,
  which the chart does not render: yours, beside it.

<details>
<summary>Under the hood</summary>

**Built from** [`charts/webapp`](../../charts/webapp) and the
[`socle-lib`](../../charts/socle-lib) library chart it bundles, which holds
every block it shares with [cronjob](cronjob.md): the pod, the container, the
restricted profile, the objects both create.

**Proven**: helm-unittest suites, one per template, every value and every
refusal of the schema; `helm lint --strict` and kubeconform on every fixture's
render; every fixture's pods against the kyverno_policies module's own
policies, `restricted` with the socle's own, through the Kyverno CLI; on
floci, installed with every policy enforced, the Deployment `Available` and
its ExternalSecret `Ready`. Not provable on floci: a route `Accepted`, since
floci runs no Gateway. On gcp, `charts-gke` (`platform: gke`), run by hand on
the sandbox's GKE Autopilot: both charts under every policy enforced, the
route `Accepted` by `private` and its backend resolved, the ExternalSecret
`Ready` through `secret-manager`.

**Published** at each release as `oci://ghcr.io/do-now-io/charts/webapp`,
signed ([Artifacts](../reference/artifacts.md)).

</details>
