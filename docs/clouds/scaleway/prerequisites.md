---
title: Prerequisites
description: The Scaleway Organization, permissions, state, tooling and quotas the socle expects before the first apply.
sidebar:
  order: 1
---

What must exist before `tofu apply` can run [`opentofu/scaleway`](../../../opentofu/scaleway/README.md). The module creates none of it. Scaleway has no API-enablement step: every product is reachable once the Organization exists and its identity is validated. What blocks a first apply here is quota.

The commands assume the `scw` CLI is initialised (`scw init`) and these variables are set:

```sh
ORG_ID=33333333-3333-3333-3333-333333333333
PROJECT_NAME=socle-prod
REGION=fr-par
STATE_BUCKET=my-tofu-state
RUNNER_CIDR=203.0.113.10/32   # the CI runner's egress address
```

## Account

- A Scaleway Organization with a validated payment method.
- **A validated identity.** Without it most production instance types have no quota at all, and the apply fails while building a pool.
- **One Project per environment.** `project_id` is required because the Project is the only boundary Scaleway offers for both IAM and cost ([SCALEWAY-08](../../decisions/scaleway.md#scaleway-08-one-project-per-environment-one-scoped-crossplane-key)). Never reuse a Project that has held a cluster until its state is archived.
- A billing alert on the Organization. Nodes are billed whether or not anything schedules on them, and the cluster-autoscaler never consolidates, so an oversized `pool_min_size` is otherwise silent.

```sh
scw account project create name="$PROJECT_NAME" organization-id="$ORG_ID"
PROJECT_ID=$(scw account project list name="$PROJECT_NAME" -o json | jq -r '.[0].id')
```

## Permissions for the apply

Give the apply its own IAM application and key, never a person's. Its policy carries:

| Permission set | Scope | For |
| --- | --- | --- |
| `KubernetesFullAccess` | Project | the cluster, its pools and its ACL; also what lets the bootstrap act on the cluster |
| `VPCFullAccess` | Project | the VPC |
| `PrivateNetworksFullAccess` | Project | the cluster's Private Network |
| `VPCGatewayFullAccess` | Project | the Public Gateways and their flexible IPs |
| `IPAMFullAccess` | Project | the gateways' private address reservations |
| `InstancesFullAccess` | Project | the placement groups and the security groups |
| `ObservabilityFullAccess` | Project | the query-only Cockpit token |
| `IAMManager` | Organization | the Crossplane application, its policy and its key |
| `ObjectStorageFullAccess` | Project | creating the state bucket, once; not needed by the apply afterwards |

`IAMManager` is Organization-scoped by nature: it is the broadest grant here and the one that cannot be confined to the Project. Give it to this application only, and bind the application's key to the runner's egress with a policy condition. Never `AllProductsFullAccess`: the module refuses it for the Crossplane identity, and the same reasoning holds for the runner.

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

Its key, with an expiry so rotation is forced. The date command differs between GNU and BSD:

```sh
EXPIRES=$(date -u -d '+1 year' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+1y +%Y-%m-%dT%H:%M:%SZ)

scw iam api-key create \
  application-id="$APP_ID" \
  description="OpenTofu runner, socle foundations" \
  expires-at="$EXPIRES" \
  default-project-id="$PROJECT_ID"
```

Export it for the provider. There is no federated alternative: Scaleway has no OIDC trust for CI, so the runner holds a long-lived key. The bootstrap's Helm provider reads the same `SCW_SECRET_KEY` as its bearer token.

```sh
export SCW_ACCESS_KEY=SCWXXXXXXXXXXXXXXXXX
export SCW_SECRET_KEY=...
export SCW_DEFAULT_ORGANIZATION_ID="$ORG_ID"
export SCW_DEFAULT_PROJECT_ID="$PROJECT_ID"
```

One key per pipeline, so revoking one stops nothing else. Never commit one.

## State

An Object Storage bucket, created before the first `tofu init`, in the cluster's region, never shared with application data. State holds every attribute of every resource, and on this cloud that includes the Crossplane secret key: losing the bucket leaves a cluster nobody can manage.

- Versioning on before the first write.
- Server-side encryption with Key Manager (SSE-KMS).
- A bucket policy restricting access to the runner's egress addresses.
- A lifecycle rule that never touches a live object: expire only non-current versions, and only old ones.
- No Object Lock on this bucket: WORM would make a legitimate state rewrite impossible.

```sh
scw object bucket create "$STATE_BUCKET" region="$REGION"
scw object bucket update "$STATE_BUCKET" enable-versioning=true acl=private region="$REGION"
```

`scw` does not expose lifecycle rules or bucket policies; the `aws` CLI does, pointed at Scaleway:

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

The module ships no backend block. Declare it in your root, one key per environment:

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

Nothing else is needed for locking: Scaleway Object Storage implements S3 conditional writes (`If-Match`, `If-None-Match`), which is what `use_lockfile` uses.

## Tooling

- OpenTofu 1.10 or later (`required_version = ">= 1.10"`, needed for OCI module sources).
- The `scaleway/scaleway` provider, `>= 2.82, < 3.0`, which `tofu init` fetches.
- The `scw` CLI, initialised.
- The `aws` CLI, for the bucket settings `scw` does not expose.
- `jq`, for the commands above.
- `sh` on the machine that runs the bootstrap: the `helm_kubernetes` output's exec credential is a `sh -c printf`.

## Quotas

Scaleway quotas are per instance type and sit below what the module's defaults need. As read on 2026-09-14, for an Organization with a validated identity:

| Quota | Default | The module's defaults need |
| --- | --- | --- |
| `COMPUTE3-X8C-16G` | not published | 4 per cluster at `pool_min_size`, up to 10 at `pool_max_size` |
| `POP2-HC-8C-16G` | 2 | 0, unless `node_type` is POP2 |
| Kapsule clusters | 40 | 1 per environment |
| Kapsule with a dedicated control plane 4 or 8 | 4 | 1 per production cluster |
| Public Gateways per Organization | 50 | 2 per cluster |
| Private Networks per Public Gateway | 10 | 1 |
| Load Balancers | 50 | 1 per Service of type `LoadBalancer` |

- The quota table gives no figure for the Zen 5 generation (`COMPUTE3`, `STANDARD3`, `BASIC3`). Read the real number in the console before the first apply.
- A raise is a support ticket: no API, no OpenTofu resource. Open it days ahead, at <https://console.scaleway.com/support/tickets/create>, for `pool_max_size` times the number of zones of `node_type`, times the clusters, plus one dedicated control plane per production cluster.
- Scaleway exposes no quota metric, so there is nothing to watch: the control is this checklist, and the symptom is a failed apply.
