---
title: argocd-image-updater decisions
description: The decisions behind the argocd-image-updater module, one per section, each with its status.
sidebar:
  order: 10
---

The argocd-image-updater module moves the client's ArgoCD applications to
new image tags without a commit. The socle installs the controller and, on
aws, its read access to ECR; what to update, and how, stays the client's.

## ARGOCD-IMAGE-UPDATER-01: Its own module, off by default, refused without argocd

**proposed** · 2026-10-12 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.** Two shapes were weighed: a switch under `kube.argocd`, or a
module of its own.

- It is another chart: `kube.argocd.values` already belongs to the argo-cd
  chart, and leaves no place for this one's.
- On aws it declares a Crossplane role, so it waits for the `crossplane`
  ResourceSet. As a switch, `argocd`, on for every client and with no cloud
  access, would wait too.
- It does nothing until the client writes an `ImageUpdater`, and its aws
  access needs repository names only the client knows.

**Decision.** `kube.argocd_image_updater`, off by default. `tofu plan`
refuses it on while `kube.argocd` is off, and its ResourceSet `dependsOn`
the `argocd` one.

**Consequences.** Turning ArgoCD off means turning both off in the same
apply. One more catalog entry.

**Sources.** [#93](https://github.com/do-now-io/socle/issues/93).

## ARGOCD-IMAGE-UPDATER-02: Its own namespace, watching argocd

**proposed** · 2026-10-12 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

**Context.**

- An `ImageUpdater` selects `Application` objects in its own namespace only, and the
  socle's are in `argocd`: ArgoCD reads no other namespace unless "apps in
  any namespace" is turned on, which the socle does not do.
- Upstream installs the controller in the ArgoCD namespace. In the socle a
  module owns one namespace and removing it is what turning the module off
  means; a guest in `argocd` would be removed object by object.
- The chart's own Role already reads every Secret of the namespace it runs
  in: in `argocd`, every Secret of ArgoCD.

**Decision.** The controller runs in `argocd-image-updater`, with
`argocd.namespace` and `watch.namespaces` set to `argocd`. The module
renders a Role and RoleBinding in `argocd` reading Secrets and ConfigMaps,
for the `git` write-back credentials.

**Consequences.**

- The same access as the upstream layout, written by the socle and removed
  with the module.
- ArgoCD's SSH known hosts ConfigMap is not mounted from another namespace:
  `git` write-back over SSH is measured on aws before this is accepted; HTTPS
  and a GitHub App are unaffected.
- `Application` objects outside `argocd` are not watched.

**Sources.** [Installation](https://argocd-image-updater.readthedocs.io/en/stable/install/installation/); [Applications in any namespace](https://argo-cd.readthedocs.io/en/stable/operator-manual/app-any-namespace/).

## ARGOCD-IMAGE-UPDATER-03: No `ImageUpdater` from the socle; the write-back method is the client's

**proposed** · 2026-10-12 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

**Context.**

- An `ImageUpdater` names the client's applications, images and version
  rules, which the socle does not know, and decides what reaches production.
- The write-back method is a field of each `ImageUpdater`
  (`writeBackConfig.method`), per application: `argocd` by default, a
  parameter override on the `Application`, no Git credentials; or `git`, a
  commit with `git:repocreds` (ArgoCD's own) or a Secret in `argocd`.
- Upstream calls `argocd` "pseudo-persistent": a parent `Application` that
  syncs its children from Git (app-of-apps) removes the override, and the
  controller puts it back, in a loop.

**Decision.** The socle ships no `ImageUpdater` and no write-back attribute.
The page shows both methods, and the parent's `ignoreDifferences` on
`spec.source.helm.parameters` and `spec.source.kustomize.images` with
`RespectIgnoreDifferences=true`.

**Consequences.** Overrides outlive the module: turned off, an `Application`
stays on its last override until the client removes it, whatever Git says.

**Sources.** [Update methods](https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/); [Diffing customization](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/).

## ARGOCD-IMAGE-UPDATER-04: On aws, a read-only role on the repositories named, its token refreshed by a script

**proposed** · 2026-10-12 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

**Context.**

- ECR has no permanent password: `GetAuthorizationToken` returns one valid
  12 hours. Image Updater has no AWS code; it runs an `ext:` script and
  re-runs it after `credsexpire`, and its image ships the `aws` CLI.
- `GetAuthorizationToken` takes no resource; the token reaches only the
  repositories the role may read.
- A credential minted once would expire within the day.

**Decision.** `kube.argocd_image_updater.repositories` names ECR
repositories of the cluster's account and region (globs allowed). When it is
not empty, the module declares through Crossplane:

- a Role: `ecr:GetAuthorizationToken` on `*`; `ecr:ListImages`,
  `ecr:DescribeImages`, `ecr:BatchGetImage` and `ecr:GetDownloadUrlForLayer`
  on `arn:aws:ecr:<region>:<account>:repository/<name>` for each name;
- a Pod Identity association to `argocd-image-updater/argocd-image-updater`;
  the chart waits for both to be Ready.

The socle mounts the login script and writes the registry entry for
`<account>.dkr.ecr.<region>.amazonaws.com`, the registry of the cluster's
account and region, re-run every 11 hours. Empty: no role, no entry.
`tofu plan` refuses `repositories` with Crossplane off, off aws, or without
the cluster's region.

**Consequences.**

- The client adds `ecr` to the foundations' `aws.crossplane.allowed_services`;
  missing, the role fails at IAM.
- Another account or region is not covered.
- Measured on EKS (2026-10-13): the image's `aws` CLI takes the Pod
  Identity credentials, and `semver` needs no more than the three reads.
  `newest-build` also reads each image's config blob, for its creation date:
  without `ecr:GetDownloadUrlForLayer` it skips every image, `AccessDenied`
  in its error lines and `errors=0` in its summary. Granted, so that every
  documented strategy works; still a read, on the same repositories.

**Sources.** [ECR private registry authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html); [ECR actions and resources](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonelasticcontainerregistry.html); [Registries](https://argocd-image-updater.readthedocs.io/en/stable/configuration/registries/).

## ARGOCD-IMAGE-UPDATER-05: Elsewhere, the client's credential

**proposed** · 2026-10-12 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

**Context.** The socle has Crossplane providers on aws only.

**Decision.** On gcp, azure and scaleway, and on aws with `repositories`
empty, the module installs with no registry entry of the socle's. The client
creates a Secret in `argocd-image-updater` and names it in an entry of
`registries` (ARGOCD-IMAGE-UPDATER-07); `tofu plan` refuses a literal
credential there.

**Consequences.** Offered on every cloud; the registry access is proven on
aws only.

**Sources.** [Authentication](https://argocd-image-updater.readthedocs.io/en/stable/basics/authentication/).

## ARGOCD-IMAGE-UPDATER-06: The `ImageUpdater` CRD is kept

**proposed** · 2026-10-12 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

**Context.** Deleting a CRD deletes every object of its kind: every
`ImageUpdater` the client wrote.

**Decision.** The chart's `crds.keep` (`helm.sh/resource-policy: keep`),
stated in the socle's values.

**Consequences.** Turned off, the client's `ImageUpdater` objects stay, inert; on
again, they resume. Each keeps the controller's finalizer, which only drops
its metrics: with the controller gone, deleting one, or the `argocd`
namespace, hangs until the finalizer is released by hand. Documented, not
automated: a cleanup job would touch the client's objects for a rare case.

**Sources.** The `argocd-image-updater` chart's `values.yaml`.

## ARGOCD-IMAGE-UPDATER-07: The client's registries in an attribute, after the socle's

**proposed** · 2026-10-12 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

**Context.**

- Every registry entry lives in one list, the chart's `config.registries`.
  helm-controller merges `values` map by map but replaces a list whole: a
  client adding one registry through `values` would drop the socle's ECR
  entry, and ECR updates would stop with no error.
- Image Updater keys its entries by prefix: of two with the same prefix, the
  later wins, silently. For an image, an exact match on the registry host
  is taken before a longer prefix.

**Decision.** `kube.argocd_image_updater.registries` takes the client's
entries, as Image Updater writes them; the socle renders its own ECR entry
first, then these. `tofu plan` refuses `config.registries` in `values`, and,
while `repositories` is not empty, an entry whose prefix starts with the
registry of the cluster's account and region: a repository of that registry
is added to `repositories`.

**Consequences.** One more attribute. With `repositories` empty the client
may configure that registry himself, with his own credential; a registry of
another account or region is always his.

**Sources.** `registry-scanner/pkg/registry/config.go` and `endpoints.go` in Image Updater.
