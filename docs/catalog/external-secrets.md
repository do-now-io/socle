# Catalog module `external_secrets` — Secrets from the cloud's secret manager

Half of #56, with [`reloader`](reloader.md). Without it the client creates
and rotates every Kubernetes `Secret` by hand, out of Git — the
`values_secret` of every module included. External Secrets Operator (ESO)
reads them from the cloud's own secret manager instead, and keeps each
`Secret` in step when the value rotates there; Reloader rolls the pods that
read it.

| Question | Position |
| --- | --- |
| What | The official chart, `oci://ghcr.io/external-secrets/charts/external-secrets:2.11.0` (ESO v2.11.0), one `HelmRelease` in namespace `external-secrets` |
| Default | **Off** |
| Cloud access, aws | With `crossplane` on and a prefix: the module's own **read-only** IAM role, `GetSecretValue` and `DescribeSecret` on `secret:<prefix>/*` in the cluster's region, Pod Identity on `external-secrets/external-secrets` |
| Store | One `ClusterSecretStore`, `secret-manager`, on that role, aws only. Per-namespace `SecretStore`s and other backends are the client's |
| Prefixes | `[<cluster name>]` by default, a list; `[]` means no role and no store |
| Other clouds, or Crossplane off | The operator alone; the client brings his stores |
| CRDs | Kept on uninstall (`helm.sh/resource-policy: keep`) |
| Write access | None: `PushSecret` and `ClusterPushSecret` are not reconciled |
| Pod security | `restricted`, enforced on the namespace |
| Client surface | `enabled`, `prefixes`, `values`, `values_secret` |

## What is installed

When enabled, three layers, each applied once what it needs exists:

1. **The `external-secrets` ResourceSet**, `dependsOn` the `crossplane` one:
   the `Namespace`, labelled `pod-security.kubernetes.io/enforce: restricted`,
   and on aws with Crossplane on and a prefix, the `Role` and the
   `PodIdentityAssociation` of `docs/catalog/crossplane.md` §3.
2. **`external-secrets-workload`**, a child ResourceSet `dependsOn` the Role
   and the association being Ready (an explicit `readyExpr`: a managed
   resource not yet created has no `Ready` condition, which kstatus reads as
   healthy — measured by external-dns). It holds the `OCIRepository`,
   `external-secrets-socle-values`, `external-secrets-client-values` and the
   `HelmRelease`, with no `spec.values` (`docs/flux-catalog.md` §6). EKS Pod
   Identity injects credentials at admission only: a controller pod admitted
   before its association never gets them.
3. **`external-secrets-store`**, a child ResourceSet `dependsOn` the
   `HelmRelease` being Ready, holding the `ClusterSecretStore`: its CRD is one
   the chart installs, and ESO's validating webhook must answer for it to
   apply. Only where the role exists.

The socle's values: `fullnameOverride: external-secrets`; the CRDs installed
and annotated `helm.sh/resource-policy: keep`; the ServiceAccount
`external-secrets` (the role's subject); `processPushSecret` and
`processClusterPushSecret` false; requests 10m / 64Mi and a 256Mi limit on the
controller, 10m / 32Mi and 128Mi on the webhook and the cert controller;
`prometheus.io/scrape` on the controller's metrics port 8080 for
[`otel_gateway`](otel-gateway.md). The chart's own security contexts already
run all three pods non-root, read-only, every capability dropped, with the
`RuntimeDefault` seccomp profile.

The role's policy, for `prefixes = ["acme-prod", "shared/platform"]` in
`eu-west-3`:

```json
{"Version": "2012-10-17", "Statement": [{
  "Sid": "ReadSecretsUnderThePrefixes", "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
  "Resource": ["arn:aws:secretsmanager:eu-west-3:*:secret:acme-prod/*",
               "arn:aws:secretsmanager:eu-west-3:*:secret:shared/platform/*"]}]}
```

The account is `*` because the account id is not among the inputs; a role
can only ever act in the account it lives in, so nothing is widened.

## How a client uses it

```hcl
# opentofu/clusters/aws, in the client's tfvars
aws  = { crossplane = { allowed_services = ["secretsmanager"] } }
kube = {
  crossplane       = { enabled = true }
  external_secrets = { enabled = true }   # prefixes = ["acme-prod"], the cluster's name
  reloader         = { enabled = true }
}
```

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: db, namespace: shop }
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: secret-manager }
  target: { name: db }
  data:
    - secretKey: password
      remoteRef: { key: acme-prod/shop/db, property: password }
---
# the Deployment reading Secret db carries reloader.stakater.com/auto: "true"
```

## Decisions

**The socle creates the store, on aws only.** A store bound to the module's
role is the natural default: the role exists for it, and a client who turns
the module on with Crossplane expects to write an `ExternalSecret` and
nothing else. It is a `ClusterSecretStore` so that every namespace may use it.
Elsewhere — gcp, azure, scaleway, or aws with Crossplane off — the socle has
no identity to bind a store to, so it installs the operator and the client
writes his stores, as KEDA does for its triggers. Each of those clouds gains
its role and its store with its Crossplane provider.

**The prefix, not the store, is the boundary.** A `ClusterSecretStore` can be
fenced to some namespaces (`spec.conditions`), but that fence is cosmetic
here: a namespaced `SecretStore` with no `auth` block falls back to the
controller's own credential chain — the same Pod Identity role — so anyone
allowed to create a `SecretStore` in any namespace reads whatever the role
reads. The chart also aggregates ESO's kinds into the `edit` and `admin`
ClusterRoles. What really bounds the module is therefore IAM: the role reads
`secret:<prefix>/*` and nothing else, and **every namespace that may create
an `ExternalSecret` or a `SecretStore` can read every secret under the
prefixes**. Use one prefix per cluster (the default) and keep other
clusters' and other teams' secrets out of it; a client who needs per-team
isolation turns off the socle's store (`prefixes = []`) and gives each team a
`SecretStore` on its own credentials, or sets `processSecretStore: false` and
`rbac.aggregateToEdit: false` through `values`.

**Prefixes, several.** A list, because a platform's shared secrets
(`shared/platform/*`) rarely live under one cluster's name. The default is
the cluster name, so two clusters in one account never read each other's
secrets unless the client says so. Each entry is validated at plan as a
Secrets Manager name path with no wildcard and no leading or trailing `/`.

**Read-only, two calls.** `GetSecretValue` and `DescribeSecret` are what a
`remoteRef` needs. `ListSecrets` and `BatchGetSecretValue` take no resource
scope — granting them lists every secret name of the account — so they are
left out, and with them `dataFrom.find`. No `kms:Decrypt`: a secret encrypted
with the account's `aws/secretsmanager` key needs none; one on a customer key
needs that key's policy to name the role, which is the key owner's decision.

**CRDs kept.** ESO's CRDs are cluster-wide and the client's objects live in
them: deleting them with the module would delete every `ExternalSecret`, and
every `Secret` whose `ownerReference` is one. Same treatment as the Gateway
API CRDs: `helm.sh/resource-policy: keep`. Turned back on, Helm adopts them
(their release annotations still name this release); measured by the e2e.
The CRDs carry no conversion webhook (`crds.conversion.enabled: false`, the
chart's default), so a kept CRD keeps serving with the operator gone.

**Parameter Store left out.** A second store on `ParameterStore` is the same
role with `ssm:GetParameter*` on `parameter/<prefix>/*`; not in v1, and
`values`-free to add: the client writes the store, the role is the open
question.

## What the e2e proves, and what floci cannot

`oci/catalog/external-secrets/tests/e2e/chainsaw-test.yaml`:

- `health`: off, the ResourceSet Ready with an empty inventory, no namespace;
- `module` (aws, floci), first half, Crossplane off: the operator Available
  in a `restricted` namespace with the PushSecret reconcilers off, the
  client's 96Mi beating the socle's 64Mi, no socle store; a client store on
  static keys Ready; a secret seeded in floci's Secrets Manager under the
  cluster's prefix becomes a `Secret`; the value rotated in floci reaches the
  `Secret`, and **reloader rolls the annotated Deployment reading it** —
  #56's proof; `values_secret` merged last; off, the CRDs still Established;
  back on, the release adopting them; off again;
- `module`, second half, Crossplane on: the Role in floci's IAM under
  `/socle/<cluster>/` with the boundary, a policy that reads
  `secret:<cluster>/*` and neither lists nor writes; the association never
  syncing, so the workload and the socle's store withheld; off, the IAM role
  deleted.

floci implements Secrets Manager (versions, `put-secret-value`) and IAM, but
not the EKS Pod Identity association API, and enforces no IAM policy. So the
socle's own store, `secret-manager`, on Pod Identity, is not provable there,
nor the prefix scope as enforced, nor the boundary. Those are the aws
sandbox's: an `ExternalSecret` from Secrets Manager through `secret-manager`,
a value rotated, the Deployment rolled — and a secret outside the prefix
refused with `AccessDenied`. The seam steps carry floci's names and are
deleted the day floci serves Pod Identity (expected in its next stable).

## What was measured

| | Result |
| --- | --- |
| Render (`flux-operator build rset`, `oci/.ci/inputs-sample.yaml`) | aws with Crossplane: Namespace, Role, PodIdentityAssociation, the two child ResourceSets; Crossplane off, `prefixes = []` or gcp: Namespace and the workload only; kubeconform strict: valid, the nested `ClusterSecretStore` too |
| Chart render with the socle's values | 25 CRDs, each `helm.sh/resource-policy: keep`; controller args `--enable-push-secret-reconciler=false --enable-cluster-push-secret-reconciler=false`; three pods non-root, read-only, `ALL` dropped, `RuntimeDefault` |
| ESO source, v2.11.0 | `AWS_SECRETSMANAGER_ENDPOINT` overrides the endpoint (`providers/v1/aws/secretsmanager/resolver.go`); a store validates by retrieving credentials only, so static keys suffice on floci |
| `tofu test` | the default, four passes, eight refusals |
| e2e, CI (`external-secrets (aws)`, [run 36865489015](https://github.com/do-now-io/socle/actions/runs/36865489015)) | operator on, three Deployments Available, 33 s; client store Ready at once; seeded secret to `Secret` in 2 s; rotation to `Secret` and Reloader's roll in 25 s (`refreshInterval: 10s`); `values_secret` 16 s; off 13 s, CRDs Established; back on adopting them and off again 59 s; Crossplane on, providers Healthy and Role declared 68 s, Role in floci's IAM 68 s; the module's whole suite 6m23s. **Job: 11m56s** |

The first run ([36863814025](https://github.com/do-now-io/socle/actions/runs/36863814025)) proved the rotation and the roll, then failed on a namespace delete that outlived Chainsaw's 15 s default: both tests now give a delete two minutes.
