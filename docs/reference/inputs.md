---
title: Inputs
description: The kube object and the catalog schema in full, the Cilium, CoreDNS and EKS add-on objects, and every variable of the bootstrap module.
sidebar:
  order: 0
---

What a client writes in his tfvars, beyond `socle_version` and the cloud
object (`aws = {…}`, documented with each cloud's foundations). How to write
it is in [Configure a cluster](../guides/configure.md).

## kube

`kube` is `{ <module> = { <attribute> = <value> } }`, typed `any`, default
`{}`. Only what differs from a default needs writing; a module absent from
`kube` is at its defaults, on or off as the catalog says.

| Rule | |
| --- | --- |
| Names | `snake_case`, as HCL writes them without quotes. The artifact reads `inputs.modules.external_dns` as-is; the module's folder, `ResourceSet` and namespace are the same name in `kebab-case` (`external-dns`) |
| Unknown module | refused at plan: `kube: unknown module(s) <name>. Catalog: <every module>.` |
| Unknown attribute | refused at plan, with the allowed attributes of every module |
| Wrong type | refused at plan: each value must have the kind (string, number, bool, list, object) of its default |
| Module not offered on this cloud | refused at plan: `kube: a module is not offered on <cloud>. Cloud-bound modules: …` |
| Secrets in `values` | refused at plan, per module: the chart's secret-bearing paths. Put them in the Secret named by `values_secret` |
| `values` and a named attribute on the same key | `values` wins |

The schema is [`catalog.tf`](../../opentofu/bootstrap/catalog.tf): each
entry's defaults are its attributes. The per-attribute rules are the
validations of `kube` in
[`variables.tf`](../../opentofu/bootstrap/variables.tf).

### The catalog schema

Every module with a chart also takes `values` (`{}`, any chart value, merged
over the socle's defaults, the client's winning) and `values_secret` (`""`,
the name of a Secret the client creates in the module's namespace with a
`values.yaml` key, merged last, never read by OpenTofu). They are not
repeated below. `gateway_api` and `hello` have neither.

| Module | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `hello` | `enabled` | `true` | podinfo, as a proof that the pipeline works |
| `hello` | `replicas` | `1` | replicas of the podinfo Deployment |
| `hello` | `message` | `"hello from socle"` | the message podinfo serves |
| `gateway_api` | `enabled` | `true` | the Gateway API standard CRDs from upstream, pinned by commit, and Cilium's `cilium` class on aws and azure. Offered on aws, azure and scaleway; GKE owns its own. Off orphans the CRDs |
| `gateway_api` | `gateways` | `true` | the shared Gateways `gateway-system/public` and `private`, on aws (once the foundations issued `gateway_certificate`) and azure |
| `crossplane` | `enabled` | `false` | Crossplane and, on aws, its IAM, EKS and S3 providers: the tooling each module declares its cloud access through. Off leaves the CRDs and orphans every module role still declared |
| `crossplane` | `permissions_boundary` | `""` | aws: the boundary every module role carries; an IAM policy ARN. The aws root wires it from the foundations' `crossplane_permissions_boundary_arn` |
| `external_dns` | `enabled` | `false` | DNS records for Services, Ingresses and HTTPRoutes in the cloud's zone. On aws with `crossplane` on, its own IAM role; elsewhere the client brings a credential. The aws root turns it on when `aws.gateway_certificate` is set and Crossplane can give it a role |
| `external_dns` | `domain_filters` | `[]` | zones it may write to, as DNS names; at least one when enabled |
| `external_dns` | `policy` | `"upsert-only"` | `upsert-only` never deletes a record; `sync` also deletes what it owns |
| `external_dns` | `txt_owner_id` | the cluster name | the owner in the TXT registry, so two clusters never fight over a zone |
| `argocd` | `enabled` | `true` | ArgoCD, the client's GitOps layer |
| `argocd` | `admin_enabled` | `true` | keep the local `admin` account; `false` once SSO exists |
| `argocd` | `domain` | `""` | the host ArgoCD is served at (`configs.cm.url` and the HTTPRoute), a lowercase FQDN; empty means no URL and no route |
| `argocd` | `gateway` | `"private"` | the shared Gateway its HTTPRoute attaches to: `private`, `public`, or `""` for none |
| `argocd` | `ha` | `false` | the chart's HA layout: Redis HA, two replicas of server, repo-server and applicationset |
| `victoria_metrics` | `enabled` | `true` | VictoriaMetrics single-node, the metrics storage |
| `victoria_metrics` | `retention` | `"15d"` | whole hours, days, weeks or years (`15d`, `4w`, `1y`), at least a day |
| `victoria_metrics` | `storage_size` | `"20Gi"` | the claim on the default StorageClass, in `Gi` or `Ti`; `""` means no claim, an `emptyDir` |
| `otel_agent` | `enabled` | `true` | the OpenTelemetry Collector as a DaemonSet: kubelet metrics, container logs, the nodes and pods dashboard |
| `otel_agent` | `logs` | `true` | container logs from `/var/log/pods` to `victoria_logs` while it is on; `false` keeps the agent to metrics |
| `otel_gateway` | `enabled` | `true` | the OpenTelemetry Collector as a one-replica Deployment: object state, scraping, the applications' OTLP, the workloads dashboard |
| `grafana` | `enabled` | `true` | Grafana, a datasource per backend that is on, every dashboard a module ships |
| `grafana` | `domain` | `""` | the host Grafana is served at (`server.root_url` and the HTTPRoute); empty means none |
| `grafana` | `gateway` | `"private"` | the shared Gateway its HTTPRoute attaches to: `private`, `public`, or `""` for none |
| `victoria_logs` | `enabled` | `true` | VictoriaLogs single-node, the logs storage |
| `victoria_logs` | `retention` | `"7d"` | as `victoria_metrics` |
| `victoria_logs` | `storage_size` | `"20Gi"` | as `victoria_metrics` |
| `victoria_traces` | `enabled` | `false` | VictoriaTraces single-node, the traces storage. Off: pre-GA, an upgrade may drop stored traces |
| `victoria_traces` | `retention` | `"7d"` | as `victoria_metrics` |
| `victoria_traces` | `storage_size` | `"10Gi"` | as `victoria_metrics` |
| `keda` | `enabled` | `false` | KEDA, event-driven autoscaling down to zero |
| `keda` | `services` | `[]` | aws only: the services KEDA's own role may read, from `sqs`, `cloudwatch`, `kinesis`, `dynamodb`. Needs `crossplane` on and each service in `aws.crossplane.allowed_services` |
| `kyverno` | `enabled` | `false` | the Kyverno engine, no policy |
| `kyverno_policies` | `enabled` | `false` | the socle's policy set, every policy in Audit; needs `kyverno` |
| `kyverno_policies` | `profile` | `"baseline"` | `baseline`, or `restricted` for baseline plus six |
| `kyverno_policies` | `enforce` | `[]` | policies switched to Enforce, each compiled into a native ValidatingAdmissionPolicy; only names this configuration renders |
| `kyverno_policies` | `allowed_registries` | `[]` | registries images may come from; empty means no registry policy |
| `external_secrets` | `enabled` | `false` | External Secrets Operator |
| `external_secrets` | `prefixes` | `[<cluster_name>]` | aws with `crossplane` on: the module's read-only role reads `secret:<prefix>/*`, and the `ClusterSecretStore` `secret-manager` is created on it. Needs `secretsmanager` in `aws.crossplane.allowed_services`. `[]`: no role, no store |
| `reloader` | `enabled` | `false` | Stakater Reloader, opt-in per workload by annotation; `reloader.autoReloadAll` is refused in `values` |
| `velero` | `enabled` | `false` | Velero, backups the applications opt into by label. aws only; needs `crossplane` on and `s3` in `aws.crossplane.allowed_services` |
| `velero` | `policies` | seven pairs | `[{ frequency, retention, schedule }]`, one `Schedule` each: hourly 24h and 48h, daily 7d and 30d, weekly 30d and 90d, monthly 90d |
| `velero` | `node_agent` | `eks_addons.efs_csi` | the privileged node-agent DaemonSet, which backs EFS volumes up by file system |

What each module installs, and what it refuses in `values`, is on its
[catalog page](../catalog/index.md).

## Cilium, CoreDNS and the EKS add-ons

Three objects of the bootstrap module and of the aws root, each `any`,
validated like `kube`: an unknown attribute or a wrong type is refused at
plan. Every key is optional.

| Variable | Attribute | Default | Where | Meaning |
| --- | --- | --- | --- | --- |
| `cilium` | `enabled` | `true` | aws, azure | install Cilium, and CoreDNS on aws, before Flux. `false` is for a cluster that brings its own CNI and DNS; the e2e k3s is the only such cluster |
| `cilium` | `hubble` | `false` | aws, azure | adds Hubble Relay and UI; Hubble in the agent is always on |
| `cilium` | `gateway_api` | `true` | aws, azure | Cilium's Gateway controller and the `cilium` class |
| `cilium` | `values` | `{}` | aws, azure | any Cilium chart value, merged after the socle's. Private keys are refused: name a Secret through the chart's `existingSecret` fields |
| `coredns` | `values` | `{}` | aws, with Cilium | any CoreDNS chart value, merged after the socle's. Nothing is refused: the chart takes no secret inline |
| `eks_addons` | `pod_identity_agent` | `true` | aws | the Pod Identity Agent; the two storage drivers need it |
| `eks_addons` | `ebs_csi` | `true` | aws | the EBS CSI driver, with its own role |
| `eks_addons` | `efs_csi` | `false` | aws | the EFS CSI driver, with its own role |
| `eks_addons` | `snapshot_controller` | `true` | aws | the CSI snapshot controller and its CRDs |

`cilium` with any key is refused on gcp and scaleway; `coredns` wherever the
socle installs no CoreDNS; `eks_addons` on every cloud but aws; `ebs_csi` or
`efs_csi` with `pod_identity_agent = false`.

Refused in `cilium.values`, measured against the 1.20.2 chart: `tls.ca.key`,
`hubble.tls.server.key`, `hubble.relay.tls.client.key`,
`hubble.relay.tls.server.key`, `hubble.ui.tls.client.key`,
`hubble.metrics.tls.server.key` and `clustermesh.config.clusters[*].tls.key`.
Certificates alone are accepted.

**Not attributes:** chart versions, IPAM and routing mode, kube-proxy
replacement, the operator's replica count, resources, the GatewayClass name.
Each is dictated by the foundations' network or has no socle use yet; all but
the chart versions are reachable through `values`.

`cluster_network` (`api_endpoint`, `service_cidr` on aws, `pod_cidr` on
azure) is what Cilium needs to know about the cluster. The root passes it
from the foundations' outputs; a client never writes it.

## The bootstrap module's variables

Generated by terraform-docs from
[`opentofu/bootstrap`](../../opentofu/bootstrap/README.md). A client's root
passes most of them through; the aws root's own variables are in
[OpenTofu modules](opentofu-modules.md#clustersaws).

::include{file="opentofu/bootstrap/README.md" section="tf-docs"}
