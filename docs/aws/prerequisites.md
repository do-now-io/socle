# AWS — prerequisites

What must exist on your AWS account before `tofu apply` can run the socle
foundations module. The module creates none of it.

Each item can be done by hand in the AWS Console — nothing is provided for
that path — or from the command line. The commands for every item are
gathered in [By command line](#by-command-line) at the end.

## Account

- An AWS account. It is very likely to hold **several clusters** —
  dev/staging/prod rings, or more than one environment for the same
  client. This module does not assume exclusive ownership of the account,
  and the account-wide prerequisites below (GuardDuty in particular)
  follow from that.
- Service quotas high enough for however many clusters share this account
  — VPCs per region, EIPs per region, NAT Gateways per AZ. Default quotas
  usually clear a handful of clusters; worth checking ahead of the third
  or fourth.
- GuardDuty EKS Protection, if wanted: enabled once per account per
  region, outside this module entirely — see
  [Good practices → GuardDuty](#guardduty) and
  [network & security](eks-network-security.md) for the decision and its
  cost.

## Roles on the principal running OpenTofu

| Service | Grants |
| --- | --- |
| EC2 (VPC, subnet, route table, internet gateway, NAT gateway, EIP, VPC endpoint) | the network |
| EKS (cluster, add-on, Pod Identity association) | the cluster and its add-ons |
| IAM (role, role policy attachment) | the cluster's, EBS CSI's and Crossplane's identities |
| KMS (key, key rotation) | secrets encryption |
| STS (`GetCallerIdentity`) | the provider's own credential check |

Every service above is reachable the moment the account exists — nothing
to activate ahead of time. The table above is authorization, not
activation.

## Credentials

The module accepts no credential as input and no IAM access key is ever
needed. The provider reads AWS's own ambient credential chain — a named
profile or environment variables for local runs, OIDC federation (a CI
system's own OIDC provider, assuming an IAM role) from CI.

## State

An S3 bucket for remote state, with versioning on, created before the
first `tofu init`. OpenTofu 1.10+ locks natively against S3 through
conditional writes — no separate DynamoDB table needed. The module ships
no backend block; state lives in your own account, so declare it in your
root configuration:

```hcl
terraform {
  backend "s3" {
    bucket = "my-account-tofu-state"
    key    = "socle/aws/<cluster-name>"
    region = "eu-west-3"
  }
}
```

## Tooling

- OpenTofu 1.10 or later.
- AWS CLI, authenticated.

## Good practices

Per resource, what to do beyond simply creating it.

### Account

- Because one account commonly holds several clusters, separate
  environments by IAM role scope and state key prefix, not by account
  boundary alone.
- A budget with alert thresholds. Several clusters sharing one account
  make a runaway workload's cost easy to miss inside the aggregate bill.

### Roles

- A dedicated IAM role for OpenTofu, assumed via OIDC from CI and via role
  assumption (never long-lived access keys) for humans.
- Scoped to what this module actually creates, not `AdministratorAccess`.
- Never grant `iam:CreateAccessKey` on the automation role — enforce it
  with a Service Control Policy if the account sits under an AWS
  Organization.

### Credentials

- OIDC federation in CI, role assumption for humans.
- No IAM user access keys, ever.

### State bucket

State holds every attribute of every resource, secrets included, and
losing it means the cluster exists but is no longer manageable.

- Versioning on before the first write.
- A lifecycle rule that can never touch the live object: expire only
  noncurrent versions, and only ones both old and superseded.
- S3 Block Public Access enabled, default encryption on (SSE-S3 or
  SSE-KMS).
- One prefix per cluster/environment: one account, and therefore one
  bucket, commonly serves several clusters.
- Never shared with application data.

### GuardDuty

- Enabled once per account per region, never per cluster. A second
  `tofu apply` of this module in the same account must not try to create
  its own detector — that is exactly why this module has no
  `guardduty_*` variable.
- Audit Log Monitoring and Runtime Monitoring turn on independently; see
  [network & security](eks-network-security.md) for the cost and the
  decision.

## By command line

Set the variables once:

```sh
REGION=eu-west-3
STATE_BUCKET=my-account-tofu-state
ROLE_NAME=socle-tofu
OIDC_PROVIDER_ARN=arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com
```

Credentials — an IAM role CI assumes via OIDC, trusting one specific
repository and branch (adjust the `sub` condition to your CI system's own
claim format):

```sh
cat > trust-policy.json <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$OIDC_PROVIDER_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:sub": "repo:do-now-io/socle:ref:refs/heads/main"
      }
    }
  }]
}
JSON
aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json
```

Scope the role to what this module creates (start from a custom policy
covering the services in the table above, not a managed
administrator-level policy):

```sh
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name socle-tofu-scope --policy-document file://socle-tofu-policy.json
```

State bucket:

```sh
aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

A lifecycle rule that never deletes a live object — only noncurrent
versions older than a year:

```sh
cat > lifecycle.json <<JSON
{
  "Rules": [{
    "ID": "expire-old-noncurrent-versions",
    "Status": "Enabled",
    "NoncurrentVersionExpiration": { "NoncurrentDays": 365 }
  }]
}
JSON
aws s3api put-bucket-lifecycle-configuration --bucket "$STATE_BUCKET" --lifecycle-configuration file://lifecycle.json
```

GuardDuty, once per account per region (skip if a detector already exists
— check with `aws guardduty list-detectors` first):

```sh
DETECTOR_ID=$(aws guardduty create-detector --enable --query DetectorId --output text)
aws guardduty update-detector --detector-id "$DETECTOR_ID" \
  --features Name=EKS_AUDIT_LOGS,Status=ENABLED Name=EKS_RUNTIME_MONITORING,Status=ENABLED
```

Then point the backend at the state bucket and initialise:

```sh
tofu init -backend-config="bucket=$STATE_BUCKET" -backend-config="key=socle/aws/<cluster-name>" -backend-config="region=$REGION"
```
