---
title: Inputs
description: The kube object and the catalog schema in full, the Cilium, CoreDNS and EKS add-on objects, and every variable of the bootstrap module.
sidebar:
  order: 0
---

What a cluster's configuration holds beyond `socle_version` and the cloud object. How to write
it: [Configure a cluster](../guides/configure.md).

## kube

`{ <module> = { <attribute> = <value> } }`, typed `any`, default `{}`; only
what differs from a default.

| Rule | |
| --- | --- |
| Names | `snake_case`; the folder, `ResourceSet` and namespace use `kebab-case` (`external-dns`) |
| Unknown module | refused at plan: `kube: unknown module(s) <name>. Catalog: <every module>.` |
| Unknown attribute | refused at plan, with the allowed attributes of every module |
| Wrong type | refused at plan: each value must have the kind (string, number, bool, list, object) of its default |
| Module not offered on this cloud | refused at plan: `kube: a module is not offered on <cloud>. Cloud-bound modules: …` |
| Secrets in `values` | refused at plan, per module: the chart's secret-bearing paths. Put them in the Secret named by `values_secret` |
| `values` and a named attribute on the same key | `values` wins |

Sources: [`catalog.tf`](../../opentofu/bootstrap/catalog.tf) (the schema),
[`variables.tf`](../../opentofu/bootstrap/variables.tf) (the rules).

### The catalog schema

Every module but `gateway_api` and `hello` also takes `values` (`{}`, any
chart value, yours winning) and `values_secret` (`""`, a Secret in the
module's namespace with a `values.yaml` key, merged last); not repeated below.
An attribute whose default is a block (`monitoring.logs`…) is merged one
level deep: a key written alone keeps its siblings at their default.

| Module | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `hello` | `enabled` | `true` | podinfo, as a proof that the pipeline works |
| `hello` | `replicas` | `1` | replicas of the podinfo Deployment |
| `hello` | `message` | `"hello from socle"` | the message podinfo serves |
| `gateway_api` | `enabled` | `true` | the Gateway API standard CRDs from upstream, pinned by commit, and Cilium's `cilium` class on aws and azure. On gcp GKE owns the CRDs and the class, and the module renders the shared Gateways only. Off orphans the CRDs |
| `gateway_api` | `gateways` | `true` | the shared Gateways `gateway-system/public` and `private`, on aws (once the foundations issued `gateway_certificate`), azure, and gcp (once they issued the certificate map and the regional certificate, `gcp.gateway_certificate`) |
| `crossplane` | `enabled` | `false` | Crossplane and, per cloud, its providers (on aws IAM, EKS and S3; on gcp the Google Cloud ones, as the federated principal the foundations' `gcp.crossplane` grants): the tooling each module declares its cloud access through. Off leaves the CRDs and orphans every module role still declared |
| `crossplane` | `permissions_boundary` | `""` | aws: the boundary every module role carries; an IAM policy ARN. The aws root wires it from the foundations' `crossplane_permissions_boundary_arn`. Refused on gcp |
| `crossplane` | `dns_records_role` | `""` | gcp: the project custom role Crossplane grants external-dns to write DNS records, on the project (a zone's own IAM is never honoured); `projects/<id>/roles/<role>`. The gcp root wires it from the foundations' `dns_records_role`. Refused elsewhere |
| `external_dns` | `enabled` | `false` | DNS records for Services, Ingresses and HTTPRoutes in the cloud's zone. On aws and gcp with `crossplane` on, its own access (an IAM role on aws, a binding of the DNS records role on gcp); elsewhere the client brings a credential. The aws and gcp roots turn it on when the foundations' `gateway_certificate` is set and Crossplane can give it access |
| `external_dns` | `domain_filters` | `[]` | zones it may write to, as DNS names; at least one when enabled |
| `external_dns` | `policy` | `"upsert-only"` | `upsert-only` never deletes a record; `sync` also deletes what it owns |
| `external_dns` | `txt_owner_id` | the cluster name | the owner in the TXT registry, so two clusters never fight over a zone |
| `argocd` | `enabled` | `true` | ArgoCD, the client's GitOps layer |
| `argocd` | `admin_enabled` | `true` | keep the local `admin` account; `false` once SSO exists |
| `argocd` | `domain` | `""` | the host ArgoCD is served at (`configs.cm.url` and the HTTPRoute), a lowercase FQDN; empty means no URL and no route |
| `argocd` | `gateway` | `"private"` | the shared Gateway its HTTPRoute attaches to: `private`, `public`, or `""` for none |
| `argocd` | `ha` | `false` | the chart's HA layout: Redis HA, two replicas of server, repo-server and applicationset |
| `argocd_image_updater` | `enabled` | `false` | Argo CD Image Updater, watching `argocd`; refused while `argocd` is off |
| `argocd_image_updater` | `repositories` | `[]` | aws: the ECR repositories of the cluster's account and region its own read-only role may read, globs allowed, never `*` alone; needs `ecr` in `aws.crossplane.allowed_services`. gcp: `LOCATION/REPOSITORY` in the cluster's project, read through `roles/artifactregistry.reader` on the whole project, which must be in `gcp.crossplane.allowed_roles`; one registry entry per location named. Both need `crossplane` on. `[]`: no role, no registry entry |
| `argocd_image_updater` | `registries` | `[]` | the client's other registries, as Image Updater's `registries.conf` writes them, after the socle's ECR or Artifact Registry entries; `credentials` a `secret:`, `pullsecret:`, `env:` or `ext:` reference. `config.registries` is refused in `values` |
| `monitoring` | `enabled` | `true` | the victoria-metrics-k8s-stack chart as one release: the operator, VictoriaMetrics, vmagent scraping the cluster, kube-state-metrics, node-exporter, and the parts below |
| `monitoring` | `metrics` | `{ retention = "15d", storage_size = "20Gi" }` | VictoriaMetrics single-node. `retention`: whole hours, days, weeks or years (`15d`, `4w`, `1y`), at least a day; `storage_size`: the claim on the default StorageClass, in `Gi` or `Ti`, `""` for an `emptyDir` |
| `monitoring` | `logs` | `{ enabled = true, retention = "7d", storage_size = "20Gi" }` | VictoriaLogs single-node, the same shape; off also stops `otel_agent` |
| `monitoring` | `traces` | `{ enabled = false, retention = "7d", storage_size = "10Gi" }` | VictoriaTraces single-node, the same shape. Off: pre-GA, an upgrade may drop stored traces |
| `monitoring` | `grafana` | `{ enabled = true, domain = "", gateway = "private" }` | Grafana with the stack's datasources and dashboards; `domain` the host it is served at (`server.root_url` and the HTTPRoute), empty for none; `gateway` the shared Gateway its HTTPRoute attaches to: `private`, `public`, or `""` |
| `monitoring` | `alerting` | `{ enabled = false, watchdog = true, receivers = [], route = {}, receivers_secret = "" }` | vmalert and Alertmanager with kube-prometheus-stack's rules. `receivers` and `route` as Alertmanager writes them, keys only through `*_file` fields; `receivers_secret` a Secret in `monitoring`, mounted under `/etc/alertmanager/secrets/`; `watchdog` an always-firing alert to its `watchdog-url` key. On needs a receiver and, with `watchdog`, `receivers_secret` |
| `otel_agent` | `enabled` | `true` | the OpenTelemetry Collector as a DaemonSet: container logs to VictoriaLogs, while `monitoring.logs` is on |
| `otel_gateway` | `enabled` | `true` | the OpenTelemetry Collector as a one-replica Deployment: the applications' OTLP and the Kubernetes events |
| `keda` | `enabled` | `false` | KEDA, event-driven autoscaling down to zero |
| `keda` | `services` | `[]` | aws and gcp: the services KEDA's own identity may read — on aws from `sqs`, `cloudwatch`, `kinesis`, `dynamodb`, each service also in `aws.crossplane.allowed_services`; on gcp `pubsub`, read through Cloud Monitoring, `roles/monitoring.viewer` also in `gcp.crossplane.allowed_roles`. Needs `crossplane` on |
| `metrics_server` | `enabled` | `true` | the `metrics.k8s.io` API behind `kubectl top` and HPAs on CPU or memory. aws only |
| `metrics_server` | `ha` | `false` | two replicas on two nodes, with a disruption budget |
| `karpenter` | `enabled` | `false` | Karpenter, the nodes for the workloads. aws only; needs `crossplane` on and `ec2`, `ssm`, `pricing`, `sqs`, `eks` in `aws.crossplane.allowed_services` |
| `karpenter` | `node_pool` | `{ capacity_types = ["spot", "on-demand"], architectures = ["arm64", "amd64"], cpu = 32, memory = "128Gi", consolidate_after = "1m", ami = "al2023@latest" }` | the default NodePool: what it may launch, the ceiling of all its nodes together, how long a node stays empty or under-used before it goes, and the AL2023 alias |
| `kyverno` | `enabled` | `false` | the Kyverno engine, no policy |
| `kyverno_policies` | `enabled` | `false` | the socle's policy set, every policy in Audit; needs `kyverno` |
| `kyverno_policies` | `profile` | `"baseline"` | `baseline`, or `restricted` for baseline plus six |
| `kyverno_policies` | `enforce` | `[]` | policies switched to Enforce, each compiled into a native ValidatingAdmissionPolicy; only names this configuration renders |
| `kyverno_policies` | `allowed_registries` | `[]` | registries images may come from; empty means no registry policy |
| `external_secrets` | `enabled` | `false` | External Secrets Operator |
| `external_secrets` | `prefixes` | `[<cluster_name>]` | aws with `crossplane` on: the module's read-only role reads `secret:<prefix>/*`, and the `ClusterSecretStore` `secret-manager` is created on it. Needs `secretsmanager` in `aws.crossplane.allowed_services`. On gcp secrets are named `<prefix>_<name>`, so a prefix is letters, digits and `-` (no `_`, no `/`). `[]`: no role, no store |
| `reloader` | `enabled` | `false` | Stakater Reloader, opt-in per workload by annotation; `reloader.autoReloadAll` is refused in `values` |
| `velero` | `enabled` | `false` | Velero, backups the applications opt into by label. aws and gcp; needs `crossplane` on and the bucket's access in the foundations' allowlist: `s3` in `aws.crossplane.allowed_services`, `roles/storage.objectAdmin` in `gcp.crossplane.allowed_roles` |
| `velero` | `policies` | seven pairs | `[{ frequency, retention, schedule }]`, one `Schedule` each: hourly 24h and 48h, daily 7d and 30d, weekly 30d and 90d, monthly 90d |
| `velero` | `node_agent` | `eks_addons.efs_csi` | the privileged node-agent DaemonSet, which backs EFS volumes up by file system. Refused on gcp: Autopilot forbids its hostPath, and every volume is a PD snapshot |

What each module installs and refuses in `values`: its [catalog page](../catalog/index.mdx).

## Cilium, CoreDNS and the EKS add-ons

Three objects, each `any`, validated like `kube`; every key optional.

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

| Refused | When |
| --- | --- |
| `cilium` | on gcp and scaleway |
| `coredns` | where the socle installs no CoreDNS |
| `eks_addons` | on every cloud but aws |
| `ebs_csi`, `efs_csi` | with `pod_identity_agent = false` |
| in `cilium.values` (chart 1.20.2) | `tls.ca.key`, `hubble.tls.server.key`, `hubble.relay.tls.client.key`, `hubble.relay.tls.server.key`, `hubble.ui.tls.client.key`, `hubble.metrics.tls.server.key`, `clustermesh.config.clusters[*].tls.key` |

- **Not attributes**: chart versions, IPAM and routing mode, kube-proxy
  replacement, operator replicas, resources, the GatewayClass name; all but
  the chart versions are reachable through `values`.
- **`cluster_network`** (`api_endpoint`, `service_cidr` on aws, `pod_cidr` on
  azure) comes from the foundations' outputs; you never write it. Neither
  do you write, on gcp, `project` (`{ id, number }`, the catalog's
  `inputs.cluster.projectId` and `projectNumber`), `gateway_certificate_map`
  or `gateway_regional_certificate`: the gcp root wires them.

## The bootstrap module's variables

Generated from [`opentofu/bootstrap`](../../opentofu/bootstrap/README.md);
the roots' own variables: [OpenTofu modules](opentofu-modules.md#clustersaws)
and [clusters/gcp](opentofu-modules.md#clustersgcp).

::include{file="opentofu/bootstrap/README.md" section="tf-docs"}
