---
title: Prerequisites
description: The Scaleway Organization, permissions, state, tooling and quotas the socle expects before the first apply.
sidebar:
  order: 1
---

Tick these before `tofu apply` runs
[`opentofu/scaleway`](../../../opentofu/scaleway/README.md). The module
creates none of it. Scaleway has no API-enablement step; what blocks a first
apply is [quota](#quotas). The commands assume `scw init` and:

```sh
ORG_ID=33333333-3333-3333-3333-333333333333
PROJECT_NAME=socle-prod
REGION=fr-par
STATE_BUCKET=my-tofu-state
RUNNER_CIDR=203.0.113.10/32   # the CI runner's egress address
```

## Account

- [ ] An Organization with a validated payment method.
- [ ] **A validated identity**: without it most production instance types
  have no quota, and the apply fails while building a pool.
- [ ] **One Project per environment**, never one that held a cluster whose
  state is not archived
  ([SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)).
- [ ] A billing alert on the Organization: the autoscaler never
  consolidates, so an oversized `pool_min_size` is silent.

```sh
scw account project create name="$PROJECT_NAME" organization-id="$ORG_ID"
PROJECT_ID=$(scw account project list name="$PROJECT_NAME" -o json | jq -r '.[0].id')
```

## Permissions for the apply

- [ ] An IAM application of its own, never a person's, with this policy:

| Permission set | Scope | For |
| --- | --- | --- |
| `KubernetesFullAccess` | Project | the cluster, pools, ACL; also the bootstrap's access |
| `VPCFullAccess` | Project | the VPC |
| `PrivateNetworksFullAccess` | Project | the Private Network |
| `VPCGatewayFullAccess` | Project | the Public Gateways and their IPs |
| `IPAMFullAccess` | Project | the gateways' private addresses |
| `InstancesFullAccess` | Project | placement and security groups |
| `ObservabilityFullAccess` | Project | the Cockpit token |
| `IAMManager` | Organization | the Crossplane application, policy and key |
| `ObjectStorageFullAccess` | Project | creating the state bucket, once |

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

- [ ] Its API key, with an expiry (the `date` line covers GNU and BSD):

```sh
EXPIRES=$(date -u -d '+1 year' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+1y +%Y-%m-%dT%H:%M:%SZ)

scw iam api-key create \
  application-id="$APP_ID" \
  description="OpenTofu runner, socle foundations" \
  expires-at="$EXPIRES" \
  default-project-id="$PROJECT_ID"
```

- [ ] The key exported for the provider; the bootstrap's Helm provider reads
  the same `SCW_SECRET_KEY`:

```sh
export SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX
export SCW_SECRET_KEY=...
export SCW_DEFAULT_ORGANIZATION_ID="$ORG_ID"
export SCW_DEFAULT_PROJECT_ID="$PROJECT_ID"
```

<details>
<summary>Under the hood</summary>

- `IAMManager` cannot be confined to a Project: it is the broadest grant
  here. Give it to this application only, with the key bound to the runner's
  egress.
- Never `AllProductsFullAccess`: the module refuses it for Crossplane, and
  the same holds for the runner.
- Scaleway has no OIDC trust for CI: the runner holds a long-lived key. One
  per pipeline; never commit one.

</details>

## State

- [ ] An Object Storage bucket in the cluster's region: versioned, private,
  never shared with application data, no Object Lock.
- [ ] SSE-KMS encryption and a bucket policy restricting access to the
  runner's egress.
- [ ] A lifecycle rule on non-current versions only.

```sh
scw object bucket create "$STATE_BUCKET" region="$REGION"
scw object bucket update "$STATE_BUCKET" enable-versioning=true acl=private region="$REGION"
```

`scw` has no lifecycle rules; the `aws` CLI, pointed at Scaleway, does:

```sh
aws configure set aws_access_key_id "$SCW_ACCESS_KEY" --profile scw
aws configure set aws_secret_access_key "$SCW_SECRET_KEY" --profile scw
aws configure set region "$REGION" --profile scw

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
aws --profile scw --endpoint-url "https://s3.$REGION.scw.cloud" s3api put-bucket-lifecycle-configuration \
  --bucket "$STATE_BUCKET" --lifecycle-configuration file://lifecycle.json
```

One key per environment; `use_lockfile` locks through S3 conditional writes,
which Scaleway implements:

```hcl
terraform {
  backend "s3" {
    bucket                      = "my-tofu-state"
    key                         = "socle/scaleway/prod/terraform.tfstate"
    region                      = "fr-par"
    endpoints                   = { s3 = "https://s3.fr-par.scw.cloud" }
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
```

State holds the Crossplane secret key: losing the bucket leaves a cluster
nobody can manage.

## Tooling

- [ ] OpenTofu 1.10 or later (OCI module sources).
- [ ] The `scaleway/scaleway` provider `>= 2.82, < 3.0`, fetched by `tofu init`.
- [ ] The `scw` CLI, initialised.
- [ ] The `aws` CLI, for the bucket lifecycle.
- [ ] `jq`.
- [ ] `sh` where the bootstrap runs: the `helm_kubernetes` exec credential is
  a `sh -c printf`.

## Quotas

Read on 2026-09-14, for an Organization with a validated identity:

| Quota | Default | The defaults need |
| --- | --- | --- |
| `COMPUTE3-X8C-16G` | not published | 4 per cluster, up to 10 |
| `POP2-HC-8C-16G` | 2 | 0, unless `node_type` is POP2 |
| Kapsule clusters | 40 | 1 per environment |
| Dedicated control plane 4 or 8 | 4 | 1 per production cluster |
| Public Gateways per Organization | 50 | 2 per cluster |
| Private Networks per Public Gateway | 10 | 1 |
| Load Balancers | 50 | 1 per Service of type `LoadBalancer` |

- [ ] The real `COMPUTE3` figure read in the console: the quota table gives
  none for Zen 5.
- [ ] A raise ticket opened days ahead, at
  <https://console.scaleway.com/support/tickets/create>: `pool_max_size` ×
  zones × clusters, plus one dedicated control plane per production cluster.
  No API, and no quota metric to watch.
