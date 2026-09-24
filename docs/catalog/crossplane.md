# Catalog module `crossplane` — how every module carries its own cloud IAM

Crossplane is in the socle for one reason: **a catalog module that needs a
cloud service declares its own role**, for each cloud it runs on, beside its
workload — instead of the foundations growing one optional IAM block per
consumer. external-dns needs to write DNS records, so the `external_dns`
module itself declares, on AWS, an IAM role with a Route 53 policy and the
Pod Identity association binding it to its ServiceAccount.

The `crossplane` module is only the **tooling**: Crossplane, and per cloud the
IAM providers and their `ProviderConfig`. It names no module and carries no
module's permissions — **a new module that needs cloud access never changes
it**. The foundations keep exactly one identity: Crossplane's own, fenced by a
permissions boundary.

This pull request is the first working instance, on AWS only: the module, the
foundations' Crossplane identity, and an e2e that turns a module-shaped role
into a real IAM role on floci. The GCP, Azure and Scaleway branches, and the
external-dns migration, are each meant to be a small PR written from this note.

| Question | Position |
| --- | --- |
| What a module declares | Its own managed resources, per cloud: on AWS an `iam.aws.m.upbound.io` `Role` and an `eks.aws.m.upbound.io` `PodIdentityAssociation` — the contract in §3 |
| What `crossplane` installs | Core; on AWS `provider-{family-aws,aws-iam,aws-eks}` v2.8.1 and `ClusterProviderConfig default` on Pod Identity. No XRD, no Composition, nothing per module |
| What the foundations still owe | Crossplane's identity, and the **permissions boundary** every module role must carry: an allowlist of services the client writes, empty by default — `opentofu/aws` variable `crossplane` |
| How a module waits | Its `ResourceSet` `dependsOn` the `crossplane` ResourceSet and uses `steps`: its role first, health-checked Ready, then its workload |
| Crossplane off | The module takes a pre-made identity by name (`kube.<module>.identity`); neither → refused at plan |
| Default | `enabled = false` — argued in §6 |
| Chart | `crossplane` 2.4.2 from `https://charts.crossplane.io/stable` — **no OCI chart exists upstream** |

## 1. The ordering chain, end to end

Crossplane needs a cloud identity to create IAM, and only OpenTofu can grant
that first one. Everything after it is the cluster's.

| # | Link | Where it lives | Cold-cluster cost |
| --- | --- | --- | --- |
| 1 | Cluster, Crossplane's IAM role, the boundary, the Pod Identity association `crossplane-system/provider-aws` | `opentofu/aws` (`crossplane = {…}`), the client's one apply | part of the apply (~70 s on floci for the whole real root; minutes on real EKS, dominated by the cluster) |
| 2 | Cilium, CoreDNS (aws, azure) | the bootstrap module, a `helm_release` before flux-operator (PR #37) | PR #37's figure |
| 3 | Pod Identity Agent | **delegated to the factory** (`docs/aws/eks-managed-scope.md` §1) — open question 3 | EKS add-on, seconds |
| 4 | Flux | `opentofu/bootstrap`: operator, instance, envelope | ~60 s (`docs/flux-catalog.md` §11) |
| 5 | Crossplane core | `oci/catalog/crossplane`, step `core` | 14 s (k3s, `helm install --wait`) |
| 6 | AWS providers | step `providers` | ~90 s until Healthy (k3s, images pulled cold) |
| 7 | `ClusterProviderConfig default` (Pod Identity) | step `config`: a child ResourceSet gated on the providers' `Healthy` | ~10 s after 6 |
| 8 | A module's role and association | the module's own ResourceSet, step `access` | role Ready 3–6 s on floci; the association is not measurable there |
| 9 | The module's workload | the module's own ResourceSet, step `workload` | the chart's own |

Measured end to end through Flux on floci's k3s: **the `crossplane`
ResourceSet Ready 99 s after it was applied** (links 5–7), then a role reached
floci's IAM in 3–6 s. On a cold real cluster, links 5–9 add roughly two
minutes to the first convergence; a warm cluster adds only link 8.

Why each link sits where it does:

- **Link 1 is the only one OpenTofu can own**: it is the only one that cannot
  be created from inside the cluster without already having an identity. Both
  halves are known before the cluster has a node — the module runs every AWS
  provider pod as `crossplane-system/provider-aws`, a fixed
  `serviceAccountTemplate` name in its `DeploymentRuntimeConfig` (Crossplane
  otherwise names the ServiceAccount after a revision hash) — so the
  association is written in the same apply, and the provider pods get their
  credentials the moment they start.
- **Links 5 → 6 → 7 are one `ResourceSet` with `spec.steps`** (flux-operator
  v0.60.0: each step applied and health-checked before the next). Step 6
  needs the core's CRDs, which the core applies itself at start; step 7 needs
  the providers' CRDs, which exist only once they are Healthy. The operator's
  health check reads `Ready`, and Crossplane packages report `Healthy` — so
  step 7 is a **child ResourceSet** with `dependsOn` and `readyExpr:
  status.conditions.exists(c, c.type == 'Healthy' && c.status == 'True')` on
  each provider, and step 7 waits for that child. When the module is off the
  child goes with the rest, so a dependency on an absent Provider can never
  wedge `socle-root`.
- **Link 8 must finish before link 9 starts, on AWS.** The EKS Pod Identity
  webhook injects credentials at pod admission, and only if the association
  already exists: a pod admitted before its association never gets
  credentials until it is recreated. That rules out "let the pod fail until
  the role appears" (it would self-heal on GKE and AKS, not here) — §4.

## 2. What the foundations still owe — `opentofu/aws`

```hcl
# opentofu/clusters/aws, in the client's tfvars
aws = {
  …
  crossplane = { allowed_services = ["route53"] }
}
kube = {
  crossplane = { enabled = true }   # permissions_boundary is wired by the root
}
```

| Object | What it is |
| --- | --- |
| variable `crossplane` | `object({ allowed_services = optional(list(string), []) })`, default `null` — nothing is created |
| `aws_iam_policy.crossplane_boundary` | `/socle/<cluster>/crossplane-boundary`: `<service>:*` allowed for each listed service, and **always** an explicit deny of `iam:*`, `sts:*`, `organizations:*`, `account:*`, `sso:*`, `identitystore:*`. Empty list: only the deny — a module role grants nothing |
| `aws_iam_role.crossplane` | `<cluster>-crossplane`, at `/`, trusted by `pods.eks.amazonaws.com` |
| `aws_iam_role_policy.crossplane` | what it may do, below |
| `aws_eks_pod_identity_association.crossplane` | `crossplane-system/provider-aws` |
| output `crossplane_permissions_boundary_arn` | wired by the root into `kube.crossplane.permissions_boundary` (a value the client writes wins — PR #36's pattern) |
| output `crossplane_role_arn` | for the record |

**Why an allowlist of services, empty by default.** It is the strictest
boundary that keeps the rule "a new module never changes the socle's code":
the boundary names **services**, not resources — which zone, which bucket is
each module's own role policy — so a module that uses a service already
allowed needs nothing, and one that uses a new service needs one word in the
client's tfvars, a reviewed change to what the cluster may ever touch.
`iam`, `sts`, `organizations`, `account`, `sso` and `identitystore` are refused
in the list at plan and denied in the document regardless: no role Crossplane
creates can mint identities, chain into another role, or reach the
organisation.

**Blast radius, argued.** An identity that can create IAM roles is the most
powerful thing in the cluster. Crossplane's policy allows:

- `iam:CreateRole`, `PutRolePermissionsBoundary`, `PutRolePolicy`,
  `UpdateAssumeRolePolicy` **only on `role/socle/<cluster>/*` and only when
  `iam:PermissionsBoundary` equals our boundary** — the condition is evaluated
  on each of those calls, so a role without it, or with another, can be
  neither created nor written;
- read, tag and delete on the same path; `iam:PassRole` on the same path to
  `pods.eks.amazonaws.com` only; the Pod Identity association calls on this
  cluster's ARN only.

Refused, by omission: `AttachRolePolicy` (no managed policies, so no
`AdministratorAccess`), `DeleteRolePermissionsBoundary`, any policy creation
or versioning — the boundary cannot be edited — and anything on a role outside
the path, its own included (it lives at `/`). What IAM **cannot** bound is a
role's trust policy: there is no condition key on the document, so a
compromised Crossplane could create a role, inside the boundary, that another
principal may assume. The boundary is the answer: such a role is worth exactly
the allowed services, never an identity or an account change. The residual
risk is inside those services — a role may be given `route53:*` on every zone
of the account; the module's review, not the foundations, keeps it to the
zones it needs. `opentofu/aws/tests/defaults.tftest.hcl` asserts each of these
properties on the planned documents.

What the other clouds will owe, one `crossplane` variable each:

- **GCP.** The pool exists (Autopilot; outputs `workload_identity_pool`,
  `workload_identity_principal_prefix`). Crossplane's principal
  `…/ns/crossplane-system/sa/provider-gcp` gets the right to set IAM policy on
  resources only — never the project's own policy, the GCP equivalent of an
  unbounded role — restricted by an IAM condition to the roles the client
  allows (`api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', [])
  .hasOnly([...])`: GCP's boundary). A module then binds its own principal
  (`…/ns/external-dns/sa/external-dns`) on its own resources: no Google
  service account. `ProviderConfig`: `credentials.source: InjectedIdentity`.
  Caveat from the output's description: two clusters in one project share the
  principal.
- **Azure.** `opentofu/azure` already enables workload identity and the OIDC
  issuer. Crossplane gets a user-assigned identity federated to
  `system:serviceaccount:crossplane-system:provider-azure`, Managed Identity
  Contributor on one dedicated resource group (where modules' identities and
  federated credentials are created), and Role Based Access Control
  Administrator **with an ABAC condition restricting the assignable roles to
  the client's list** — Azure's constrained delegation is the boundary.
  `ProviderConfig`: `credentials.source: OIDCTokenFile`.
- **Scaleway — the key that exists.** No federation; `opentofu/scaleway`
  already mints the Crossplane application, its Project-scoped policy with the
  source-IP condition, and the key. A module's access there is an IAM
  application, a policy and a key delivered as a connection Secret in its
  namespace. **The weakest of the four**: Scaleway IAM has no boundary, so
  Crossplane can hand out any permission set its own policy holds
  (`crossplane_permission_sets`). Open for that PR: how Crossplane's key
  reaches `crossplane-system` without a `kubernetes` provider and without
  transiting `kube` — most likely a Secret the client creates from the
  sensitive output, like `artifact_pull_secret`.

## 3. What a module declares — the AWS contract

A module that needs AWS access renders, in its own ResourceSet, under
`<< if eq inputs.cloud "aws" >>`:

```yaml
apiVersion: iam.aws.m.upbound.io/v1beta1
kind: Role
metadata:
  name: external-dns
  namespace: external-dns
  annotations:
    # IAM names are account-wide and two clusters may share an account.
    crossplane.io/external-name: << inputs.cluster.name >>-external-dns
    fluxcd.controlplane.io/reconcile: << if inputs.modules.external_dns.enabled >>enabled<< else >>disabled<< end >>
spec:
  forProvider:
    path: /socle/<< inputs.cluster.name >>/                        # the only path Crossplane may write
    permissionsBoundary: << inputs.modules.crossplane.permissions_boundary >>  # refused by IAM without it
    assumeRolePolicy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}'
    inlinePolicy:                                                  # the module's own, least privilege
      - name: route53
        policy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["route53:ChangeResourceRecordSets","route53:ListResourceRecordSets"],"Resource":["arn:aws:route53:::hostedzone/<zone>"]}, …]}'
---
apiVersion: eks.aws.m.upbound.io/v1beta1
kind: PodIdentityAssociation
metadata:
  name: external-dns
  namespace: external-dns
  annotations: { fluxcd.controlplane.io/reconcile: … }
spec:
  forProvider:
    region: << inputs.cluster.region >>
    clusterName: << inputs.cluster.name >>
    namespace: external-dns
    serviceAccount: external-dns
    roleArnRef: { name: external-dns }
```

The rules, all enforced somewhere:

- **Path `/socle/<cluster>/`, boundary `inputs.modules.crossplane.permissions_boundary`**:
  anything else is refused by IAM through Crossplane's own policy.
- **Inline policy only**: Crossplane cannot attach managed policies.
- **The module scopes resources itself** (the zones from its own `kube`
  attributes, say), because the boundary scopes only services.
- **One role per module per cloud**, named `<cluster>-<module>`; the
  `ClusterProviderConfig default` is implied (`providerConfigRef` omitted).
- `inputs.cluster.region` exists for the association: the bootstrap module
  gains a `region` variable, which the root fills from `aws.region`.

Why raw managed resources and not a Composition/XRD owned by `crossplane`: a
shared abstraction puts every module's permissions into this module — each
new need would change it, which is exactly what the socle refuses. With raw
resources the module owns its whole cloud surface, in its own file, reviewed
with it; the cost is about twenty lines of YAML per module per cloud, and the
contract above keeps them uniform. Where the lines live: in the module's own
template, one branch per cloud in its `access` step — the module's IAM stays
next to the module, and a cloud without a branch simply has no role.

## 4. How a module waits for its role

**Chosen: `dependsOn` the `crossplane` ResourceSet, and `steps` in the module's
own ResourceSet — `access` (ServiceAccount, Role, association), then
`workload`.**

- `dependsOn` a ResourceSet that always exists (`crossplane`, Ready trivially
  when off) guarantees the providers' CRDs before the module applies its
  role, and never blocks when Crossplane is off.
- The `access` step is health-checked: managed resources carry a `Ready`
  condition, which the operator's health check reads. The workload's pods are
  therefore admitted after the association exists — the only order that works
  with Pod Identity (§1).
- **Degrading honestly**: a role that never turns Ready (boundary refused,
  service not in the allowlist) makes the step time out; the module's
  ResourceSet reports `step "access"` not ready and `socle-root` stays not
  Ready — the one object CI and a client read (`docs/flux-catalog.md` §9).
  Nothing is half-deployed.

Refused: Flux `HelmRelease.dependsOn` (it only references other HelmReleases);
the pod failing until the role appears (never recovers on EKS); a Job gate (an
image, RBAC and a poll loop for what `steps` does natively).

## 5. When Crossplane is off — the escape hatch

`kube.<module>.identity` (PR #36's attribute) **survives as the escape hatch**:
a non-empty value means "the client made the identity himself" — the module
renders no role, only its ServiceAccount (annotated where the cloud needs it:
the client ID on Azure). A module that needs cloud access with Crossplane off
**and** no `identity` is **refused at plan** by a validation in
`opentofu/bootstrap/variables.tf` naming both ways out. A client who does not
want Crossplane is told: create each module's identity in your own
infrastructure code (on AWS a role and a Pod Identity association for the
module's fixed ServiceAccount) and pass its name. The socle's foundations no
longer mint per-module identities — PR #36's `aws.external_dns` block and its
siblings go away.

## 6. Whether `enabled` stays `false`

**It stays `false` in this PR**: no catalog module declares a role yet; the
foundations' Crossplane identity is itself opt-in (`aws.crossplane = null`),
so an on-by-default Crossplane would run providers that cannot authenticate;
and on AWS it costs ~1.1 GB of memory idle, ~2 GB just after install (§7). "A module needing cloud access
implies Crossplane" is enforced as a **plan-time error** in that module, not
as a hidden default. The root adds a `check` that warns when
`kube.crossplane.enabled` is set without `aws.crossplane`. Revisit when a
module that needs cloud access defaults on — that PR flips both defaults.

## 7. What was measured, and what floci cannot prove

| | Result |
| --- | --- |
| Render (`flux-operator build rset`, `oci/.ci/inputs-sample.yaml`) | aws: 10 objects in three steps; gcp: the 5 of `core`, the other steps empty; `enabled = false`: none |
| kubeconform strict | rendered and raw, `fluxcd.controlplane.io` kinds against flux-operator v0.60.0's own schemas (the datree catalog's `ResourceSet` predates `spec.steps`; `pr-static.yaml` now fetches `crd-schemas.tar.gz` from the release it already installs) |
| Flux on floci's k3s, local | `crossplane` ResourceSet Ready 99 s cold; the client's `resourcesRBACManager.requests.memory = 48Mi` beats the socle's 32Mi on the live Deployment; the chart's limits gone |
| Role → IAM, local | Ready in 3–6 s; `aws iam get-role` shows `/socle/<cluster>/`, the Pod Identity trust and the inline policy; deleted → gone from IAM in 1–2 s |
| Off, local | namespace gone in 18 s. **Left behind**: 21 Crossplane CRDs, 71 provider CRDs, the `crossplane-no-usages` webhook configuration (it matches only objects labelled `crossplane.io/in-use`, which then cannot be deleted by hand) |
| Back on, local | ~5 min: the providers re-adopt their leftover CRDs slowly (3.5 min to Healthy, against 89 s cold) |
| Memory with the AWS providers | core 109–138Mi, RBAC manager 17–21Mi, `provider-family-aws` 306–401Mi, `provider-aws-iam` 323–441Mi, `provider-aws-eks` 327–374Mi — ~1.1 GB. Requests: core 50m/128Mi, RBAC manager 10m/32Mi, providers 50m/320Mi each (one `DeploymentRuntimeConfig`), no limits |
| e2e, CI (`e2e-aws-catalog`, step "Crossplane turns on, turns a module's Role into an IAM role, turns off"; [run 35903123437](https://github.com/do-now-io/socle/actions/runs/35903123437)) | `crossplane` Ready **58 s** after the apply returned; the client's 48Mi on the live Deployment, no limits; module-shaped Role → IAM role under `/socle/socle-e2e-catalog/` in **62 s**, gone 32 s after its deletion; association `Synced=False` as expected; off → HelmRelease gone. Memory right after install: core 148Mi, providers 550–662Mi each (~2 GB, settling towards the local ~1.1 GB). **Job: 6m24s**, up from 3m35s |

Local measurements were taken on an earlier revision that also installed two
functions for a Composition since removed; they changed none of the figures
above but the ~40Mi they cost.

**floci's limits, stated plainly.** floci implements IAM, so the provider and
a module-shaped role are proven for real. It does **not** implement the EKS
Pod Identity association API (the provider gets a 404 HTML page), so the
association is not provable there; and it **ignores `PermissionsBoundary`** at
`CreateRole` — even `aws iam create-role --permissions-boundary` returns none —
and enforces no IAM policy at all, so neither the boundary nor Crossplane's
conditions are proven. Those are covered by the plan-time tests on the
documents, and eventually a real account. The seam: the socle's
`ClusterProviderConfig default` is on Pod Identity, which floci does not run,
so the e2e creates a second one, `floci` (static test keys, floci's endpoint
for `iam`, `eks`, `sts`), and its module-shaped resources name it.

**The values precedence, found on the way.** §6 of `docs/flux-catalog.md` says
the client's values win, and the argocd module puts the socle's defaults in
the `HelmRelease`'s `.values`. helm-controller merges `.values` **last**, over
every `valuesFrom` entry (`fluxcd/pkg` `chartutil.ChartValuesFromReferences`:
"the values map is merged in last overwriting values from references"). This
module therefore renders the socle's values into a `crossplane-socle-values`
ConfigMap listed first under `valuesFrom`, then the client's, then his Secret,
with no `.values`; the e2e asserts the client's value on the live Deployment.
The same fix applies to argocd and to §6's wording.

## 8. The external-dns migration, as a diff sketch

```diff
# opentofu/aws — the per-consumer block goes; the service joins the allowlist
-variable "external_dns" { type = object({ zone_ids = list(string) }) … }
-resource "aws_iam_role" "external_dns" …
-resource "aws_iam_role_policy" "external_dns" …
-resource "aws_eks_pod_identity_association" "external_dns" …
-output "external_dns_role_arn" …
# the client's tfvars
-  external_dns = { zone_ids = ["Z…"] }
+  crossplane   = { allowed_services = ["route53"] }
 kube = {
-  external_dns = { domain_filters = ["acme.example"] }
+  crossplane   = { enabled = true }
+  external_dns = { domain_filters = ["acme.example"], zone_ids = ["Z…"] }   # the module scopes its own policy
 }

# opentofu/clusters/aws/main.tf
-  external_dns_identity = … module.foundations.external_dns_role_arn …

# opentofu/bootstrap — zone_ids joins external_dns's schema, plus one validation
+  validation {
+    condition = !try(local.modules.external_dns.enabled, false)
+      || local.modules.external_dns.identity != ""
+      || local.modules.crossplane.enabled
+    error_message = "kube.external_dns needs cloud access: set kube.crossplane.enabled = true (and aws.crossplane in the foundations), or pass a pre-made identity in kube.external_dns.identity."
+  }

# oci/catalog/external-dns/resourceset.yaml — resources: becomes steps:
 spec:
+  dependsOn:
+    - { apiVersion: fluxcd.controlplane.io/v1, kind: ResourceSet, name: crossplane, namespace: flux-system, ready: true }
-  resources: [Namespace, HelmRepository, HelmRelease, ConfigMap]
+  steps:
+    - name: access
+      resourcesTemplate: |
+        Namespace, ServiceAccount external-dns
+        << if and (eq inputs.cloud "aws") (not inputs.modules.external_dns.identity) >>
+        Role + PodIdentityAssociation, exactly §3, policy on the zone_ids
+        << end >>
+        # gcp, azure, scaleway: their branch when their crossplane PR lands
+    - name: workload
+      resources: [HelmRepository, ConfigMap, HelmRelease]   # serviceAccount.create: false

# oci/clusters/aws/external-dns-provider.patch.yaml — the index moves
-  path: /spec/resources/2/spec/values/provider
+  path: /spec/steps/1/resources/2/spec/values/provider
```

PR #36's `external-dns-aws` Secret seam for its e2e stays as it is; on floci
its Role needs `providerConfigRef: floci`, which the e2e sets with a one-line
`kubectl patch`, since the module does not render that field.

## 9. Open questions for the coordinator

1. **Values precedence** (§7): confirm this module's shape and carry it to
   argocd and to §6 of `docs/flux-catalog.md`, or revert this module to
   argocd's.
2. **A Helm repository source**, the catalog's first non-OCI chart, unverified
   (Crossplane publishes no chart signature a `HelmRepository` can check), and
   provider packages pulled by tag from `xpkg.crossplane.io`, also unverified
   by Flux. Accept, or mirror chart and packages into the socle's registry?
3. **The Pod Identity Agent** is delegated to the factory in
   `docs/aws/eks-managed-scope.md`, but nothing in the chain works on real EKS
   without it — Crossplane's own credentials included. Should the foundations
   install the add-on when `crossplane` is set?
4. **This reverses a documented position**: `opentofu/aws/iam.tf` said no
   Crossplane identity would be built there, because its ServiceAccount did
   not exist yet. The fixed `serviceAccountTemplate` name removes that reason;
   the comment is rewritten, `docs/aws/eks-managed-scope.md` is not touched.
5. **Cost**: ~1.1 GB idle (~2 GB just after install, measured in CI) on every cluster that enables it. `provider-aws-eks`
   exists only for the associations; recommended to keep it — the alternative,
   the foundations pre-creating one association per module, brings back the
   per-consumer foundations blocks this design removes.
