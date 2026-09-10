# Observing AWS resources outside the cluster

Managed services around a cluster, cost data, and quota signals — read from a central observability cluster, not per client. In-cluster metrics: see [managed scope](eks-managed-scope.md).


| Question                          | Position                                                        |
| --------------------------------- | --------------------------------------------------------------- |
| AWS service metrics               | `GetMetricData` via YACE, every 300s                            |
| Cluster metrics through that path | Refused — wrong path entirely                                   |
| Database/cache exporters          | Catalog option, for signal the API lacks                        |
| Alerting                          | Ours — one Alertmanager for four clouds                         |
| CloudWatch Metric Streams         | Refused — only wins below ~190s, not needed here                |
| Cost attribution                  | CUR / Data Exports to the client's own S3 bucket                |
| Cost Explorer API                 | Refused as the audit source — paid, opaque, internal use only   |
| Quota metrics                     | Standard perimeter, same CloudWatch pricing as any other metric |
| Unmanaged-resource detection      | Resource Groups Tagging API                                     |
| AWS Config                        | Catalog option, for continuous compliance tracking              |


## Pulling metrics out

- Native AWS service metrics are **free to ingest** — cost only appears on the read side. One exception: S3 **request metrics** (opt-in, per-prefix) are billed at the custom-metric rate — excluded from the standard perimeter for that reason.
- Reading is billed **per metric requested** via `GetMetricData` — $0.01 per 1,000 metrics, batched up to 500 metrics/call.

A perimeter of ~100 time series across the nine services below:


| Scrape interval | Per month |
| --------------- | --------- |
| 60 s            | $43.20    |
| **300 s**       | **$8.64** |
| 900 s           | $2.88     |


**Decision: 300 seconds, with YACE in the central cluster.**

- One cadence across the multi-cloud supervision plane rather than a per-cloud tuning exercise — the gap to 900s ($5.76/month) isn't worth the added staleness.
- **The mistake to avoid:** pointing this same exporter at cluster metrics — in-cluster metrics stay on the in-cluster path, a different pipeline entirely.
- CloudWatch Metric Streams (push via Firehose) only becomes cheaper below a ~190-second interval — not a requirement here, so refused as the default. It also changes the whole model to near-native-frequency push rather than a chosen cadence, which the 300s decision doesn't need.
- YACE over an OpenTelemetry Collector receiver: the two are cost-equivalent (both call `GetMetricData` the same way), so the choice comes down to reusing Socle's existing exporter pattern — a Prometheus-style exporter feeding one central Alertmanager — rather than introducing a second pipeline shape just for this.

## Service coverage

The criterion for the standard perimeter, applied to every row below: **systematic** (common enough across clients to build once for everyone) **and** **actionable** (the metric drives a real alert, not just a number to look at). A service that's everywhere but produces nothing to act on doesn't qualify, no matter how common it is.


| Service                     | Direct alternative                    | Position                                                                   |
| --------------------------- | ------------------------------------- | -------------------------------------------------------------------------- |
| RDS, ElastiCache            | `postgres_exporter`, `redis_exporter` | Standard perimeter; exporter is a catalog option                           |
| S3 (storage metrics)        | none                                  | Standard perimeter — request metrics are a catalog option, not default     |
| SQS, SNS                    | none                                  | Standard perimeter — oldest-message age is the alert that matters          |
| Lambda                      | none                                  | Standard perimeter                                                         |
| Load balancers, NAT Gateway | none                                  | Standard perimeter — NAT port-allocation errors are the alert that matters |
| Quotas                      | none                                  | Standard perimeter                                                         |


- CloudFront and API Gateway are excluded: not systematic for Socle's setup, since exposure already goes through the EKS-managed ALB (see [network & security](eks-network-security.md)) — redundant for most clients, not a component of the reference architecture.
- SNS sits alongside SQS to cover AWS's fan-out messaging pattern — failed-delivery signals matter for the same reason SQS's backlog age does.

## Cost attribution

**Decision: CUR / Data Exports, delivered to the client's own S3 bucket, filtered by the module's standard cost-allocation tag.**

- Free to generate — the only cost is S3 storage (small) and Athena queries at query time ($5/TB scanned; partitioning by month keeps this low).
- Cost Allocation Tags take up to 24 hours to appear once activated. AWS provides `StartCostAllocationTagBackfill` for up to 12 months of history, but that backfill itself isn't instantaneous either — so activation is a module default from day one, not an onboarding step.
- Auditable by construction: the client's own dataset, queryable with their own Athena — not a number handed to them.
- Cost Explorer API is refused as the audit source: $0.01/request, a service Do Now calls rather than a dataset the client owns. Fine for internal dashboards, wrong tool for a figure a client needs to independently verify.

## Quotas & limits

**Decision: Service Quotas' automatic CloudWatch usage metrics, same pipeline as service metrics (YACE, 300s).**

- Free either way — the API and its `AWS/Usage` metrics cost nothing beyond the standard metric-read pricing above.
- Default set: EC2 instances per family, security group rules, Lambda concurrency, EBS gp3 storage, VPC IPs/ENIs per subnet — each is a known way a cluster silently stops scaling or scheduling before anyone notices.

## Detecting unmanaged resources

**Decision: Resource Groups Tagging API by default; AWS Config as a catalog option.**

- Free, and answers the question directly: which resources are missing the module's standard tag. No infrastructure to run for it.
- AWS Config gives continuous compliance tracking, not just a point-in-time answer, at a real but modest cost (~$0.003/configuration item, ~$0.001/rule evaluation) — a catalog option for a client who wants ongoing drift visibility, not the default.
- CloudTrail is refused as the default mechanism: real-time detection is possible in principle, but it's an event stream needing correlation logic to build and maintain, for a check the tagging API already answers for free.

## Cost impact

Reference perimeter: ~100 time series across the nine services above, 300s interval, list price.


|                                                    | Per month             |
| -------------------------------------------------- | --------------------- |
| `GetMetricData` via YACE (~100 series, 300s)       | $8.64                 |
| CUR generation + S3 storage                        | ~$0 (storage only)    |
| Resource Groups Tagging API                        | $0                    |
| Service Quotas metrics                             | included above        |
| **Total**                                          | **~$9**               |
| *Same perimeter at 60s*                            | $43.20                |


Read 8 September 2026.

## Module specification


| Variable                               | Default                                    | Constraint                                                        |
| -------------------------------------- | ------------------------------------------ | ----------------------------------------------------------------- |
| `cost_allocation_tag_key`              | matches the module's standard resource tag | must be the same key applied to every resource the module creates |
| `cost_allocation_tag_backfill_enabled` | `true`                                     | one-time action, rate-limited to once per 24h                     |
| `metrics_export_enabled`               | `true`                                     | —                                                                 |
| `metrics_scrape_interval_seconds`      | `300`                                      | —                                                                 |
| `quota_monitoring_enabled`             | `true`                                     | —                                                                 |
| `aws_config_enabled`                   | `false`                                    | catalog option                                                    |


Absent by decision: any CloudWatch Metric Streams / Firehose variable, any Cost Explorer API credential or role, any CloudFront/API Gateway monitoring toggle — catalog surface where it exists at all, not module defaults.

## Sources

Read 8–9 September 2026.

- [`GetMetricData` pricing and cost attribution](https://aws.amazon.com/blogs/mt/identifying-resources-driving-amazon-cloudwatch-getmetricdata-charges-using-aws-cloudtrail/) · [`GetMetricData` API reference (500-metric batch limit)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_GetMetricData.html) · [CloudWatch native-metric ingestion](https://cast.ai/blog/the-truth-about-cloudwatch-pricing/) · [S3 request metrics billed as custom](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudwatch-monitoring.html)
- [CloudWatch Metric Streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Metric-Streams.html) · [Firehose pricing](https://aws.amazon.com/firehose/pricing/) · [`yet-another-cloudwatch-exporter`](https://github.com/prometheus-community/yet-another-cloudwatch-exporter)
- [AWS Data Exports](https://aws.amazon.com/about-aws/whats-new/2023/11/aws-billing-cost-management-data-exports) · [Resource tags in CUR](https://docs.aws.amazon.com/cur/latest/userguide/resource-tags-columns.html) · [Cost allocation tag activation and backfill](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html) · [Cost Explorer API pricing](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/)
- [Service Quotas](https://docs.aws.amazon.com/servicequotas/latest/userguide/intro.html) · [CloudWatch usage metrics (`AWS/Usage`)](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Usage-Metrics.html)
- [Resource Groups Tagging API](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html) · [AWS Config pricing](https://www.cloudzero.com/blog/aws-config-pricing/)

