---
title: argocd
description: ArgoCD, the GitOps layer you ship your applications with, served on the private Gateway when you set a domain.
category: gitops
requires: []
---

ArgoCD is what you deploy your own applications with: Flux keeps the socle
converged, ArgoCD carries what you build on it. **On by default**, on every
cloud, with no application in it.

## Getting started

It is already on. Give it a host, on the private Gateway:

```hcl title="terraform.tfvars" kube-start="argocd"
kube = {
  argocd = {
    domain  = "argocd.acme.example"
    gateway = "private"
  }
}
```

Then `kubectl -n argocd get httproute argocd-server` shows your host.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `true` | Turns the module on or off. |
| `domain` | `""` | The host ArgoCD is served at. Empty: no URL, no route. |
| `gateway` | `"private"` | The shared Gateway the route uses: `private`, `public` or `""`. |
| `admin_enabled` | `true` | `false` removes the local `admin` account, once your SSO works. |
| `ha` | `false` | Two replicas of each server and `redis-ha`. Needs three nodes. |
| `values` | `{}` | Any [`argo-cd` chart](https://artifacthub.io/packages/helm/argo/argo-cd) value; yours win. |
| `values_secret` | `""` | A Secret in `argocd` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl title="terraform.tfvars" kube-full="argocd"
kube = {
  argocd = {
    enabled       = true      # on by default
    admin_enabled = true      # the local admin account; false once your SSO works
    domain        = ""        # "" = no URL and no route; a host serves the UI
    gateway       = "private" # the route's shared Gateway: "private", "public" or ""
    ha            = false     # true: redis-ha and two replicas (needs 3 nodes)

    # Any value of the argo-cd chart 10.9.2; yours win over the socle's.
    values = {
      configs = {
        cm   = { "timeout.reconciliation" = "300s" }
        rbac = { "policy.default" = "role:readonly" }
      }
    }

    # A Secret you create in argocd, whose values.yaml key holds chart values
    # that must not reach the OpenTofu state, such as a repository's
    # githubAppPrivateKey.
    values_secret = "argocd-values"
  }
}
```

## Good to know

- **No route without the shared Gateways.** They exist on aws (once the
  Gateways' certificate is issued) and azure. Elsewhere:
  `kubectl -n argocd port-forward svc/argocd-server 8080:80`.
- **Repository credentials go in `values_secret`**, or in a `repo-creds`
  Secret of your own. `tofu plan` refuses them in `values`, which lands in
  the state.
- **Your `values` win over the attributes**: `server.replicas` over `ha`,
  `configs.cm.url` over `domain`.
- **The socle ships no Application.** Add yours through ArgoCD, or the
  chart's `extraObjects`.
- **Upgrades**: the chart moves with `socle_version`. A chart major may
  rename keys you set in `values`.

<details>
<summary>Under the hood</summary>

**Installed**: chart `argo-cd` 10.9.2 (ArgoCD v3.5.3) from
`oci://ghcr.io/argoproj/argo-helm/argo-cd`, in the `argocd` namespace. With a
`domain`, a `gateway` and the shared Gateways, a child `ResourceSet/argocd-route`
holds `HTTPRoute/argocd-server`, which waits for its Gateway to be `Accepted`.

**What the socle sets**: one replica of each component (two with `ha`; the
controller stays at one), requests with no limits, `server.insecure` (TLS
ends at the Gateway), `dex` and `notifications` off, `admin.enabled` and
`global.domain` from the attributes. Your `values` are merged over these.

**Cloud access**: none.

**Measured** on floci k3s, 2026-09-24: Ready 42 s after the wait started
(53 s on the full aws root); turned off, removed in 8 s.

</details>
