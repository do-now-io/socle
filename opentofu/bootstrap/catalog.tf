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
      # docs/architecture/flux-catalog.md#how-values-merge: free-form chart
      # values, and the name of a Secret the client creates in the
      # external-dns namespace for what must not reach the OpenTofu state.
      values        = {}
      values_secret = ""
    }
    # The Gateway API standard CRDs, from upstream pinned by commit, and on
    # the clouds where the socle runs Cilium, the `cilium` GatewayClass and
    # the one operator restart that turns Cilium's controller on
    # (docs/catalog/gateway-api.md). On gcp GKE owns the CRDs and the
    # controller: the module renders the shared Gateways only. No chart, so
    # no values/values_secret. Disabling it removes the Flux objects and
    # orphans the CRDs: every Gateway survives.
    #
    # gateways: the two shared Gateways every module and the client route
    # through, `public` (internet-facing) and `private` (internal), in
    # gateway-system — HTTPS on 443 (on azure and gcp also HTTP on 80, redirecting;
    # not on aws yet, docs/catalog/gateway-api.md). Created where a class
    # serves them — the socle's Cilium (aws, azure) or GKE's (gcp) — and, on
    # aws and gcp, only once the foundations issued their certificate(s):
    # TLS terminates at the load balancer (docs/catalog/gateway-api.md).
    # false keeps the CRDs and the class, and no Gateway.
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
    # dns_records_role (GCP) takes its place there: the project custom role
    # Crossplane grants external-dns to write DNS records — wired by the gcp
    # root from the foundations' dns_records_role.
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
      dns_records_role     = ""
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
    # Argo CD Image Updater: moves the client's ArgoCD Applications to the
    # new image tags their ImageUpdater objects allow, without a commit
    # (docs/catalog/argocd-image-updater.md). Off by default, and refused
    # while argocd is off: it does nothing until the client writes an
    # ImageUpdater, in argocd. Runs in its own namespace, watching argocd.
    # repositories names the ECR repositories of the cluster's account and
    # region its own role may read, globs allowed; on aws with crossplane on,
    # the module declares that read-only role and the registry entry whose
    # token a login script renews. On gcp each entry is LOCATION/REPOSITORY
    # of the cluster's project: with crossplane on, the module binds
    # roles/artifactregistry.reader on the project to its own Workload
    # Identity principal, and writes one registry entry per location
    # (<location>-docker.pkg.dev). Empty means no access and no entry.
    # registries is the client's other registries, as Image Updater writes
    # them, rendered after the socle's ECR entry: a registry entry is never
    # set through values, whose list would replace the socle's. Credentials
    # are references to a Secret, never literals. values and values_secret
    # as every module, secrets refused there.
    argocd_image_updater = {
      enabled       = false
      repositories  = []
      registries    = []
      values        = {}
      values_secret = ""
    }
    # The monitoring stack (docs/architecture/observability.md), the
    # official victoria-metrics-k8s-stack chart as one release: the
    # VictoriaMetrics operator, vmagent scraping the cluster (kubelets,
    # cAdvisor, kube-state-metrics, node-exporter, every annotated pod), and
    # the parts below, each in the monitoring namespace (docs/catalog/monitoring.md).
    # metrics is VictoriaMetrics single-node, always there while the module
    # is: retention a VictoriaMetrics duration, at least a day; storage_size
    # the PVC on the default StorageClass, empty for an emptyDir — the escape
    # for a cluster with no default class. logs is VictoriaLogs and traces
    # VictoriaTraces, the same shape; traces OFF by default, pre-GA, its
    # storage format not yet committed. grafana reads them all; domain is the
    # host it is served at, gateway the shared Gateway its HTTPRoute attaches
    # to, as argocd's. alerting is vmalert and Alertmanager with the rules
    # kube-prometheus-stack installs, OFF by default: on, it needs where
    # alerts go, which only the client knows — receivers and route, as
    # Alertmanager writes them, keys only as *_file paths under
    # /etc/alertmanager/secrets/, where receivers_secret (a Secret the client
    # creates in monitoring) is mounted — and, unless watchdog = false, a dead
    # man's switch whose URL is that Secret's watchdog-url key. values and
    # values_secret as every module, for the one chart; the rules' sources,
    # Alertmanager's configuration and secrets refused there.
    monitoring = {
      enabled = true
      metrics = {
        retention    = "15d"
        storage_size = "20Gi"
      }
      logs = {
        enabled      = true
        retention    = "7d"
        storage_size = "20Gi"
      }
      traces = {
        enabled      = false
        retention    = "7d"
        storage_size = "10Gi"
      }
      grafana = {
        enabled = true
        domain  = ""
        gateway = "private"
      }
      alerting = {
        enabled          = false
        watchdog         = true
        receivers        = []
        route            = {}
        receivers_secret = ""
      }
      values        = {}
      values_secret = ""
    }
    # The node-level collector (docs/architecture/observability.md): the
    # OpenTelemetry Collector as a DaemonSet, every container's log to
    # monitoring's VictoriaLogs, with its pod's metadata. Deployed only while
    # monitoring runs its logs; no metric of its own, vmagent scrapes the
    # nodes. No port on the node: applications speak to otel_gateway. values
    # and values_secret as every module, secrets refused there
    # (docs/catalog/otel-agent.md).
    otel_agent = {
      enabled       = true
      values        = {}
      values_secret = ""
    }
    # The cluster-level collector: the OpenTelemetry Collector as a
    # one-replica Deployment, the applications' OTLP on
    # otel-gateway.otel-gateway.svc:4317/4318, and the Kubernetes events as
    # logs, to the monitoring module's backends. No named attribute: every
    # knob is chart configuration, which values is for; secrets refused there
    # as in otel_agent (docs/catalog/otel-gateway.md).
    otel_gateway = {
      enabled       = true
      values        = {}
      values_secret = ""
    }
    # KEDA: event-driven autoscaling — a ScaledObject scales a Deployment on a
    # queue's depth, a cron window or a PromQL query, and down to zero. Off
    # by default: KEDA does nothing until a client writes a ScaledObject.
    # services names the cloud's services the operator's OWN role may read —
    # on aws sqs, cloudwatch, kinesis, dynamodb, on gcp pubsub — and the
    # module declares that access through Crossplane, scoped per service
    # named, nothing for the rest, nothing at all when the list is empty
    # (docs/catalog/keda.md). A non-empty list needs kube.crossplane on and
    # the matching allowance in the foundations (aws.crossplane.
    # allowed_services, gcp crossplane.allowed_roles); refused at plan
    # otherwise (variables.tf). Cron, Prometheus, Kafka,
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
    # External Secrets Operator: an ExternalSecret becomes a Kubernetes Secret
    # read from the cloud's own secret manager, kept in step when the value
    # rotates there (pair it with reloader for the pods to roll). Off by
    # default. On AWS with crossplane on, the module declares its own
    # READ-ONLY role — GetSecretValue and DescribeSecret on secret:<prefix>/*
    # for each prefix, in the cluster's region — and one ClusterSecretStore,
    # secret-manager, on it. prefixes defaults to the cluster name; empty
    # means no role and no store. Elsewhere, or with crossplane off, the
    # operator is installed alone and the client brings his stores
    # (docs/catalog/external-secrets.md). values and values_secret as every
    # module, secrets refused there.
    external_secrets = {
      enabled       = false
      prefixes      = [var.cluster_name]
      values        = {}
      values_secret = ""
    }
    reloader = {
      enabled       = false
      values        = {}
      values_secret = ""
    }
    # Backup and restore of what GitOps cannot restore — the data in the
    # applications' EBS and EFS volumes, with their objects
    # (docs/catalog/velero.md). On aws and gcp, and off by default: it needs
    # Crossplane, which makes its bucket and its access. Nothing is backed up
    # unless an application opts in, its chart labelling every object of its
    # release with socle.do-now.io/backup-frequency and
    # socle.do-now.io/backup-retention: each entry of policies is one such
    # pair, rendered as one Schedule, and a pair absent from it backs nothing
    # up — a warning at admission says so. EBS volumes are CSI snapshots, EFS
    # volumes a file-system backup through the node-agent, a privileged
    # DaemonSet installed only when node_agent is on (by default when the EFS
    # driver is; never on gcp, where Autopilot forbids its hostPath and every
    # volume is a PD snapshot). values and values_secret as every module;
    # credentials are refused in values.
    velero = {
      enabled = false
      policies = [
        { frequency = "hourly", retention = "24h", schedule = "0 * * * *" },
        { frequency = "hourly", retention = "48h", schedule = "0 * * * *" },
        { frequency = "daily", retention = "7d", schedule = "0 2 * * *" },
        { frequency = "daily", retention = "30d", schedule = "0 2 * * *" },
        { frequency = "weekly", retention = "30d", schedule = "30 2 * * 0" },
        { frequency = "weekly", retention = "90d", schedule = "30 2 * * 0" },
        { frequency = "monthly", retention = "90d", schedule = "0 3 1 * *" },
      ]
      node_agent    = local.eks_addon_installed.efs_csi
      values        = {}
      values_secret = ""
    }
    # metrics-server: serves the metrics.k8s.io API, the latest CPU and memory
    # of every node and pod, read by kubectl top and by every
    # HorizontalPodAutoscaler on CPU or memory. Not monitoring: no history.
    # On by default: without it every such HPA stays blind, which a client
    # finds out under load, and it needs no client input. aws only — gcp,
    # azure and scaleway ship their own, and a second one cannot coexist
    # (catalog_clouds below). ha runs two replicas, spread across nodes, with
    # a disruption budget. values and values_secret as every module; the plan
    # refuses --kubelet-insecure-tls in values — docs/catalog/metrics-server.md.
    metrics_server = {
      enabled       = true
      ha            = false
      values        = {}
      values_secret = ""
    }
    # Karpenter: the autoscaler that owns every node but the bootstrap group's
    # (docs/catalog/karpenter.md). aws only — GKE Autopilot provisions its
    # own nodes, and Karpenter has no provider there (catalog_clouds below).
    # Off by default: it needs Crossplane, which makes its role and its
    # interruption queue, and ec2, ssm, pricing, sqs and eks in the
    # foundations' crossplane.allowed_services. Its nodes run as the
    # bootstrap nodes' role, through the instance profile the foundations
    # create for it. Two NodePools, always: private_pool, where a pod goes by
    # default, in the private subnets, its egress through the NAT Gateway;
    # public_pool, tainted socle.do-now.io/node-pool=public, for the
    # workloads costly in network traffic that tolerate it, in the public
    # subnets with a public IP, their egress through the Internet Gateway.
    # Each: the capacity_types (spot, on-demand) and architectures (arm64,
    # amd64) it may launch — Karpenter launches the cheapest that fits, so
    # Spot and Graviton first, as for the bootstrap group — cpu and memory
    # the ceiling of all its nodes together, consolidate_after how long a
    # node stays empty or under-used before it goes, and ami the EC2NodeClass
    # alias (al2023@latest follows each new AMI; al2023@v<date> pins one). A
    # client writes more NodePools himself. values and values_secret as every
    # module; credentials are refused in values.
    karpenter = {
      enabled = false
      private_pool = {
        capacity_types    = ["spot", "on-demand"]
        architectures     = ["arm64", "amd64"]
        cpu               = 32
        memory            = "128Gi"
        consolidate_after = "1m"
        ami               = "al2023@latest"
      }
      public_pool = {
        capacity_types    = ["spot", "on-demand"]
        architectures     = ["arm64", "amd64"]
        cpu               = 32
        memory            = "128Gi"
        consolidate_after = "1m"
        ami               = "al2023@latest"
      }
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
    gateway_api    = ["aws", "azure", "gcp", "scaleway"]
    karpenter      = ["aws"]
    metrics_server = ["aws"]
    velero         = ["aws", "gcp"]
  }

  # The services kube.keda.services may name, per cloud: those whose scaler
  # the cloud's part of the keda module scopes to its exact read calls
  # (oci/clusters/<cloud>/keda/patch.yaml). Adding one is a statement there
  # and a word here. On gcp pubsub's scaler reads Cloud Monitoring:
  # roles/monitoring.viewer on the project. A cloud absent here gives the
  # operator no cloud access.
  keda_services = {
    aws = ["sqs", "cloudwatch", "kinesis", "dynamodb"]
    gcp = ["pubsub"]
  }
  # The keys an Alertmanager receiver takes in clear, each with a *_file twin
  # that reads it from a file: kube.monitoring.alerting.receivers refuses these, so no
  # webhook URL, token or password lands in the state (docs/catalog/monitoring.md).
  alerting_literal_keys = [
    "api_url", "api_key", "app_token", "routing_key", "service_key", "auth_password",
    "auth_secret", "url", "webhook_url", "token", "token_id", "bot_token", "user_key",
    "api_secret",
  ]
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

  # One level deeper for an attribute whose default is itself a non-empty
  # object (monitoring.logs, monitoring.alerting…): a client who writes
  # logs = { retention = "30d" } keeps the other keys at their default. An
  # empty default ({}, as values or route) is free-form and taken whole.
  # A list of one-key objects spread into merge(), not a map: a map would
  # unify its values to one type, and turn every bool in them into a string.
  modules = {
    for m, d in local.catalog : m => merge(d, try(var.kube[m], {}), [
      for a, x in try(var.kube[m], {}) : { (a) = merge(d[a], x) }
      if length(try(keys(lookup(d, a, null)), [])) > 0 && can(keys(x))
    ]...)
  }

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
