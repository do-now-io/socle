---
title: argocd-image-updater
description: New image tags in your registry reach your ArgoCD applications, without a commit per release.
category: gitops
requires:
  - module: argocd
    why: it moves ArgoCD's Applications to new image tags
  - module: crossplane
    clouds: [aws, gcp]
    why: "only when repositories is set: the access that reads ECR or Artifact Registry is a Crossplane managed resource"
---

Argo CD Image Updater watches your registry and moves your ArgoCD
applications to the new image tags your rules allow: push `crm-api:1.5.0`,
and the application runs it, with no commit to bump a tag. Turn it on when
releases should reach an environment by themselves. **Off by default**, on
every cloud; the socle's read access is to ECR on aws and to Artifact
Registry on gcp.

## Getting started

On aws, add `ecr` to the foundations' `aws.crossplane.allowed_services`,
then name the repositories it may read:

```hcl kube-start="argocd_image_updater"
kube = {
  crossplane = { enabled = true }
  argocd_image_updater = {
    enabled      = true
    repositories = ["crm-api", "acme/*"]
  }
}
```

On gcp, add `roles/artifactregistry.reader` to the foundations'
`crossplane.allowed_roles`, then name the repositories as
`LOCATION/REPOSITORY`, in the cluster's project:

```hcl
kube = {
  crossplane = { enabled = true }
  argocd_image_updater = {
    enabled      = true
    repositories = ["europe-west1/apps"]
  }
}
```

Nothing is updated yet: write an `ImageUpdater` next to your `Application` objects,
in `argocd`, from your own GitOps repository.

```yaml
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: crm-api
  namespace: argocd
spec:
  applicationRefs:
    - namePattern: crm-api-uat1
      images:
        - imageName: 123456789012.dkr.ecr.eu-west-3.amazonaws.com/crm-api
          commonUpdateSettings:
            updateStrategy: semver
          manifestTargets:
            helm:
              tag: image.tag
```

Then `kubectl -n argocd get application crm-api-uat1 -o jsonpath='{.spec.source.helm.parameters}'`
shows the tag it moved to.

## Settings

| Attribute | Default | |
| --- | --- | --- |
| `enabled` | `false` | Turns the module on or off. Needs `kube.argocd`. |
| `repositories` | `[]` | aws: the ECR repositories it may read, in the registry of the cluster's account and region; globs allowed. gcp: `LOCATION/REPOSITORY` in the cluster's project; the role reads the whole project. `[]`: no role. |
| `registries` | `[]` | Your other registries, as Image Updater writes them, each with a credential of yours. |
| `values` | `{}` | Any [`argocd-image-updater` chart](https://artifacthub.io/packages/helm/argo/argocd-image-updater) value; yours win. |
| `values_secret` | `""` | A Secret in `argocd-image-updater` with a `values.yaml` key, for what must stay out of the OpenTofu state. |

### Every setting

```hcl kube-full="argocd_image_updater"
kube = {
  argocd_image_updater = {
    enabled      = false # off by default; needs kube.argocd
    repositories = []    # aws: ECR repository names or globs; gcp: LOCATION/REPOSITORY; [] = no role

    # Your other registries, after the socle's ECR entry. The credential is
    # a Secret you create in argocd-image-updater, never a literal.
    registries = [{
      name        = "ghcr"
      prefix      = "ghcr.io"
      api_url     = "https://ghcr.io"
      credentials = "pullsecret:argocd-image-updater/ghcr"
      credsexpire = "1h" # re-read the Secret hourly, so a rotated key is taken
    }]

    # Any value of the argocd-image-updater chart; yours win over the socle's.
    values = {
      config = {
        "log.level" = "debug"
        "git.user"  = "image-updater"
      }
    }

    # A Secret you create in argocd-image-updater, whose values.yaml key
    # holds chart values that must not reach the OpenTofu state.
    values_secret = "argocd-image-updater-values"
  }
}
```

## Good to know

- **Each `ImageUpdater` chooses how it writes**, per application, in
  `writeBackConfig.method`:
  - `argocd`, the default: an override on the `Application`, no Git access.
    Git keeps the old tag; the override wins.
  - `git:repocreds`: a commit, with the credentials ArgoCD reads your
    repository with, which must then be allowed to write. Or
    `git:secret:<name>`, a Secret of yours in `argocd`.
- **App-of-apps undoes `argocd` overrides.** A parent `Application` that
  syncs its children from Git removes the override, and the updater puts it
  back, in a loop. Tell the parent to leave it:

  ```yaml
  spec:
    ignoreDifferences:
      - group: argoproj.io
        kind: Application
        jsonPointers:
          - /spec/source/helm/parameters
          - /spec/source/kustomize/images
    syncPolicy:
      syncOptions:
        - RespectIgnoreDifferences=true
  ```

- **Overrides outlive the module.** Turned off, an `Application` stays on its
  last override, whatever Git says, until you remove it:
  `argocd app unset crm-api-uat1 --parameter image.tag`.
- **Delete your `ImageUpdater` objects before turning the module off.**
  Each carries a finalizer only the controller removes: afterwards, deleting
  one, or the `argocd` namespace, hangs until you release it:
  `kubectl -n argocd patch imageupdater <name> --type merge -p '{"metadata":{"finalizers":[]}}'`.
- **Read the controller's `level=error` lines, not its summary.** An image
  it cannot read, for want of access, is counted as skipped: the summary
  still says `errors=0`.
- **Only `Application` objects in `argocd` are watched**, the namespace ArgoCD reads.
- **`repositories` needs crossplane, on aws or gcp.** `tofu plan` refuses
  it otherwise. It cannot see `aws.crossplane.allowed_services` nor
  `crossplane.allowed_roles`: without `ecr`, or
  `roles/artifactregistry.reader`, there, the access fails at IAM, with the
  reason on the Role's or the ProjectIAMMember's `Synced` condition.
- **On gcp, `repositories` picks the registries, not the reach.** Its
  locations become the socle's entries, one `LOCATION-docker.pkg.dev` each;
  the role, Artifact Registry Reader, is on the project: Artifact Registry
  takes no IAM condition that would let Crossplane grant it on one
  repository and nothing more
  ([ARGOCD-IMAGE-UPDATER-08](../decisions/argocd-image-updater.md)). The
  login script renews the token every 5 minutes from the metadata server;
  no key.
- **The controller asks 256Mi of disk**, for its `git` write-back clones in
  `/tmp`. On GKE Autopilot that is also its limit: raise it in `values`
  (`resources.requests.ephemeral-storage`) for larger repositories.
- **A repository of your account's ECR goes in `repositories`**, never in
  `registries`: the socle already configures that registry, and `tofu plan`
  refuses a second entry for it while `repositories` is set.
- **Another registry takes your credential.** Create a Secret in
  `argocd-image-updater` and name it in an entry of `registries`. On
  scaleway, a Secret `scw-registry` whose `creds` key is
  `nologin:<secret key>`:

  ```hcl
  registries = [{
    name        = "scaleway"
    prefix      = "rg.fr-par.scw.cloud"
    api_url     = "https://rg.fr-par.scw.cloud"
    credentials = "secret:argocd-image-updater/scw-registry#creds"
  }]
  ```

  `tofu plan` refuses a literal credential there, and `config.registries` in
  `values`, which would replace the socle's entry.
- **Upgrades**: the chart moves with `socle_version`. The `ImageUpdater` CRD
  is kept when the module is off; your `ImageUpdater` objects stay, inert.

<details>
<summary>Under the hood</summary>

**Installed**: chart `argocd-image-updater` from
`oci://ghcr.io/argoproj/argo-helm/argocd-image-updater`, in
`argocd-image-updater`, watching `argocd`; a Role and RoleBinding in `argocd`
reading Secrets and ConfigMaps, for `git` write-back. On aws with
`repositories`, aws's step
([`oci/clusters/aws/argocd-image-updater/patch.yaml`](../../oci/clusters/aws/argocd-image-updater/patch.yaml))
adds `Role/argocd-image-updater`, `PodIdentityAssociation/argocd-image-updater`
and the ConfigMap `argocd-image-updater-cloud-values`. On gcp with
`repositories`, gcp's step
([`oci/clusters/gcp/argocd-image-updater/patch.yaml`](../../oci/clusters/gcp/argocd-image-updater/patch.yaml))
adds `ProjectIAMMember/argocd-image-updater` and the same ConfigMap.

**What the socle sets**: the CRD kept on removal, one replica, and on aws
with `repositories` the login script and the registry entry for
`<account>.dkr.ecr.<region>.amazonaws.com`, its token renewed every 11
hours; on gcp with `repositories` the login script and an entry for each
`<location>-docker.pkg.dev` named, its token renewed every 5 minutes; your
`registries` follow them. Your `values` are merged over these.

**Cloud access**: on aws, the role `<cluster>-argocd-image-updater` gets the
registry token on `*`, which reaches only what the role may read, and
`ListImages`, `DescribeImages`, `BatchGetImage` and `GetDownloadUrlForLayer`
on the repositories named. On gcp, the controller's own principal
(`…/subject/ns/argocd-image-updater/sa/argocd-image-updater`, no Google
service account) holds `roles/artifactregistry.reader` on the project.
Read-only.

**Ordering**: waits for the `argocd` ResourceSet, and on aws for
`crossplane`; the chart is applied after the cloud's step, which is healthy
only once the role and its association are Ready on aws, the project member
on gcp. On aws it also waits for the Job `argocd-image-updater-pod-identity`
to receive the Pod Identity credentials under the module's ServiceAccount,
which aws's step creates instead of the chart: a Ready association reaches
the admission webhook seconds later ([module IAM](../architecture/module-iam.md#the-ordering-chain)).

**Measured** on the sandbox EKS, 2026-10-13: an `ImageUpdater` moved an
`Application` to a new tag pushed to ECR within one 2-minute cycle, Git
untouched; the controller at idle, one `Application` watched, used 2m CPU
and 25Mi. On floci, every CI run: the same loop on GHCR, and the role's
policy in IAM. On the sandbox GKE Autopilot, 2026-10-16 (artifact
`0.0.0-feat-gcp-parity.d896756`, `argocd-image-updater-module-gke`, 70 s):
Artifact Registry's Docker endpoint accepted the metadata server's federated
token, and Image Updater listed the tags of the private repository
`europe-west1-docker.pkg.dev/sandbox-2bace/socle-e2e/podinfo` and moved the
`Application` from 6.9.0 to 6.9.4.

</details>
