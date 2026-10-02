# The catalog schema. One entry per module; its defaults ARE its schema: the
# attribute names a client may set, and what each is when he does not. The
# validations in variables.tf refuse anything outside this map, and
# local.modules merges the client's values over it so that every module and
# every attribute is present in what reaches the cluster — the artifact's
# templates test values, never presence.
#
# Adding a module to the catalog is an entry here, a folder under oci/catalog/
# and a line in every oci/clusters/<cloud>/kustomization.yaml it exists on
# (catalog_clouds below says which) — in the same release. They travel
# together because module and artifact share socle_version.
locals {
  catalog = {
    # v1: proves the pipeline end to end. A real module reads exactly like it.
    hello = {
      enabled  = true
      replicas = 1
      message  = "hello from socle"
    }
    # external-dns: publishes DNS records for Services, Ingresses and Gateway
    # API HTTPRoutes into the cloud's zone (Route 53, Cloud DNS, Azure DNS,
    # Scaleway DNS — the template picks the provider). Off by default: it
    # needs a zone to publish into, which has no default. On AWS with
    # crossplane on, it declares its own IAM role and Pod Identity
    # association; elsewhere the client brings a credential — see
    # docs/catalog/external-dns.md. When enabled, domain_filters is required
    # (variables.tf). txt_owner_id
    # defaults to the cluster name so two clusters never fight over one zone.
    external_dns = {
      enabled        = false
      domain_filters = []
      policy         = "upsert-only"
      txt_owner_id   = var.cluster_name
      # docs/flux-catalog.md §6: free-form chart values, and the name of a
      # Secret the client creates in the external-dns namespace for what must
      # not reach the OpenTofu state.
      values        = {}
      values_secret = ""
    }
    # The Gateway API standard CRDs, from upstream pinned by commit, and on
    # the clouds where the socle runs Cilium, the `cilium` GatewayClass and
    # the one operator restart that turns Cilium's controller on
    # (docs/catalog/cilium.md §4). Not on gcp, where GKE owns the CRDs and
    # the controller. No chart, so no values/values_secret. Disabling it
    # removes the Flux objects and orphans the CRDs: every Gateway survives.
    #
    # gateways: the two shared Gateways every module and the client route
    # through, `public` (internet-facing) and `private` (internal), in
    # gateway-system — HTTPS on 443 (on azure also HTTP on 80, redirecting;
    # not on aws yet, docs/catalog/gateway-api.md). Created where
    # the socle's Cilium serves Gateway API (aws, azure), and on aws only
    # once the foundations issued their certificate: TLS terminates at the
    # load balancer (docs/catalog/gateway-api.md). false keeps the CRDs and
    # the class, and no Gateway.
    gateway_api = {
      enabled  = true
      gateways = true
    }
    # The tooling through which every catalog module carries its own cloud
    # IAM: Crossplane and, per cloud, the IAM providers and their
    # ProviderConfig (on AWS: provider-aws-iam and -eks, on Pod Identity). A
    # module that needs a cloud service declares its own role in its own
    # ResourceSet (docs/catalog/crossplane.md); nothing here names a module.
    # Off by default until the first module that needs cloud access defaults
    # on — that module's PR flips this too.
    # values is the client's own chart values, merged over the socle's, his
    # winning; secrets are refused there and go in values_secret, a Secret he
    # creates in crossplane-system with a values.yaml key, never read by
    # OpenTofu. permissions_boundary (AWS) is the policy every module's role
    # must carry — the client root wires it from the foundations'
    # crossplane_permissions_boundary_arn; empty means the roles are created
    # without one, which the foundations' Crossplane identity refuses.
    #
    # WARNING — turning it off does not delete what it provisioned. The
    # namespace and the release go; the CRDs and the crossplane-no-usages
    # webhook stay, and so does every module role still declared, orphaned
    # in the cloud with nothing left to reconcile or delete it. Turn those
    # modules off first, wait for their roles to be gone, then
    # enabled = false.
    crossplane = {
      enabled              = false
      values               = {}
      values_secret        = ""
      permissions_boundary = ""
    }
    # The client's GitOps layer: the official argo-cd chart, non-HA, ClusterIP,
    # no SSO. On by default: it is what a client gets a socle for, and it
    # converges on floci's k3s (docs/catalog/argocd.md). domain is the host
    # ArgoCD believes it is served at (configs.cm.url, later the HTTPRoute);
    # empty means no URL. ha flips the chart's documented HA layout as one
    # switch. admin_enabled=false removes the local admin once SSO exists.
    # values is the client's own chart values — accounts, RBAC, repositories,
    # SSO connectors, exclusions — deep-merged by helm-controller over the
    # socle's defaults, the client's winning. Secrets are refused there (they
    # would land in the state and in a plain ConfigMap): a private key or a
    # client secret goes in values_secret, a Secret the client creates in the
    # argocd namespace with a values.yaml key, merged the same way and never
    # read by OpenTofu.
    # gateway is the shared Gateway its HTTPRoute attaches to, `private` by
    # default — ArgoCD is an operator's tool, not an internet service —
    # `public`, or "" for no route. The route exists only with a domain and
    # the shared Gateways (inputs.gateway.shared).
    argocd = {
      enabled       = true
      admin_enabled = true
      domain        = ""
      gateway       = "private"
      ha            = false
      values        = {}
      values_secret = ""
    }
    # The monitoring stack's metrics storage (docs/monitoring.md):
    # VictoriaMetrics single-node, OTLP in from the collectors, PromQL out to
    # Grafana, no cloud access. On by default, like every monitoring module but
    # traces. retention is a VictoriaMetrics duration, at least a day.
    # storage_size sizes the PVC on the cluster's default StorageClass; empty
    # means no claim at all, an emptyDir — the escape for a cluster with no
    # default class, which a socle EKS is until the EBS CSI driver exists
    # (docs/catalog/victoria-metrics.md). values and values_secret as every
    # module: the client's chart values, his winning, secrets refused there
    # and put in a Secret he creates in victoria-metrics instead.
    victoria_metrics = {
      enabled       = true
      retention     = "15d"
      storage_size  = "20Gi"
      values        = {}
      values_secret = ""
    }
    # The node-level collector of the monitoring stack (docs/monitoring.md):
    # the OpenTelemetry Collector as a DaemonSet, kubelet metrics for every
    # node, pod and container, exported to victoria_metrics when it is on —
    # nowhere otherwise. Ships the nodes and pods dashboard. No port on the
    # node: applications speak to otel_gateway. No named attribute yet; the
    # logs switch arrives with victoria_logs. values and values_secret as every
    # module, secrets refused there (docs/catalog/otel-agent.md).
    otel_agent = {
      enabled = true
      # Container logs to victoria_logs while it is on; false keeps the
      # agent to metrics, for a cluster whose logs go elsewhere, or where the
      # read-only hostPath on /var/log/pods is refused (Baseline Pod Security).
      logs          = true
      values        = {}
      values_secret = ""
    }
    # The cluster-level collector of the monitoring stack: the OpenTelemetry
    # Collector as a one-replica Deployment — Kubernetes object state
    # (k8s_cluster), the Prometheus endpoints of pods annotated
    # prometheus.io/scrape, and the applications' OTLP on
    # otel-gateway.otel-gateway.svc:4317/4318 — exported to victoria_metrics
    # when it is on. Ships the workloads dashboard. No named attribute: every
    # knob is chart configuration, which values is for; secrets refused there
    # as in otel_agent (docs/catalog/otel-gateway.md).
    otel_gateway = {
      enabled       = true
      values        = {}
      values_secret = ""
    }
    # The monitoring stack's one place to read (docs/monitoring.md §5):
    # Grafana from the grafana-community chart, a read-only datasource for
    # each backend that is on, and every dashboard a module ships as a
    # ConfigMap labelled grafana_dashboard. ClusterIP, no persistence, the
    # chart's random admin password. domain is the host Grafana believes it is
    # served at (grafana.ini server.root_url, later the HTTPRoute), validated as
    # argocd's; empty means none. values and values_secret as every module,
    # secrets refused there (docs/catalog/grafana.md).
    grafana = {
      enabled = true
      domain  = ""
      # The shared Gateway its HTTPRoute attaches to, as argocd's: private by
      # default, public, or "" for no route. The route exists only with a
      # domain and the shared Gateways (inputs.gateway.shared).
      gateway       = "private"
      values        = {}
      values_secret = ""
    }
    # The monitoring stack's logs storage (docs/monitoring.md): VictoriaLogs
    # single-node, OTLP in from both collectors — container logs from
    # otel_agent, Kubernetes events and the applications' logs from
    # otel_gateway — LogsQL out to Grafana. Same shape as victoria_metrics:
    # retention (7 days) and storage_size (20Gi, empty for an emptyDir), values
    # and values_secret, secrets refused there (docs/catalog/victoria-logs.md).
    victoria_logs = {
      enabled       = true
      retention     = "7d"
      storage_size  = "20Gi"
      values        = {}
      values_secret = ""
    }
    # The monitoring stack's traces storage (docs/monitoring.md): VictoriaTraces
    # single-node, the applications' OTLP traces in through otel_gateway, the
    # Jaeger query API out to Grafana. OFF by default: pre-GA, its storage
    # format not yet committed, so an upgrade may drop stored traces — turning
    # it on accepts that. Same shape as victoria_logs, 10Gi by default
    # (docs/catalog/victoria-traces.md).
    victoria_traces = {
      enabled       = false
      retention     = "7d"
      storage_size  = "10Gi"
      values        = {}
      values_secret = ""
    }
    # KEDA: event-driven autoscaling — a ScaledObject scales a Deployment on a
    # queue's depth, a cron window or a PromQL query, and down to zero. Off
    # by default: KEDA does nothing until a client writes a ScaledObject.
    # services names the AWS services the operator's OWN role may read —
    # sqs, cloudwatch, kinesis, dynamodb — and the module declares that role
    # through Crossplane with one read-only statement per service named,
    # nothing for the rest, no role at all when the list is empty
    # (docs/catalog/keda.md). A non-empty list needs kube.crossplane on and
    # each service in the foundations' aws.crossplane.allowed_services;
    # refused at plan otherwise (variables.tf). Cron, Prometheus, Kafka,
    # RabbitMQ and Redis triggers need no cloud, so no entry.
    keda = {
      enabled       = false
      services      = []
      values        = {}
      values_secret = ""
    }
    # The admission layer (docs/catalog/kyverno.md): the Kyverno engine —
    # admission controller (three replicas behind a PodDisruptionBudget),
    # background and reports controllers, no cleanup controller — from the
    # official chart,
    # and no policy: those are kyverno_policies'. Off by default: an admission
    # webhook on every cluster is something a client opts into. No cloud
    # access. Its webhooks never see kube-system or flux-system. values and
    # values_secret as every module, secrets refused there (the chart's
    # imagePullSecrets credentials, an extraEnvVars entry named like one).
    kyverno = {
      enabled       = false
      values        = {}
      values_secret = ""
    }
    # The socle's baseline policy set, on the kyverno engine
    # (docs/catalog/kyverno-policies.md): the Pod Security Standards from the
    # official kyverno-policies chart as CEL ValidatingPolicy objects, plus
    # requests required and the latest tag refused. Off by default, and
    # refused without kyverno. Every policy in Audit: reported, admitted.
    # Scope: the client's applications — every namespace the socle renders is
    # out of every policy, by the operator's label.
    # profile is baseline or restricted (baseline plus six). enforce names the
    # policies the client switches to Enforce, each compiled into a native
    # ValidatingAdmissionPolicy that the API server applies with Kyverno up or
    # down. allowed_registries, when not empty, adds a policy admitting images
    # from those registries only (each a host, optionally a path under it).
    kyverno_policies = {
      enabled            = false
      profile            = "baseline"
      enforce            = []
      allowed_registries = []
      values             = {}
      values_secret      = ""
    }
    # Stakater Reloader: rolls a workload when a ConfigMap or Secret it reads
    # changes — the other half of external_secrets, whose rotated Secrets a
    # running pod never re-reads, and useful alone for ConfigMaps. Opt-in per
    # workload through Reloader's annotations (reloader.stakater.com/auto),
    # never autoReloadAll, which values refuses (variables.tf). Off by
    # default: it reads every ConfigMap and Secret of the cluster, a grant the
    # client chooses (docs/catalog/reloader.md). No named attribute; values and
    # values_secret as every module.
    reloader = {
      enabled       = false
      values        = {}
      values_secret = ""
    }
  }

  # Which clouds a module exists on. Absent = every cloud. A module listed
  # here is offered only by the oci/clusters/<cloud>/ overlays named, and
  # .github/scripts/check-catalog-clouds.sh fails CI when an overlay and this
  # map disagree — the overlay is what deploys, this map is what the client
  # may configure, and they must say the same thing. The script reads this
  # block by shape: one `name = ["cloud", ...]` per line.
  # var.kube refuses at plan a module this map does not offer on var.cloud.
  catalog_clouds = {
    gateway_api = ["aws", "azure", "scaleway"]
  }

  # The AWS services kube.keda.services may name: those whose scaler the
  # keda template scopes to its exact read calls (oci/catalog/keda/
  # resourceset.yaml). Adding one is a statement there and a word here.
  keda_services = ["sqs", "cloudwatch", "kinesis", "dynamodb"]
  # The policies kyverno_policies renders, by what turns them on: what
  # kube.kyverno_policies.enforce may name. The chart's lists are those of
  # kyverno-policies 3.9.1 (templates/baseline, templates/restricted); the
  # socle's are in oci/catalog/kyverno-policies/resourceset.yaml.
  kyverno_policies = {
    baseline = [
      "disallow-capabilities", "disallow-host-namespaces", "disallow-host-path",
      "disallow-host-ports", "disallow-host-process", "disallow-privileged-containers",
      "disallow-proc-mount", "disallow-selinux", "restrict-apparmor-profiles",
      "restrict-seccomp", "restrict-sysctls",
    ]
    restricted = [
      "disallow-capabilities-strict", "disallow-privilege-escalation", "require-run-as-non-root-user",
      "require-run-as-nonroot", "restrict-seccomp-strict", "restrict-volume-types",
    ]
    socle = ["require-requests", "disallow-latest-tag"]
    # Rendered only when allowed_registries names at least one registry.
    registries = ["restrict-image-registries"]
  }

  modules = { for m, d in local.catalog : m => merge(d, try(var.kube[m], {})) }

  # jsonencode's first character tells a value's kind without a type()
  # function: `"` string, `[` list, `{` object, t/f bool, n null, else number.
  json_kinds = {
    "\"" = "string"
    "["  = "list"
    "{"  = "object"
    "t"  = "bool"
    "f"  = "bool"
    "n"  = "null"
  }
}
