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
      enabled       = true
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
      enabled       = true
      domain        = ""
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
