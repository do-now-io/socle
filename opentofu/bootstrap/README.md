# Socle bootstrap — Flux, and the inputs the catalog renders from

One module for four clouds. `helm` installs everything that runs in the
cluster — `flux-operator`, a `FluxInstance`, and two literal objects: the
client's inputs and the root source; on aws, `aws` adds the EKS-managed
add-ons and their roles. After that OpenTofu owns those three releases and nothing
else: the operator renders the catalog from the inputs, Flux converges it.

```hcl
module "socle" {
  source = "oci://ghcr.io/do-now-io/socle/opentofu-modules//opentofu/bootstrap?tag=${var.socle_version}"

  cloud        = "aws"
  cluster_name = "acme-prod"
  environment  = "prod"
  owner        = "platform"

  kube = {
    hello = { replicas = 2 }
  }
}
```

The design, and the measurements behind it: [docs/flux-catalog.md](../../docs/flux-catalog.md).

## Where it runs

In the same root as the foundations module, in one apply — see
`opentofu/clusters/<cloud>/`. It configures no provider itself; the root passes
the foundations module's `helm_kubernetes` output to the `helm` provider, and
on aws its own `aws` provider serves both modules. Elsewhere `aws` has no
resource here and is never configured.

## The catalog schema

`kube` is `{ <module> = { <attribute> = <value> } }`. Only what differs from a
default needs writing; an unknown module or attribute, or a value of the wrong
type, is an error at plan, with the allowed list in the message.

| Module | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `gateway_api` | `enabled` | `true` | Gateway API standard CRDs from upstream, pinned by commit, and Cilium's `cilium` class on aws and azure. Offered on aws, azure and scaleway; GKE owns its own. Disabling orphans the CRDs |
| `gateway_api` | `gateways` | `true` | The shared Gateways `gateway-system/public` (internet-facing) and `private` (internal), HTTPS on 443, on aws and azure — on aws once the foundations issued `gateway_certificate`, with no port 80 yet; on azure HTTP on 80 redirects to HTTPS ([design note](../../docs/catalog/gateway-api.md)) |
| `crossplane` | `enabled` | `false` | Deploy Crossplane and, per cloud, its IAM providers — the tooling through which each catalog module declares its own cloud role ([design note](../../docs/catalog/crossplane.md)). Turning it off leaves the CRDs and orphans every module role still declared |
| `crossplane` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan |
| `crossplane` | `values_secret` | `""` | Name of a Secret in `crossplane-system` with a `values.yaml` key, created by the client, merged last |
| `crossplane` | `permissions_boundary` | `""` | AWS: the boundary every module's role carries. The client root wires it from the foundations' `crossplane_permissions_boundary_arn` |
| `external_dns` | `enabled` | `false` | Publish DNS records for Services, Ingresses and HTTPRoutes into the cloud's zone — needs `domain_filters`; on AWS with `crossplane` on it declares its own IAM role, elsewhere the client brings a credential ([design note](../../docs/catalog/external-dns.md)) |
| `external_dns` | `domain_filters` | `[]` | Zones it may write to, as DNS names; required when enabled |
| `external_dns` | `policy` | `"upsert-only"` | `upsert-only` never deletes a record; `sync` also deletes what it owns |
| `external_dns` | `txt_owner_id` | the cluster name | Owner written into the TXT registry, so two clusters never fight over a zone |
| `external_dns` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan |
| `external_dns` | `values_secret` | `""` | Name of a Secret in `external-dns` with a `values.yaml` key, created by the client, merged last |
| `argocd` | `enabled` | `true` | Deploy ArgoCD, the client's GitOps layer ([design note](../../docs/catalog/argocd.md)) |
| `argocd` | `admin_enabled` | `true` | Keep the local `admin` account; `false` once SSO exists |
| `argocd` | `domain` | `""` | Host ArgoCD is served at (`configs.cm.url` and the HTTPRoute); empty means no URL and no route |
| `argocd` | `gateway` | `"private"` | Shared Gateway its HTTPRoute attaches to: `private`, `public`, or `""` for none |
| `argocd` | `ha` | `false` | The chart's HA layout: Redis HA, two replicas of server, repo-server and applicationset |
| `argocd` | `values` | `{}` | The client's own chart values (accounts, RBAC, repositories, SSO connectors, exclusions), merged over the socle's defaults, client wins. Secrets refused at plan |
| `argocd` | `values_secret` | `""` | Name of a Secret in `argocd` with a `values.yaml` key, created by the client, merged last — where the private keys and client secrets go |
| `victoria_metrics` | `enabled` | `true` | Deploy VictoriaMetrics single-node, the monitoring stack's metrics storage: OTLP in, PromQL out, no cloud access ([design note](../../docs/catalog/victoria-metrics.md), [stack](../../docs/monitoring.md)) |
| `victoria_metrics` | `retention` | `"15d"` | How long samples are kept: whole hours, days, weeks or years, at least a day |
| `victoria_metrics` | `storage_size` | `"20Gi"` | Size of the claim on the cluster's default StorageClass, in `Gi` or `Ti`; `""` means no claim, an `emptyDir` — what a socle EKS needs until the EBS CSI driver exists |
| `victoria_metrics` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan; numeric flags written as strings |
| `victoria_metrics` | `values_secret` | `""` | Name of a Secret in `victoria-metrics` with a `values.yaml` key, created by the client, merged last |
| `otel_agent` | `enabled` | `true` | Deploy the OpenTelemetry Collector as a DaemonSet: kubelet metrics for every node, pod and container, to `victoria_metrics` when it is on, and the nodes and pods dashboard ([design note](../../docs/catalog/otel-agent.md)) |
| `otel_agent` | `logs` | `true` | Container logs from `/var/log/pods` (read-only hostPath, root without capabilities) to `victoria_logs` while it is on; `false` keeps the agent to metrics |
| `otel_agent` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Literal credentials refused at plan; `${env:NAME}` read from a Secret is fine |
| `otel_agent` | `values_secret` | `""` | Name of a Secret in `otel-agent` with a `values.yaml` key, created by the client, merged last |
| `otel_gateway` | `enabled` | `true` | Deploy the OpenTelemetry Collector as a one-replica Deployment: Kubernetes object state, the Prometheus endpoints of pods annotated `prometheus.io/scrape`, and the applications' OTLP on `otel-gateway.otel-gateway.svc:4317/4318`, to `victoria_metrics`; ships the workloads dashboard ([design note](../../docs/catalog/otel-gateway.md)) |
| `otel_gateway` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Literal credentials refused at plan; `${env:NAME}` read from a Secret is fine |
| `otel_gateway` | `values_secret` | `""` | Name of a Secret in `otel-gateway` with a `values.yaml` key, created by the client, merged last |
| `grafana` | `enabled` | `true` | Deploy Grafana: a read-only datasource for each monitoring backend that is on, and every dashboard a module ships ([design note](../../docs/catalog/grafana.md)) |
| `grafana` | `domain` | `""` | Host Grafana is served at (`grafana.ini` `server.root_url`, later the HTTPRoute); empty means none |
| `grafana` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan: admin password, secret key, OAuth client secrets, literal datasource secrets |
| `grafana` | `values_secret` | `""` | Name of a Secret in `grafana` with a `values.yaml` key, created by the client, merged last |
| `victoria_logs` | `enabled` | `true` | Deploy VictoriaLogs single-node, the monitoring stack's logs storage: container logs, Kubernetes events and OTLP logs in, LogsQL out, no cloud access ([design note](../../docs/catalog/victoria-logs.md)) |
| `victoria_logs` | `retention` | `"7d"` | How long logs are kept: whole hours, days, weeks or years, at least a day |
| `victoria_logs` | `storage_size` | `"20Gi"` | Size of the claim on the default StorageClass; `""` means an `emptyDir`, as `victoria_metrics` |
| `victoria_logs` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan |
| `victoria_logs` | `values_secret` | `""` | Name of a Secret in `victoria-logs` with a `values.yaml` key, created by the client, merged last |
| `victoria_traces` | `enabled` | `false` | Deploy VictoriaTraces single-node, the applications' OTLP traces through `otel_gateway`, a Jaeger datasource in Grafana. **Off**: pre-GA, an upgrade may drop stored traces ([design note](../../docs/catalog/victoria-traces.md)) |
| `victoria_traces` | `retention` | `"7d"` | How long traces are kept: whole hours, days, weeks or years, at least a day |
| `victoria_traces` | `storage_size` | `"10Gi"` | Size of the claim on the default StorageClass; `""` means an `emptyDir` |
| `victoria_traces` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan |
| `victoria_traces` | `values_secret` | `""` | Name of a Secret in `victoria-traces` with a `values.yaml` key, created by the client, merged last |
| `kyverno` | `enabled` | `false` | Deploy the Kyverno engine: admission (three replicas, a PodDisruptionBudget), background, cleanup and reports controllers, no policy; its webhooks never see `kube-system` or `flux-system`. **Off**: an admission webhook is opted into ([design note](../../docs/catalog/kyverno.md)) |
| `kyverno` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Registry credentials (`imagePullSecrets`) and literal credential env refused at plan |
| `kyverno` | `values_secret` | `""` | Name of a Secret in `kyverno` with a `values.yaml` key, created by the client, merged last |
| `kyverno_policies` | `enabled` | `false` | Deploy the socle's policy set on `kyverno` (required): the Pod Security Standards as CEL policies, requests required, no `latest` tag, every policy in Audit ([design note](../../docs/catalog/kyverno-policies.md)) |
| `kyverno_policies` | `profile` | `"baseline"` | `baseline`, or `restricted` for baseline plus the six restricted policies |
| `kyverno_policies` | `enforce` | `[]` | Policies switched to Enforce, each compiled into a native ValidatingAdmissionPolicy the API server applies with Kyverno up or down; only names this configuration renders |
| `kyverno_policies` | `allowed_registries` | `[]` | Registries images may come from (`ghcr.io`, `registry.k8s.io`, `ghcr.io/acme`); empty means no registry policy |
| `kyverno_policies` | `values` | `{}` | The client's own `kyverno-policies` chart values, merged over the socle's, client wins; a list he sets replaces the socle's whole |
| `kyverno_policies` | `values_secret` | `""` | Name of a Secret in `kyverno-policies` with a `values.yaml` key, created by the client, merged last |
| `hello` | `enabled` | `true` | Deploy podinfo as a proof the pipeline works |
| `hello` | `replicas` | `1` | Replicas of the podinfo Deployment |
| `hello` | `message` | `"hello from socle"` | Message podinfo serves |
| `keda` | `enabled` | `false` | Deploy KEDA, event-driven autoscaling: a `ScaledObject` scales a Deployment on a queue's depth, a cron window or a PromQL query, and down to zero ([design note](../../docs/catalog/keda.md)). Off: it does nothing until a `ScaledObject` exists |
| `keda` | `services` | `[]` | AWS services KEDA's own role may **read**, from `sqs`, `cloudwatch`, `kinesis`, `dynamodb`: one read-only statement per service named, declared through Crossplane, no role when empty. Needs `crossplane` on and the same services in the foundations' `aws.crossplane.allowed_services`; aws only for now |
| `keda` | `values` | `{}` | The client's own chart values, merged over the socle's defaults, client wins. Secrets refused at plan |
| `keda` | `values_secret` | `""` | Name of a Secret in `keda` with a `values.yaml` key, created by the client, merged last |
| `hello` | `enabled` | `true` | Deploy podinfo as a proof the pipeline works |
| `hello` | `replicas` | `1` | Replicas of the podinfo Deployment |
| `hello` | `message` | `"hello from socle"` | Message podinfo serves |

The schema lives in `catalog.tf`; the templates in `oci/catalog/<module>/`;
each `oci/clusters/<cloud>/kustomization.yaml` lists the modules that cloud
offers, and `catalog_clouds` in `catalog.tf` names the clouds a module is bound
to (absent = every cloud). All of it changes in the same release, and CI
(`.github/scripts/check-catalog-clouds.sh`) fails when the overlays and the
schema disagree.

## Cilium, before Flux

On `aws` and `azure` the foundations create a cluster with no CNI, and
nothing without `hostNetwork`, Flux included, starts until one runs. This
module therefore installs Cilium, and on `aws` CoreDNS, before
`flux-operator`. On `gcp` and `scaleway` the cloud operates Cilium and none of
this exists. The Gateway API CRDs are not installed here: the catalog's
`gateway_api` module brings them from upstream once Flux runs. The root
passes `cluster_network` from the foundations' outputs:

```hcl
cilium  = { hubble = true }           # optional: enabled, hubble, gateway_api, values
coredns = { values = { replicaCount = 3 } }         # aws: any CoreDNS chart value
cluster_network = {
  api_endpoint = module.foundations.cluster_endpoint
  service_cidr = module.foundations.service_cidr   # aws
  # pod_cidr   = module.foundations.pod_cidr       # azure
}
```

`values` takes any chart value and is merged after the socle's, so the
client wins. Private keys are refused there, because they would land in the
state: name a Secret through the chart's `existingSecret` fields instead. The
templates see what was decided as `inputs.cilium.{installed, gatewayApi,
hubble}`. The design and what was measured are in
[docs/catalog/cilium.md](../../docs/catalog/cilium.md).

## EKS add-ons, once the nodes run

On `aws` the Pod Identity Agent, EBS CSI and EFS CSI stay EKS-managed
add-ons ([managed scope](../../docs/aws/eks-managed-scope.md)), and this
module creates them — the foundations provision nothing that needs a pod.
The Pod Identity Agent comes after Cilium and before `flux-operator`: every
catalog module that talks to AWS, Crossplane first, gets its credentials from
it, and without it they hang without an error (#48). The two drivers come
after CoreDNS, each with its own role bound through the add-on's
`pod_identity_association`, outside `/socle/<cluster>/`.

```hcl
eks_addons = { efs_csi = true }   # optional: pod_identity_agent (true), ebs_csi (true), efs_csi (false)
```

Versions are pinned in `eks_addons.tf` and move with the socle release. The
drivers need the agent; turning it off with either on is refused at plan.

## What is decided for you

| Decision | Position |
| --- | --- |
| Templating | Flux Operator `ResourceSet`s in the artifact — never Helm, never OpenTofu |
| What OpenTofu ships | Inputs only: one `ResourceSetInputProvider`, one root `ResourceSet` |
| Applier | `helm_release` over `manifests/`, the one provider that needs no CRD at plan |
| Version | `socle_version` defaults to this module's own; one tag bump moves everything |
| Signature | cosign keyless, verified by Flux on every reconciliation, cannot be disabled |
| Default identity | the release workflow on `main` — a branch build needs an explicit override |
| Source kind | OCI only |
| Namespace | `flux-system`, fixed |
| CNI on aws and azure | Cilium 1.20.2, pinned here: ENI IPAM on aws, BYOCNI overlay on azure, kube-proxy replacement on both |
| DNS on aws | CoreDNS by Helm after Cilium; the EKS add-on cannot exist before a CNI |
| Identity on aws | the Pod Identity Agent add-on, before Flux, pinned; IRSA absent |
| Storage on aws | EBS CSI add-on on by default, EFS CSI on request, each with its own Pod Identity role |

## Reading the result

```sh
kubectl -n flux-system get resourcesetinputprovider socle -o yaml   # what the client declared
kubectl -n flux-system get resourceset                              # socle-root and one per module, with Ready
kubectl -n flux-system get ocirepository socle                      # the pulled digest, and SourceVerified
```

Helm's `wait` does not wait for a custom resource to be Ready, so a green
apply proves the objects were deposited, not that they converged. The root
`ResourceSet` (`wait: true`) is the convergence signal; CI reads it.

## Testing

`tofu test` covers the interface — one failing case per validation, and the
defaults and normalisation with mocked helm and aws providers. Convergence is proven
by `publish-artifact.yaml`'s `e2e-aws-root` and `e2e-aws-catalog` jobs, which
apply on floci against the artifact the same commit published; the
integration legs plan only.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0, < 7.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0, < 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_eks_addon.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.pod_identity_agent](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.efs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.cilium](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.coredns](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.instance](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.operator](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.socle](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Which cloud this cluster runs on. Selects the artifact's clusters/<cloud> overlay and the operator's workload identity wiring. Scaleway has no federation the operator knows, so it runs as a plain kubernetes cluster. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster this socle serves. Stamped on every object the operator creates, and exposed to the catalog as inputs.cluster.name. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this cluster serves. Stamped as a label, exposed as inputs.cluster.environment, and the axis the upgrade rings follow. | `string` | n/a | yes |
| <a name="input_owner"></a> [owner](#input\_owner) | Team accountable for the cluster. Stamped as a label on every object. | `string` | n/a | yes |
| <a name="input_artifact_pull_secret"></a> [artifact\_pull\_secret](#input\_artifact\_pull\_secret) | Name of an existing kubernetes.io/dockerconfigjson Secret in flux-system that Flux uses to pull the artifact from a private registry. Empty for a public registry. The Secret is created outside this module — a credential never enters OpenTofu. | `string` | `""` | no |
| <a name="input_artifact_url"></a> [artifact\_url](#input\_artifact\_url) | OCI repository the socle artifact is pulled from. Override for a mirror; the tag is socle\_version. | `string` | `"oci://ghcr.io/do-now-io/socle/flux-modules"` | no |
| <a name="input_cilium"></a> [cilium](#input\_cilium) | The socle's Cilium, on the clouds whose foundations create a cluster with<br/>no CNI — aws and azure — as `{ enabled, hubble, gateway_api }`, every key<br/>optional: `enabled` (true) installs it before Flux; false means the<br/>cluster brings its own CNI and DNS, which only a test double does.<br/>`hubble` (false) adds Hubble Relay and UI. `gateway_api` (true) makes<br/>Cilium serve the `cilium` GatewayClass. `values` ({}) is any Cilium chart<br/>value, merged over the socle's so the client wins; private keys are<br/>refused there, and the chart's `existingSecret` fields name a Secret<br/>instead. Refused on gcp and scaleway, where the cloud operates Cilium.<br/>Typed `any` and validated like `kube`, so a misspelt key is an error at<br/>plan. Chart versions are pinned in cilium.tf. | `any` | `{}` | no |
| <a name="input_cluster_network"></a> [cluster\_network](#input\_cluster\_network) | What Cilium needs to know about the cluster, from the foundations'<br/>outputs, never from the client: `api_endpoint`, the API server as EKS<br/>returns it (https://host) or AKS does (a bare FQDN), for kube-proxy<br/>replacement; `service_cidr`, the service range, whose `.10` is CoreDNS's<br/>address on aws; `pod_cidr`, Cilium's pool on azure, where the VNet holds<br/>nodes only. Required wherever the socle installs Cilium, ignored<br/>elsewhere. | <pre>object({<br/>    api_endpoint = string<br/>    service_cidr = optional(string)<br/>    pod_cidr     = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_coredns"></a> [coredns](#input\_coredns) | The CoreDNS the socle installs on aws, right after Cilium, as<br/>`{ values }`: `values` ({}) is any CoreDNS chart value, merged over the<br/>socle's so the client wins — extra zones, forwarders, plugins. The chart<br/>has no value that takes secret material inline; a Secret is mounted by<br/>name through `extraSecrets`, or read through `env[].valueFrom`. Refused<br/>where the socle installs no CoreDNS: every cloud but aws, and aws with<br/>cilium.enabled = false. Chart version pinned in cilium.tf. | `any` | `{}` | no |
| <a name="input_cosign_identity"></a> [cosign\_identity](#input\_cosign\_identity) | Keyless identity the artifact's signature must match, as issuer and subject regexes. Defaults to the socle's release workflow on main, so production never consumes a branch build by accident. Override on a dev cluster testing a branch. Null means this default. Verification cannot be disabled. | <pre>object({<br/>    issuer  = string<br/>    subject = string<br/>  })</pre> | <pre>{<br/>  "issuer": "^https://token\\.actions\\.githubusercontent\\.com$",<br/>  "subject": "^https://github\\.com/do-now-io/socle/\\.github/workflows/publish-artifact\\.yaml@refs/heads/main$"<br/>}</pre> | no |
| <a name="input_eks_addons"></a> [eks\_addons](#input\_eks\_addons) | The EKS-managed add-ons the socle installs on aws once the nodes run, as<br/>`{ pod_identity_agent, ebs_csi, efs_csi }`, every key optional:<br/>`pod_identity_agent` (true) is what hands every Pod Identity association<br/>its credentials — Crossplane's AWS providers included — and flux-operator<br/>waits for it; `ebs_csi` (true) is the block-storage driver, with its own<br/>role; `efs_csi` (false) the RWX one, with its own role. Both drivers need<br/>the agent. Refused on every cloud but aws. Versions pinned in<br/>eks\_addons.tf. | `any` | `{}` | no |
| <a name="input_flux_components"></a> [flux\_components](#input\_flux\_components) | Flux controllers to install. The image automation pair is absent by default: the socle's version moves through a reviewed tfvars change, not through a controller rewriting tags. | `list(string)` | <pre>[<br/>  "source-controller",<br/>  "kustomize-controller",<br/>  "helm-controller",<br/>  "notification-controller"<br/>]</pre> | no |
| <a name="input_flux_version"></a> [flux\_version](#input\_flux\_version) | Flux version the operator installs and keeps converged. 2.x tracks the latest 2 series; an exact version pins it. | `string` | `"2.x"` | no |
| <a name="input_gateway_certificate_arn"></a> [gateway\_certificate\_arn](#input\_gateway\_certificate\_arn) | On aws, the ACM certificate the shared Gateways' load balancers terminate<br/>TLS with — the foundations' gateway\_certificate\_arn output, never the<br/>client's. Null or empty on aws means no shared Gateway, and no route<br/>attached to one. Unknown at plan on the apply that issues it, which is<br/>why nothing validates it here. Ignored elsewhere. | `string` | `null` | no |
| <a name="input_helm_timeout_seconds"></a> [helm\_timeout\_seconds](#input\_helm\_timeout\_seconds) | How long to wait for each release to become ready. The instance release is the slow one: its health check waits for the operator to converge the controllers. | `number` | `600` | no |
| <a name="input_instance_size"></a> [instance\_size](#input\_instance\_size) | Resource profile the operator applies to the controllers. Empty is the operator's own default; small, medium and large scale requests and limits together. | `string` | `""` | no |
| <a name="input_kube"></a> [kube](#input\_kube) | The catalog modules this cluster enables and their values, as<br/>`{ <module> = { <attribute> = <value> } }`. List only what differs from<br/>the catalog's defaults; an absent module is at its default. Module names<br/>are snake\_case. Typed `any` on purpose: a map(any) refuses two modules with<br/>different attributes, and an object type silently drops a misspelt<br/>attribute — the validations below are what makes a typo an error at plan.<br/>The schema is catalog.tf; the README lists it module by module. | `any` | `{}` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Let the operator install network policies isolating the Flux namespace. On by default; Cilium enforces them on every cloud we ship. | `bool` | `true` | no |
| <a name="input_operator_version"></a> [operator\_version](#input\_operator\_version) | Chart version of flux-operator, which is also the operator's own version. Pinned exactly: the operator is pre-1.0 and its minors are not a stable contract. | `string` | `"0.60.0"` | no |
| <a name="input_region"></a> [region](#input\_region) | Region the cluster runs in, exposed to the catalog as inputs.cluster.region. Regional cloud APIs need it — on AWS the Pod Identity associations the crossplane module creates. Empty when the caller does not know it; a module that needs it says so. | `string` | `""` | no |
| <a name="input_schedulable_nodes"></a> [schedulable\_nodes](#input\_schedulable\_nodes) | How many nodes the foundations give the cluster before this module<br/>starts — on aws, the bootstrap node group's size. Everything but Cilium<br/>waits for it: Cilium's DaemonSet is what makes those nodes Ready, so it<br/>is installed beside them, and CoreDNS and the Flux operator, the first<br/>releases that need a scheduled pod, come after. Zero fails the plan with<br/>that reason, instead of Helm waiting helm\_timeout\_seconds for a node.<br/>Null skips the check, on a cluster whose compute this module cannot see. | `number` | `null` | no |
| <a name="input_socle_version"></a> [socle\_version](#input\_socle\_version) | Tag of the socle artifact to pull. Null means this module's own version, so that one bump of the module tag moves module and artifact together. Set it only on a dev cluster testing a branch build, together with cosign\_identity. | `string` | `null` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the source-controller's artifact cache. Empty uses the cluster default. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_artifact"></a> [artifact](#output\_artifact) | The socle artifact, as OCI URL and tag. |
| <a name="output_cilium"></a> [cilium](#output\_cilium) | Whether this module installed Cilium (aws, azure: the clouds whose foundations create a cluster with no CNI), with the chart versions it pinned. installed is false where the cloud operates Cilium, or when cilium.enabled is false. |
| <a name="output_cosign_identity"></a> [cosign\_identity](#output\_cosign\_identity) | Keyless identity the artifact's signature is verified against, on every reconciliation. |
| <a name="output_eks_addons"></a> [eks\_addons](#output\_eks\_addons) | The EKS-managed add-ons this module installed (aws only), each as its pinned version, and for the two storage drivers the ARN of the role their controller runs as. Null for an add-on not installed. |
| <a name="output_flux_version"></a> [flux\_version](#output\_flux\_version) | Flux version the operator converges the controllers to. |
| <a name="output_inputs"></a> [inputs](#output\_inputs) | What this module ships into the cluster as the ResourceSetInputProvider's defaultValues, after normalisation against the catalog. The catalog's templates read exactly these paths. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace holding the operator, the Flux controllers and the socle's inputs. |
| <a name="output_operator_version"></a> [operator\_version](#output\_operator\_version) | Version of flux-operator installed, which is also its chart version. |
| <a name="output_socle_version"></a> [socle\_version](#output\_socle\_version) | Tag of the socle artifact the cluster pulls. |
<!-- END_TF_DOCS -->
