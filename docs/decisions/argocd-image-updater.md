---
title: argocd-image-updater decisions
description: The decisions behind the argocd-image-updater module, one per section, each with its status.
sidebar:
  order: 10
---

The argocd-image-updater module moves the client's ArgoCD applications to
new image tags without a commit. The socle installs the controller and, on
aws, its read access to ECR, on gcp to Artifact Registry; what to update,
and how, stays the client's.

## ARGOCD-IMAGE-UPDATER-01: Its own module, off by default, refused without argocd

**accepted** · 2026-10-13 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

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

**accepted** · 2026-10-13 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

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
  `git` write-back over SSH may fail host-key verification, not measured;
  HTTPS and a GitHub App are unaffected.
- `Application` objects outside `argocd` are not watched.

**Sources.** [Installation](https://argocd-image-updater.readthedocs.io/en/stable/install/installation/); [Applications in any namespace](https://argo-cd.readthedocs.io/en/stable/operator-manual/app-any-namespace/).

## ARGOCD-IMAGE-UPDATER-03: No `ImageUpdater` from the socle; the write-back method is the client's

**accepted** · 2026-10-13 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

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

**accepted** · 2026-10-13 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf)

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

**accepted** · 2026-10-13 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

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

**accepted** · 2026-10-13 · [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

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

**accepted** · 2026-10-13 · [`opentofu/bootstrap/catalog.tf`](../../opentofu/bootstrap/catalog.tf), [`opentofu/bootstrap/variables.tf`](../../opentofu/bootstrap/variables.tf), [`oci/catalog/argocd-image-updater/resourceset.yaml`](../../oci/catalog/argocd-image-updater/resourceset.yaml)

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

## ARGOCD-IMAGE-UPDATER-08: On gcp, Artifact Registry Reader on the project, its token from the metadata server

**proposed** · 2026-10-16 · [`oci/clusters/gcp/argocd-image-updater/patch.yaml`](../../oci/clusters/gcp/argocd-image-updater/patch.yaml), [`oci/catalog/argocd-image-updater/tests/e2e/chainsaw-test.yaml`](../../oci/catalog/argocd-image-updater/tests/e2e/chainsaw-test.yaml)

**Context.** ARGOCD-IMAGE-UPDATER-04 has no gcp shape: on gcp the module
falls under ARGOCD-IMAGE-UPDATER-05, the client's credential. The socle has
no Google service account there, and Crossplane grants a role only under the
foundations' `modifiedGrantsByRole.hasOnly()` condition
([GCP-14](gcp.md#gcp-14-workload-identity-federation-direct-principals-no-google-service-account)).
Artifact Registry grants roles per repository, and the `provider-gcp-artifact`
family member has the kind for it (`RegistryRepositoryIAMMember`, v3.0.0),
but Artifact Registry recognises neither
`iam.googleapis.com/modifiedGrantsByRole` nor `resource.name` in IAM
conditions: a Crossplane allowed to set a repository's IAM policy could grant
itself, or anyone, writer or admin on every repository of the project, and
push the images the cluster runs. A project grant of
`roles/artifactregistry.reader` stays under the condition, and reaches every
repository of the project; the socle already runs one cluster per project.

Artifact Registry takes an OAuth access token as a password, user
`oauth2accesstoken`, on `LOCATION-docker.pkg.dev`, one host per location, and
supports federated identities with no listed limitation. The GKE metadata
server exchanges the pod's ServiceAccount token for such a token, valid one
hour and cached, without saying how much of the hour is left. Image Updater
has no Google code: an `ext:` credential runs a script, kills it after 10
seconds, splits its output on the first `:`, and runs it again once
`credsexpire` has passed or at once after a 401 or 403. Its v1.3.0 image is
Alpine with busybox `wget` and `sed`, and neither `curl` nor `gcloud`. It
matches an image's host exactly before any longer prefix, and registers an
anonymous entry for a host no entry covers, which then wins over an entry
whose prefix is a path.

**Decision.** On gcp, `kube.argocd_image_updater.repositories` names
Artifact Registry repositories of the cluster's project as
`LOCATION/REPOSITORY` (`europe-west1/apps`). With it not empty and Crossplane
on, gcp's step declares a `ProjectIAMMember` granting
`roles/artifactregistry.reader` on the project to the principal
`…/subject/ns/argocd-image-updater/sa/argocd-image-updater`, and the chart
waits for it to be Ready. The socle mounts a login script printing
`oauth2accesstoken:<token>` from the metadata server, and writes one registry
entry per location named, prefix `LOCATION-docker.pkg.dev`, re-run every 5
minutes, before the client's `registries`. No key, no Google service account.
If accepted, this decision replaces ARGOCD-IMAGE-UPDATER-05 for gcp; with
`repositories` empty, gcp keeps the client's credential.

**Consequences.** The client adds `roles/artifactregistry.reader` to the
foundations' `crossplane.allowed_roles`; without it the member fails at IAM,
the reason on its `Synced` condition. The names in `repositories` choose the
hosts, not what the role reaches: the controller reads every repository of
the project, and one outside it wherever its owner grants that principal the
role. An image of a location named, in another project, takes the socle's
entry, and `tofu plan` refuses a client entry for that host, as
ARGOCD-IMAGE-UPDATER-07 does for ECR. Measured on the sandbox GKE
Autopilot, 2026-10-16 (artifact `0.0.0-feat-gcp-parity.d896756`): Artifact
Registry's Docker endpoint accepts the metadata server's federated token,
and Image Updater listed the tags of the private repository
`europe-west1-docker.pkg.dev/sandbox-2bace/socle-e2e/podinfo` and moved the
Application from 6.9.0 to 6.9.4; the GKE e2e
(`argocd-image-updater-module-gke`), binding and its propagation included,
passed in 70 s.

**Sources.** [Artifact Registry access control](https://docs.cloud.google.com/artifact-registry/docs/access-control); [Artifact Registry Docker authentication](https://docs.cloud.google.com/artifact-registry/docs/docker/authentication); [IAM conditions attribute reference](https://docs.cloud.google.com/iam/docs/conditions-attribute-reference); [Resource attributes for IAM conditions](https://docs.cloud.google.com/iam/docs/conditions-resource-attributes); [Set limits on granting roles](https://docs.cloud.google.com/iam/docs/setting-limits-on-granting-roles); [Identity federation: products and limitations](https://docs.cloud.google.com/iam/docs/federated-identity-supported-services); [About Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity); `registry-scanner/pkg/image/credentials.go`, `registry-scanner/pkg/registry/endpoints.go` and `registry.go`, and the `Dockerfile`, in Image Updater v1.3.0; the GKE Autopilot sandbox run of 2026-10-16.
