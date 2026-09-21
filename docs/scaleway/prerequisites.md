# Scaleway — prerequisites

What must exist on your Scaleway Organization before `tofu apply` can run the
socle foundations module. The module creates none of it.

Each item can be done by hand in the console — nothing is provided for that
path — or from the command line. The commands for every item are gathered in
[By command line](#by-command-line) at the end. The permission sets the apply
itself needs are listed in
[the minimal example](../../opentofu/scaleway/examples/minimal/README.md).

Two things are different here from the other clouds, and both bite early:
**there is nothing to enable, and almost everything is gated on quota.**

## Account

- A Scaleway Organization with a **validated payment method**.
- **A validated identity.** Without it, most production instance types have
  no quota at all — not a low quota, none — and the apply fails while
  building a pool.
- **One Project per environment.** The module takes `project_id` as a
  required input because the Project is the only boundary Scaleway offers for
  both IAM and cost attribution: there are no per-resource IAM conditions
  outside IAM, Key Manager and Secret Manager, and consumption carries no
  tags.

## Nothing to enable

Scaleway has no API-enablement step. Every product is reachable as soon as
the Organization exists and identity is validated. There is no equivalent of
`gcloud services enable`, and nothing to forget.

## Quota

**This is the blocker.** Scaleway quotas are per instance type and sit below
what a production socle needs.

| Quota | Default, identity validated | The reference estate wants |
| --- | --- | --- |
| `COMPUTE3-X8C-16G` | **not published** | **4 in production** |
| `POP2-HC-8C-16G`, the shape it replaces | 2 | 4 |
| Kapsule clusters | 40 | 1 per environment |
| Kapsule with a dedicated control plane 4 or 8 | **4** | 1 per production cluster |
| Public Gateways per Organization | 50 | 2 per cluster |
| Private Networks per Public Gateway | 10 | 1 |
| Load Balancers | 50 | 1 per cluster |

- The quota table has **no figure at all for the Zen 5 generation**
  (`COMPUTE3`, `STANDARD3`, `BASIC3`), so read the real number from the
  console before the first apply rather than assuming.
- Raising a quota is a **support ticket**. No API, no Terraform resource,
  no self-service. Open it days before you need it.
- The dedicated control plane quota caps the offer at **four production
  clusters** per Organization before another ticket.

## Permission sets on the principal running OpenTofu

| Permission set | Grants |
| --- | --- |
| `KubernetesFullAccess` | the cluster, its pools and its ACL |
| `VPCFullAccess` | the VPC |
| `PrivateNetworksFullAccess` | the cluster's Private Network |
| `VPCGatewayFullAccess` | the Public Gateways and their flexible IPs |
| `IPAMFullAccess` | the gateways' private address reservations |
| `InstancesFullAccess` | the placement groups and the security groups |
| `IAMManager` | the Crossplane application, its policy and its key |
| `ObservabilityFullAccess` | the query-only Cockpit token |
| `ObjectStorageFullAccess` | creating the state bucket — one-time, and not needed by the apply principal afterwards |

`IAMManager` is **Organization-scoped by nature** and is the broadest thing
required here. `IAMApplicationManager` and `IAMPolicyManager` cover the
application and the policy; whether they also cover creating that
application's API key is worth verifying against your own Organization before
relying on the narrower pair.

## Credentials

An API key — an access key and a secret key — reachable by the provider
through `SCW_ACCESS_KEY` and `SCW_SECRET_KEY`.

**There is no federated alternative.** Scaleway has no workload identity
federation and no OIDC trust for CI, so the runner holds a long-lived
credential, and so does the in-cluster Crossplane provider the module
creates. This is the cloud where "no keys, ever" is not an available
position. What is available:

- **Bind the key to the runner's egress address** with an IAM policy
  condition. Request-level conditions work on every product, unlike
  resource-level ones.
- **Set an expiry** on the key, so rotation is forced rather than intended.
- Give the key to an IAM **application**, never to a user.

## State

An Object Storage bucket, versioning on, created before the first
`tofu init`. The module ships no backend block; state lives in your own
account, so declare it in your root configuration:

```hcl
terraform {
  backend "s3" {
    bucket                      = "my-tofu-state"
    key                         = "socle/scaleway/terraform.tfstate"
    region                      = "fr-par"
    endpoints                   = { s3 = "https://s3.fr-par.scw.cloud" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
```

**Nothing else is needed for locking.** Scaleway Object Storage implements S3
conditional writes (`If-Match`, `If-None-Match`), which is exactly what
`use_lockfile` uses — so there is no DynamoDB equivalent to provision.

## Tooling

- OpenTofu 1.10 or later.
- `scw` CLI, initialised.
- The `aws` CLI for the bucket settings `scw` does not expose — lifecycle
  rules and bucket policies.

## Good practices

Per resource, what to do beyond simply creating it.

### Organization and Projects

- One Project per cluster and per environment. A shared Project makes an IAM
  mistake estate-wide, and makes the cost export unattributable — there are
  no tags on consumption to fall back on.
- Validate identity before anything else. Half the quota table is
  inaccessible without it, and the failure appears only when a pool is built.
- Never reuse a Project that has held a cluster until its state is archived.

### Billing

- A **billing alert** with thresholds on the Organization. Nodes bill whether
  or not anything schedules on them, because the cluster-autoscaler never
  consolidates — an over-sized `pool_min_size` is silent otherwise.
- Savings plans are a commercial decision, never a module default: compute
  only, 12 or 36 months, billed in full even when unused, and neither
  cancellable nor exchangeable.

### Quota

- Raise quotas at onboarding, as a checklist item, not when an apply fails.
- **Do not try to watch quota consumption.** Scaleway exposes no quota metric
  in Cockpit, so unlike GCP there is nothing to alert on. The control is the
  checklist; the symptom is a failed apply.

### Permission sets

- A dedicated IAM **application** for OpenTofu, with its own key, rather than
  a key belonging to a human.
- Scoped to the target Project on every rule that can be — which is all of
  them except `IAMManager`.
- Never `AllProductsFullAccess`. The module refuses it for the Crossplane
  identity by validation, and the same reasoning applies to the runner.
- One key per pipeline, so revoking one does not stop the others.

### Credentials

- An IP condition on the runner's policy, pinned to the CI egress.
- An expiry on every key, and a rotation the pipeline can actually perform.
- Never commit a key; the module accepts none as input and emits its own as a
  sensitive output.

### State bucket

State holds every attribute of every resource, secrets included — and on this
cloud that includes the Crossplane secret key. Losing the bucket means the
cluster exists but is no longer manageable.

- **Versioning on before the first write.**
- Server-side encryption with Key Manager (SSE-KMS).
- A bucket policy restricting access to the runner's egress addresses.
- **Object Lock belongs on a Velero bucket, not on this one** — WORM would
  make a legitimate state rewrite impossible.
- A lifecycle rule that can never touch a live object: expire only
  non-current versions, and only old ones.
- Same region as the cluster, one key prefix per environment, never shared
  with application data.

## By command line

Set the variables once:

```sh
ORG_ID=33333333-3333-3333-3333-333333333333
PROJECT_NAME=socle-prod
REGION=fr-par
STATE_BUCKET=my-tofu-state
RUNNER_CIDR=203.0.113.10/32   # the CI runner's egress address
```

Initialise the CLI, if it is not already:

```sh
scw init
```

Create the Project for this environment, and keep its ID:

```sh
scw account project create name="$PROJECT_NAME" organization-id="$ORG_ID"
PROJECT_ID=$(scw account project list name="$PROJECT_NAME" -o json | jq -r '.[0].id')
```

When it already exists, find it instead:

```sh
scw account project list
```

An application for OpenTofu, and its policy. `IAMManager` is
Organization-scoped; everything else is confined to the Project:

```sh
APP_ID=$(scw iam application create name=socle-tofu -o json | jq -r '.id')

scw iam policy create \
  name=socle-tofu \
  application-id="$APP_ID" \
  rules.0.project-ids.0="$PROJECT_ID" \
  rules.0.condition="request.ip in ['$RUNNER_CIDR']" \
  rules.0.permission-set-names.0=KubernetesFullAccess \
  rules.0.permission-set-names.1=VPCFullAccess \
  rules.0.permission-set-names.2=PrivateNetworksFullAccess \
  rules.0.permission-set-names.3=VPCGatewayFullAccess \
  rules.0.permission-set-names.4=IPAMFullAccess \
  rules.0.permission-set-names.5=InstancesFullAccess \
  rules.0.permission-set-names.6=ObservabilityFullAccess \
  rules.1.organization-id="$ORG_ID" \
  rules.1.condition="request.ip in ['$RUNNER_CIDR']" \
  rules.1.permission-set-names.0=IAMManager
```

Its key, with an expiry so rotation is forced:

```sh
scw iam api-key create \
  application-id="$APP_ID" \
  description="OpenTofu runner — socle foundations" \
  expires-at="$(date -u -d '+1 year' +%Y-%m-%dT%H:%M:%SZ)" \
  default-project-id="$PROJECT_ID"
```

Export it for the provider:

```sh
export SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX
export SCW_SECRET_KEY=...
export SCW_DEFAULT_ORGANIZATION_ID="$ORG_ID"
export SCW_DEFAULT_PROJECT_ID="$PROJECT_ID"
```

The state bucket, with versioning on from the start:

```sh
scw object bucket create "$STATE_BUCKET" region="$REGION"
scw object bucket update "$STATE_BUCKET" enable-versioning=true acl=private region="$REGION"
```

The parts `scw` does not expose. Point the `aws` CLI at Scaleway first:

```sh
aws configure set aws_access_key_id "$SCW_ACCESS_KEY" --profile scw
aws configure set aws_secret_access_key "$SCW_SECRET_KEY" --profile scw
aws configure set region "$REGION" --profile scw
S3="aws --profile scw --endpoint-url https://s3.$REGION.scw.cloud"
```

A lifecycle that never touches a live object — only non-current versions over
a year old:

```sh
cat > lifecycle.json <<'JSON'
{
  "Rules": [
    {
      "ID": "expire-old-noncurrent-state",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 365 }
    }
  ]
}
JSON
$S3 s3api put-bucket-lifecycle-configuration \
  --bucket "$STATE_BUCKET" --lifecycle-configuration file://lifecycle.json
```

Then point the backend at it and initialise:

```sh
tofu init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=socle/scaleway/terraform.tfstate" \
  -backend-config="region=$REGION"
```

Finally, **open the quota ticket** — there is no command for it:

```
https://console.scaleway.com/support/tickets/create
```

Ask for the node type the module will use, at the count `pool_max_size`
allows times the number of zones, plus one dedicated control plane per
production cluster.
