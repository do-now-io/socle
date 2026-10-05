---
title: argocd
description: ArgoCD, the GitOps layer you ship your applications with, served on the private Gateway when you set a domain.
category: gitops
requires: []
---

ArgoCD is what you deploy your own applications with: Flux keeps the socle
converged, ArgoCD carries what you build on it. The module is **on by
default**, on every cloud, non-HA, with no application in it.

## What it installs

| | |
| --- | --- |
| Chart | `argo-cd` `10.9.2` (ArgoCD v3.5.3) from `oci://ghcr.io/argoproj/argo-helm/argo-cd` |
| Namespace | `argocd` |
| Objects | `Namespace/argocd`, `OCIRepository/argo-cd-chart`, `ConfigMap/argocd-socle-values`, `ConfigMap/argocd-client-values`, `HelmRelease/argocd`; with a `domain`, a `gateway` and the shared Gateways, the child `ResourceSet/argocd-route` holding `HTTPRoute/argocd-server` |

The socle's values, in `argocd-socle-values`:

| Value | Setting |
| --- | --- |
| `controller.replicas` | 1, with `ha` too: more controllers shard clusters, they do not add availability |
| `server`, `repoServer`, `applicationSet` `.replicas` | 1; 2 with `ha` |
| `redis-ha.enabled` | `true` only with `ha` |
| Requests | controller 250m / 256Mi, repoServer 100m / 128Mi, server 50m / 64Mi, applicationSet 50m / 64Mi, redis 50m / 32Mi; with `ha`, redis-ha 100m / 128Mi and haproxy 50m / 64Mi. No limits |
| `server.service.type` | `ClusterIP` |
| `configs.params."server.insecure"` | `true`: TLS ends at the Gateway or its load balancer, the server speaks plain HTTP in the cluster |
| `configs.cm."admin.enabled"` | `admin_enabled` |
| `global.domain` | `domain`, when set. The chart derives `configs.cm.url` from it |
| `configs.cm.url`, `statusbadge.url` | `""` when `domain` is empty, instead of the chart's `https://argocd.example.com` |
| `dex.enabled`, `notifications.enabled` | `false` |

The HelmRelease has a 10-minute timeout and retries a failed install or
upgrade three times.

## What you can set

Under `kube.argocd` in your tfvars:

| Attribute | Default | What it does |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on. `false` removes the release and its namespace; the CRDs stay ([CRDs when a module is off](../architecture/flux-catalog.md#crds-when-a-module-is-off)). |
| `admin_enabled` | `true` | `false` removes the local `admin` account. The module configures no SSO, so set it only once yours works through `values`. |
| `domain` | `""` | The host ArgoCD is served at, such as `argocd.acme.example`. Feeds `global.domain` and the route's hostname. Empty means no URL and no route. |
| `gateway` | `"private"` | The shared Gateway the route attaches to: `private`, `public`, or `""` for no route. |
| `ha` | `false` | The chart's HA layout without autoscaling: the `redis-ha` subchart and two replicas of server, repo-server and applicationset. `redis-ha` places its three Redis pods on three different nodes: on a cluster with fewer nodes they stay Pending. |
| `values` | `{}` | Any `argo-cd` chart value; yours win over the socle's ([SOCLE-06](../decisions/socle.md#socle-06-the-clients-values-win)). |
| `values_secret` | `""` | The name of a Secret you create in `argocd`, with a `values.yaml` key, merged last. OpenTofu never reads it. |

Refused at plan:

- `domain` that is not empty or a lowercase FQDN: no scheme, no port, no path.
- `gateway` other than `private`, `public` or `""`.
- In `values`: `configs.secret`, `configs.credentialTemplates`,
  `configs.clusterCredentials`, and a `password`, `sshPrivateKey`,
  `githubAppPrivateKey`, `bearerToken`, `tlsClientCertData` or
  `tlsClientCertKey` under `configs.repositories`. `values` lands in the
  OpenTofu state and in a ConfigMap; those go in `values_secret`. An
  ArgoCD `repo-creds` Secret you create yourself, labelled
  `argocd.argoproj.io/secret-type: repo-creds`, works too.
- `values_secret` that is not a valid Secret name.

A typical block:

```hcl
kube = {
  argocd = {
    domain = "argocd.acme.example"
    values = {
      configs = {
        cm   = { "accounts.alice" = "apiKey, login" }
        rbac = { "policy.csv" = "g, platform-admins, role:admin" }
        repositories = {
          acme = { url = "https://github.com/acme", type = "git", githubAppID = "12345", githubAppInstallationID = "67890" }
        }
      }
    }
    values_secret = "argocd-values" # holds configs.repositories.acme.githubAppPrivateKey
  }
}
```

A named attribute is a convenience, not a lock: `server.replicas` in
`values` wins over `ha`, `configs.cm.url` over `domain`. The chart version
and the namespace are not configurable. The socle ships no Application:
yours go in through the chart's `extraObjects` in `values`, or through
ArgoCD itself.

## Per cloud

The same template on aws, gcp, azure and scaleway, with no overlay patch.
The route exists where the shared Gateways do, aws and azure
([gateway-api](gateway-api.md)); on aws only once the foundations issued the
Gateways' certificate. Elsewhere, reach the server with
`kubectl -n argocd port-forward svc/argocd-server 8080:80`.

## Cloud access

None.

## Ordering

No requirement. The route waits for its Gateway: `argocd-route` `dependsOn`
the Gateway named by `gateway` being `Accepted`, so the release never waits
for the Gateway API CRDs and a missing Gateway leaves only the route
pending ([ARGOCD-02](../decisions/argocd.md#argocd-02-the-socle-owns-the-httproute-not-the-chart)).
The route sends `domain` on the `https` listener to `argocd-server:80`. The
`argocd` CLI logs in with `--grpc-web` over that route.

## Upgrade notes

The chart pin moves with `socle_version`, and the release notes name the
new version. Your `values` are written in the chart's vocabulary: a chart
major may rename keys, and adapting them is yours, as with any chart you
install yourself. `crds.keep` stays at the chart's `true`.

## Measured

| Date | Where | What |
| --- | --- | --- |
| 2026-09-24 | floci k3s v1.34.1, GitHub `ubuntu-latest` runner (7 GB) | `resourceset/argocd` Ready and `argocd-server` Available 42 s after the wait started on a bare root, 53 s on the full aws root; `enabled = false` garbage-collected the release in 8 s; back on, Ready 18 s later with the images already on the node. No eviction, no Pending pod |
| 2026-09-24 | `helm template` of chart 10.9.2 | A client `server.resources.requests.memory: 96Mi` gives `argocd-server` `cpu: 50m, memory: 96Mi`: the client's key wins, the socle's sibling key stays |

Its decisions: [argocd decisions](../decisions/argocd.md).
