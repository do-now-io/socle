# Cilium in the socle

Where Cilium runs on each cloud, who installs it, what a client may set, and
what the other catalog modules can rely on. Part of issue #32.

| Question | Position |
| --- | --- |
| Is Cilium a catalog module | **No.** On the two clouds where the socle installs it, Flux cannot run until it does |
| Who installs it on AWS and Azure | The bootstrap module, as Helm releases **before** `flux-operator` |
| GCP, Scaleway | Nothing installed: the cloud operates Cilium; `cilium` is refused at plan there |
| CoreDNS on AWS | Helm, in the bootstrap module, right after Cilium — not the EKS managed add-on |
| CoreDNS on Azure | AKS's own, which BYO CNI keeps; nothing installed |
| Gateway API CRDs | Standard channel v1.6.1, **not vendored**: the `gateway_api` catalog module takes them from upstream, pinned by commit, through Flux, on AWS, Azure and Scaleway |
| Gateway API implementation on AWS and Azure | Cilium's `cilium` GatewayClass, on by default |
| Gateway API on GCP | GKE's controller and CRDs, stated in `opentofu/gcp` (`gateway_api_enabled`, standard channel) |
| Gateway API on Scaleway | Nothing yet: Kapsule's Cilium cannot serve it — open question 6 |
| The class templates target | `inputs.gateway.className`: `cilium` on aws and azure, `gke-l7-global-external-managed` on gcp, empty on scaleway |
| Client surface | `cilium = { enabled, hubble, gateway_api, values }` and, on AWS, `coredns = { values }`, on the bootstrap module and the AWS root |
| Versions | Cilium chart 1.20.2, CoreDNS chart 1.47.1, pinned in `opentofu/bootstrap/cilium.tf` |

## 1. The chicken-and-egg, and why option 1

EKS is created with `bootstrap_self_managed_addons = false`: no VPC CNI, no
kube-proxy, no CoreDNS. AKS is created with `network_plugin = "none"`. On
both, every node is `NotReady` and every pod without `hostNetwork` stays
`Pending` until a CNI runs — flux-operator and the four Flux controllers
included. The catalog is rendered by Flux Operator and applied by Flux, so a
catalog module cannot deliver the CNI Flux itself needs.

Cilium's agent, operator and Envoy all run `hostNetwork` (measured: the
1.20.2 chart renders `hostNetwork: true` on `DaemonSet/cilium`,
`DaemonSet/cilium-envoy` and `Deployment/cilium-operator`, in both the ENI and
the BYOCNI configuration). Helm can therefore install them on a CNI-less
cluster, and Helm is already the applier in the bootstrap module. The chosen
option is the coordinator's first one. On `aws` and `azure`, and only there,
`opentofu/bootstrap/cilium.tf` applies the following releases, in order:

1. `cilium`, from `oci://quay.io/cilium/charts`, in `kube-system`.
2. `coredns`, from `oci://ghcr.io/coredns/charts`, on `aws` only.
3. `flux-operator` then `depends_on` Cilium and CoreDNS. The rest of the
   module is unchanged.

The Gateway API CRDs are not among them. They arrive after Flux (§4).

The two rejected options stay rejected. A pre-Flux step in the client root
breaks "one root, one module" and buys nothing over (1). A minimal CNI
installed only to let Flux deliver Cilium means two CNIs and a migration on
every new cluster. No thin `cilium` catalog module either: Hubble and the
Gateway API toggle are values of the release above, and a second owner of the
same Helm release would be worse than none.

## 2. What is installed, per cloud

| | AWS (EKS) | Azure (AKS BYO CNI) | GCP (Autopilot) | Scaleway (Kapsule) |
| --- | --- | --- | --- | --- |
| Cilium | ENI IPAM, native routing | cluster-pool IPAM, VXLAN overlay | Dataplane V2, Google's | `cni = "cilium"`, Scaleway's |
| kube-proxy | none; Cilium replaces it | AKS's own, Cilium replaces it too | Google's | Scaleway's |
| CoreDNS | socle, by Helm | AKS's own | Google's | Scaleway's |
| Gateway API CRDs | `gateway_api` module, v1.6.1 | `gateway_api` module, v1.6.1 | GKE's, standard channel | `gateway_api` module, v1.6.1 |
| GatewayClass | `cilium`, default | `cilium`, default | GKE's `gke-l7-*` | none yet |

**AWS values** (rendered by `tofu test`, then `helm template` of the real
chart, which read back the agent configuration):

- `eni.enabled: true` alone yields `ipam: eni`, `routing-mode: native`,
  `enable-endpoint-routes: true` and `enable-ipv4-masquerade: false`. Pods
  carry VPC addresses and leave through the per-AZ NAT Gateway like the
  nodes do, so `egressMasqueradeInterfaces` is not needed and not set.
- ENIs go in the node's own subnet, the operator's default. They inherit
  `eth0`'s security groups, so the node-to-node rules that already carry
  kubelet traffic carry pod traffic. No subnet or security-group filter is
  set: the foundations' private subnets are the only ones nodes use.
- `kubeProxyReplacement: true` with `k8sServiceHost` and `k8sServicePort`
  taken from the foundations' `cluster_endpoint` output
  (`https://<id>.gr7.<region>.eks.amazonaws.com` becomes that host and port
  443). No ClusterIP exists to reach the API server through, since there is
  no kube-proxy.
- No `aws-node` to patch and no `node.cilium.io/agent-not-ready` taint to
  add. Both exist to stop the VPC CNI from claiming pods first, and this
  cluster never had it.
- The operator needs EC2 permissions to create ENIs and assign addresses.
  It runs `hostNetwork`, so it takes them from its node's role: the
  foundations attach `cilium_operator_policy_json` to the bootstrap nodes'
  role (below), and output it for any other node role the operator may land
  on.

**Azure values:**

- `aksbyocni.enabled: true` yields `ipam: cluster-pool`,
  `routing-mode: tunnel` over VXLAN, and masquerade on. This is the overlay
  the foundations' network design assumes: the subnet is sized for nodes
  only. The chart refuses anything but tunnel mode with `aksbyocni`.
- The pool is `ipam.operator.clusterPoolIPv4PodCIDRList = [pod_cidr]`. The
  new foundations variable `pod_cidr` defaults to `10.244.0.0/16`, AKS's own
  pod range, and reaches Cilium through an output. The chart's default pool,
  `10.0.0.0/8`, contains the default VNet, `10.0.0.0/16`. azurerm refuses
  `pod_cidr` on the cluster under `network_plugin = "none"`, so the control
  plane is not told this range; that gap is already recorded in
  `opentofu/azure/cluster.tf`.
- `kubeProxyReplacement: true` with the private FQDN as `k8sServiceHost`,
  port 443. The FQDN is the foundations' `cluster_endpoint` output. Nodes
  resolve it through the private DNS zone AKS manages.
- `nodeinit` stays off, against the brief. The 1.20 chart does not tie it to
  `aksbyocni`, and Cilium's AKS BYOCNI procedure sets `aksbyocni.enabled`
  alone. Node init existed for the Azure IPAM mode, which this is not.
- AKS keeps deploying kube-proxy. azurerm has no `kube_proxy_config`: it was
  added and reverted, and hashicorp/terraform-provider-azurerm#19300 is
  closed as not planned. Cilium's own documentation accepts kube-proxy
  replacement alongside kube-proxy on a new cluster. Both run until azurerm
  can turn kube-proxy off.

**Both clouds:** one operator replica. Hubble Relay and UI are off unless the
client turns them on. `rollOutCiliumPods` is on, so a configuration change
restarts the agents instead of waiting for the next node rotation. Requests
are set and limits are not: agent 100m and 256Mi, Envoy 50m and 128Mi,
operator 50m and 128Mi. A memory limit on the CNI is a guess that kills the
network when it is wrong.

**CoreDNS on AWS** gets `fullnameOverride: coredns`, a Service named
`kube-dns` with label `k8s-app: kube-dns`, and the `.10` address of the
cluster's service range. That address is what every EKS node's kubelet is
given as `clusterDNS`. The range comes from the new foundations output
`service_cidr`, which is EKS's `kubernetes_network_config` read back. It also
gets two replicas spread across nodes, `system-cluster-critical`, a
disruption budget of one, and the managed add-on's own requests and limits.
The CoreDNS configuration is the chart's.

### Compute on EKS: the bootstrap node group

A real EKS apply showed what floci and k3s could not: with no node,
`helm_release.cilium` returns in 4 s (a DaemonSet with nothing to schedule,
and one operator whose rollout tolerates it being absent), then CoreDNS's
pods stay Pending until Helm's 600 s timeout. The foundations therefore
create one node group, the only compute they own. It carries what the socle
installs before anything else — Cilium's operator, CoreDNS, the Flux
operator and controllers — and later Karpenter, which provisions every
other node. It is not the cluster's capacity. A cluster with no node is not a
cluster, so this is not the catalog changing the foundations.

**Ordering.** The nodes boot with no CNI and stay `NotReady`; a managed node
group is `ACTIVE` only once they are Ready. So Cilium cannot wait for the
group, and the group cannot wait for Cilium. The AWS root drops its
`depends_on = [module.foundations]`: Cilium follows the cluster alone and is
installed while the nodes boot, and its agent makes them Ready. CoreDNS, the
Flux operator and everything after them follow the group through
`schedulable_nodes = module.foundations.bootstrap_node_group.node_count`, so
they start once nodes exist and are uninstalled before them on a destroy.
Checked in `tofu graph`: `helm_release.cilium` reaches the cluster and not
the group; `coredns`, `operator` and `socle` reach both.

**The failure mode.** `bootstrap_node_count` below 1 is refused at plan by
the foundations. The bootstrap module checks `schedulable_nodes` too, as a
precondition on the first release that needs a pod (CoreDNS on aws, the Flux
operator elsewhere): zero fails the plan with "The cluster has no
schedulable node", instead of a Helm timeout ten minutes later. Null skips
the check where a root cannot see its compute. The check reads the group's
size, not a live node count: floci mocks the group with no instance behind
it, so a live count would fail the e2e for a reason that is not real.

**Size, measured.** Requests, from the charts at the pinned versions:

| Component | Where | CPU | Memory |
| --- | --- | --- | --- |
| Cilium agent + Envoy | every node | 150m | 384Mi |
| Cilium operator ×1 | once | 50m | 128Mi |
| CoreDNS ×2 | once | 200m | 140Mi |
| flux-operator | once | 100m | 64Mi |
| source, kustomize, helm, notification controllers | once | 350m | 256Mi |
| Karpenter ×2 (later; chart sets none, docs say 1 vCPU and 1 GiB each) | once | 2000m | 2Gi |

On two nodes that is 1000m and 1.3 GiB today, 3000m and 3.3 GiB with
Karpenter. Two nodes, not one: CoreDNS keeps a replica through a node loss,
and Karpenter's chart requires its two replicas on different nodes
(`podAntiAffinity` on hostname) in different zones (`DoNotSchedule`), on
nodes Karpenter does not manage.

The nodes are sized for the case Spot makes routine, one node left, and not
for the smallest instance that clears the total. Every default type has
4 vCPU and 8 to 32 GiB, so one node allocates about 3920m and at least
6.6 GiB (AL2023 reserves 80m and 893 MiB at 58 pods, plus 100 MiB for
eviction). Everything the socle runs, on the surviving node alone, with one
Karpenter replica (its second waits for a second node, by its own
anti-affinity):

| | CPU | Memory | Pods |
| --- | --- | --- | --- |
| Today | 850m | 972Mi | 10 |
| With Karpenter at 1 vCPU and 1 GiB | 1850m | 1996Mi | 11 |
| One node allocates | 3920m | ≥ 6.6 GiB | 58 |

A clear yes: under half the CPU and a third of the memory, with room for
what the factory adds to every cluster later (the EBS CSI controller, the
Pod Identity agent, Hubble Relay). The 2 vCPU types first considered left
80m of CPU in that case; that squeeze is why the defaults are 4 vCPU. Three
nodes would hold nothing two cannot.

**Surface.** Three variables. `bootstrap_node_instance_types`, a list, the
AMI following its architecture (a "g" after the generation: `t4g`, `m7gd`;
`g5` stays x86; a list mixing the two is refused). `bootstrap_node_capacity_type`,
`SPOT` or `ON_DEMAND`. `bootstrap_node_count`, default 2, at least 1: one
number, because nothing scales this group — no autoscaler reads it,
Karpenter never resizes it — so min, max and desired would be three knobs
with one meaning. Not variables: 20 GiB encrypted gp3,
IMDSv2 with one hop (a pod that is not `hostNetwork` cannot borrow the
node's role), the private subnets, one node rolled at a time, and the
control plane's Kubernetes version.

**Untainted.** Until Karpenter exists this group is the only compute, and
every catalog module — `hello` today — must schedule on it. A
`CriticalAddonsOnly` taint would leave them Pending and the socle would not
converge. Whether it gets tainted once Karpenter provisions the workload
nodes is decided with Karpenter, not before.

**Spot, over six families.** One instance type on Spot is one capacity
pool per zone, and a reclaim can take both nodes together. The fix is the
list: `t4g.xlarge`, `m7g.xlarge`, `m6g.xlarge`, `c7g.xlarge`, `c6g.xlarge`,
`r6g.xlarge`. Six families across two Graviton generations and four shapes
(burstable, general purpose, compute, memory), not six sizes of one; each
type in each zone is its own pool, so twelve to eighteen pools for two
nodes. Bigger classes are what make the list this wide: the same families'
small sizes are fewer, and Paris offers no 8th-generation Graviton yet. EKS
creates the group with `price-capacity-optimized` on Kubernetes 1.28 and
later, and with Capacity Rebalancing: on a rebalance recommendation it
launches the replacement first, and cordons and drains the old node once
the new one is Ready. The Spot Advisor puts these types at 5–10 %
(`m7g.xlarge`, `r6g.xlarge`), 15–20 % (`t4g.xlarge`) and above 20 %
(`m6g`, `c6g`, `c7g`) interruptions a month in eu-west-3.

A reclaim, then: the replacement boots, Cilium's agent makes it Ready, the
old node drains. Cilium follows the node. CoreDNS, the Flux operator and
controllers, the Cilium operator and later Karpenter reschedule, onto the
survivor if the drain comes first, which the table above says it holds
with room. The socle converges again on its own: nothing in the OpenTofu
state changes, the group's size is the same, and Flux resumes where it
stopped. The pods do not move back when the new node joins; the next drain
moves them.

**Disruption budgets.** CoreDNS already has one (`maxUnavailable: 1`, in the
bootstrap module), and it is what makes a drain safe: its second replica is
not evicted until the first runs elsewhere. Its spread stays preferred,
not required: required, a one-node cluster could never run its second
replica, and Helm's wait would fail. The residue is a hard interruption,
with no rebalance recommendation first, of a node carrying both CoreDNS
replicas after an earlier reclaim: DNS stops until they reschedule, about a
minute. Nothing else warrants a budget. The Flux controllers and the Cilium
operator are one replica each; a budget there blocks every drain without
adding availability, and their outage delays reconciliation or IP
allocation, nothing more. Karpenter's chart ships its own budget and its
own zone spread; the catalog keeps them.

AWS recommends on-demand for cluster tooling that is not fault tolerant.
This group is fault tolerant by the arithmetic above; a client who wants no
reclaim at all sets `bootstrap_node_capacity_type = "ON_DEMAND"`, and EKS
then takes the list's first type, `t4g.xlarge`, the cheapest of the six on
demand.

**Cost, eu-west-3, September 2026**, per month, 730 hours, plus about $3.70
for two 20 GiB gp3 volumes in every case:

| Two nodes | Per node | Pair, with volumes |
| --- | --- | --- |
| **Default: Spot, six 4 vCPU families** | $39.42 (`t4g.xlarge`), $40.37 (`m6g`), $41.68 (`m7g`), $42.63 (`c6g`), $59.57 (`r6g`); `c7g` unpriced | **about $84**, up to $123 if EKS draws both from `r6g` |
| Same machines on demand (`t4g.xlarge`, the first) | $109.79 | $223.28 |
| `m7g.xlarge` on demand, fixed performance | $138.99 | $281.68 |
| Reference: two `t4g.medium` on demand | $27.45 | $58.60 |

In Paris today a 4 vCPU Spot node does not cost less than a 2 vCPU
on-demand one: the default is about $25 a month above the `t4g.medium`
pair it replaces, and buys a survivor that holds the socle with half its
CPU free, over six families instead of one pool. Flipping it to on-demand
for production costs about $139 more a month. The cheapest price
`price-capacity-optimized` finds is the likely one; the $123 ceiling is the
rare month both nodes come from the memory family. Beside the $73 control
plane fee.

**Not chosen.** EKS Auto Mode brings its own networking and refuses any
alternate CNI, Cilium by name (docs.aws.amazon.com, "VPC networking and load
balancing in EKS Auto Mode"): it cannot be the answer on a Cilium socle,
already settled in `docs/aws/eks-cluster-mode.md`. Karpenter alone cannot
bootstrap: it is a pod and needs a node first.

**For later, not built.** Karpenter is an in-cluster component, so it is a
catalog module, and its cloud access is its own: declared as Crossplane
resources in its own ResourceSet, not an IAM block in the foundations. The
line sits here: the bootstrap node group is the one piece of compute the
foundations own, Karpenter owns every other node. The operator's ENI policy
follows it: kept on the bootstrap nodes, or attached to Karpenter's node
role by the Karpenter module.

## 3. CoreDNS: why not the EKS managed add-on

`docs/aws/eks-managed-scope.md` delegated CoreDNS to EKS. The foundations
module leaves every add-on out because a Deployment has no node to run on
there. Moving the add-on to the bootstrap module does not help. It would run
before the CNI exists, or it would need the aws provider, which the bootstrap
module refuses by design.

The add-on cannot be created before Cilium either. The aws provider's
`waitAddonCreated` treats `DEGRADED` as pending and `ACTIVE` as the only
target, with a 20-minute default timeout. A CoreDNS add-on on a cluster with
no CNI sits `DEGRADED` until that timeout. Helm with `wait` is the same
dependency in the right order. CoreDNS therefore moved to the bootstrap
module; the table row in `eks-managed-scope.md` is revised and points here.

The cost is that the socle, not AWS, now tracks which CoreDNS runs on which
Kubernetes minor. The chart is pinned to 1.47.1, which ships CoreDNS 1.14.6,
and moves with socle releases like the other pins.

**Azure:** AKS deploys CoreDNS as a system component whatever the network
plugin. Microsoft's BYO CNI page documents `NotReady` nodes until a CNI is
installed. Azure's and Cilium's BYO CNI guides both install Cilium only, with
no DNS step. *Not measured on a real AKS cluster: there is no Azure root yet.*

## 4. Gateway API on every cloud

The goal is Gateway API installed by default for every client, and no
Ingress anywhere. The socle ships no Ingress object and no Ingress
controller. The gateway-api PR (#35) was closed and its scope moved here.

- **The CRDs are not in the repository.** They come from upstream,
  `kubernetes-sigs/gateway-api`, through Flux. The `gateway_api` catalog
  module (`oci/catalog/gateway-api/`) renders a `GitRepository` pinned to
  commit `8bb74df`, the v1.6.1 tag and the version Cilium 1.20 documents. A
  commit is content-addressed, so nothing can change under the socle. The
  clone is restricted to the `release-1.6` branch, and only
  `config/crd/standard` is checked out. A `Kustomization` then applies that
  directory. Measured: it yields exactly the same 12 objects as the release
  asset, `standard-install.yaml`: 10 CRDs and the safe-upgrades
  `ValidatingAdmissionPolicy` with its binding.
- **Offered on aws, azure and scaleway** (`catalog_clouds`), on by default.
  It is refused at plan on gcp, where GKE owns the CRDs. Disabling it
  deletes the Flux objects and orphans the CRDs (`deletionPolicy: Orphan`),
  so no client loses a Gateway to a toggle.
- **Ordering, and the one restart.** Cilium runs before Flux with
  `gatewayAPI.enabled` and no CRDs. Measured on Cilium 1.20.2 in a CNI-less
  k3s:
  - the agent and the operator are Ready, so Helm's `wait` passes, and the
    node goes Ready;
  - the operator logs "Required GatewayAPI resources are not found" and
    switches its Gateway controller off;
  - it never looks again: applying the CRDs later makes nothing happen (the
    operator's `discoverCRDsWithRetry` retries transient errors only).

  So on the Cilium clouds a second `Kustomization`, `gateway-api-cilium`,
  runs from the socle artifact and depends on the CRDs being established.
  It creates the `cilium` GatewayClass and runs a Job that restarts the
  operator once, with `rollout restart`, under a Role limited to `get` and
  `patch` on that one Deployment. Measured: 17 s from applying it to the
  class being `Accepted`, with the node Ready throughout. Restarting the
  operator does not touch the datapath.
- **The class is the catalog's, not the chart's.** The bootstrap module sets
  `gatewayAPI.gatewayClass.create: "false"`. The chart's default, `auto`,
  renders the class only when the CRD exists at render time: never on the
  first apply, and always on the next one. That would give one object two
  owners.
- **gcp: GKE's own.** GKE installs and upgrades the standard-channel CRDs and
  runs the managed controller, with classes `gke-l7-global-external-managed`,
  `gke-l7-regional-external-managed` and `gke-l7-rilb`. Autopilot does this
  by default. The foundations now state it rather than inherit it:
  `gateway_api_enabled`, default true, sets `gateway_api_config` to
  `CHANNEL_STANDARD`, and `tofu test` covers both states. This is Hugo's
  commit from the closed PR, cherry-picked. The socle installs nothing for
  Gateway API on GKE.
- **scaleway: the CRDs, no controller yet.** Kapsule's Cilium is operated
  by Scaleway and cannot enable Gateway API. The module installs the CRDs
  there, so the API exists, but no class serves it. The closed PR's answer
  for the controller was Envoy Gateway; it is not built here until
  Scaleway's scope is confirmed (question 6).
- **One class name for the templates.** A shared alias is not possible,
  because GKE serves only its own GatewayClasses. The bootstrap module
  therefore tells every template which class to target:

  ```yaml
  gateway:
    className: cilium   # gke-l7-global-external-managed on gcp; "" where nothing serves Gateway API
  cilium:
    installed: true     # the socle's Cilium runs here, and so do the Gateway API CRDs
    gatewayApi: true    # Cilium serves the `cilium` class
    hubble: false       # Hubble Relay and UI exist
  ```

  A template that exposes something, such as an ArgoCD `HTTPRoute` or
  external-dns's Gateway source, reads `inputs.gateway.className` and
  renders no `Gateway` when it is empty. On gcp the value is the global
  external managed class, the internet-facing default. It assumes the
  foundations kept `gateway_api_enabled`, because the bootstrap module
  cannot see that variable. A regional or internal class is a template's
  choice, not a second input.
- **Why this mechanism** — the four options, measured:

  | Option | Before Flux on aws, azure | Pinned | floci e2e | Cost |
  | --- | --- | --- | --- | --- |
  | `http` data source feeding a local chart | yes | sha256 postcondition | untouched, Cilium off | **6.4 MB of state** (measured): the data source keeps the document three times, the release twice. GitHub must answer at every plan. A second provider |
  | Republish into `ghcr.io` at publish time | yes | at publish | untouched | a package and a CI step. Clients need registry credentials in the helm provider while the package is private |
  | **Upstream `GitRepository` + one restart** (chosen) | not needed | commit SHA | **proven**: the CRDs are asserted established | about 150 lines of templates; clusters reach `github.com`; one operator restart per cluster |
  | Vendored file (before) | yes | digest check | untouched | 20116 lines in the repository |

  The Helm release that would carry the CRDs weighs 456 KB, under the
  1 MiB limit, so size was not the deciding factor.
- **This revises one recorded decision.** `docs/flux-catalog.md` §3 says
  "Source kind: OCI only". That rule is about where the socle's own
  composition comes from: one signed artifact, never a client repository.
  It still holds. The `GitRepository` here pulls a third-party, read-only
  dependency, pinned by commit, and carries no composition. The coordinator
  should amend that row rather than let this read as a contradiction.
- Not implemented here: any `Gateway`, `HTTPRoute`, or exposure of Hubble UI.

## 5. What the client may set

On the bootstrap module and on the AWS root, `cilium = { … }` and
`coredns = { … }`, where every key is optional:

| Variable | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `cilium` | `enabled` | `true` | Install Cilium, and CoreDNS on aws, before Flux. `false` is for a cluster that brings its own CNI and DNS; the e2e k3s is the only such cluster |
| `cilium` | `hubble` | `false` | Adds Hubble Relay and UI. Hubble in the agent is always on |
| `cilium` | `gateway_api` | `true` | Cilium's Gateway controller on. The `gateway_api` catalog module creates the `cilium` class once the CRDs exist |
| `cilium` | `values` | `{}` | Any Cilium chart value, the client's winning (below) |
| `coredns` | `values` | `{}` | Any CoreDNS chart value, the client's winning. aws only, where the socle installs CoreDNS |

It is validated like `kube`: a typo or a wrong type is refused at plan, and
any key at all is refused on `gcp` and `scaleway`. The cluster's own facts
(`cluster_network`: API endpoint, service range, pod range) come from the
foundations' outputs in the root and never from the tfvars.

**Not named attributes:** chart versions, IPAM and routing mode, kube-proxy
replacement, the operator replica count, resources, the GatewayClass name,
WireGuard encryption, cluster mesh, the BGP control plane, egress gateway,
and Cilium's L2 announcements. Each one is either dictated by the
foundations' network design or has no socle use case yet. All of them except
the chart versions are still reachable through `values`. Promoting one to a
named attribute is an entry in `local.cilium_schema`, a value in `cilium.tf`,
and a test.

### The client's own chart values

This is the same promise the catalog makes, in `docs/flux-catalog.md` §6. A
client passes any chart value to every release the socle installs, without
waiting for a socle release, and secrets never enter the OpenTofu state. The
mechanism differs because these are `helm_release`s, not catalog modules:

| | Catalog module | Cilium, CoreDNS (this module) |
| --- | --- | --- |
| Free-form values | `kube.<m>.values`, rendered into the `<m>-client-values` ConfigMap | `cilium.values`, `coredns.values` |
| Merge | `valuesFrom` before the HelmRelease's own `values:`; helm-controller deep-merges, the client wins | the release's `values` list is the socle's block, then `yamlencode(values)`; the helm provider deep-merges in order, the client wins |
| Secrets | `values_secret`, a Secret with a `values.yaml` key, merged by helm-controller | a Secret the client creates in `kube-system`, named through the chart's own reference fields |
| Refused at plan | the chart's secret-bearing paths | the same |

**No `values_secret` here.** A `helm_release` cannot merge a Secret that
already exists in the cluster. OpenTofu would have to read it, which puts it
in the state, and it would need the `kubernetes` provider, which this chain
refuses. Both charts already take a Secret by name, so the client writes the
name, which is not secret, in `values`.

**Refused in `cilium.values`**, measured against the 1.20.2 chart: every path
whose template renders inline private key material.

| Refused path | Name a Secret instead |
| --- | --- |
| `hubble.tls.server.key` | `hubble.tls.server.existingSecret` |
| `hubble.relay.tls.client.key`, `hubble.relay.tls.server.key` | `hubble.relay.tls.{client,server}.existingSecret` |
| `hubble.ui.tls.client.key` | `hubble.ui.tls.client.existingSecret` |
| `hubble.metrics.tls.server.key` | `hubble.metrics.tls.server.existingSecret` |
| `tls.ca.key` | a `cilium-ca` Secret created before the apply, or `*.tls.auto.method: certmanager` |
| `clustermesh.config.clusters[*].tls.key` | `clustermesh.config.enabled: false` and the client's own `cilium-clustermesh` Secret |

Certificates alone (`cert`) are accepted: they are public. IPsec already
takes a name, `encryption.ipsec.secretName`, and nothing about it is
refused.

**Nothing is refused in `coredns.values`.** The chart has no value that
renders secret material inline. A Secret reaches CoreDNS through
`extraSecrets`, which mounts it by name, or through `env[].valueFrom`.

**`values` always wins.** A client who sets `hubble = true` and
`hubble.relay.enabled: false` in `values` gets no Relay, because `values` is
merged last. The same goes for the socle's own positions, such as
`eni.enabled` or `k8sServiceHost`: overriding them is possible and is the
client's responsibility. `inputs.cilium` reflects the named attributes only.

The `gateway_api` module installs no chart and takes no values.

## 6. What was measured, and what was not

Measured on 2026-09-23 with OpenTofu 1.12.6, helm 4.1.0 and flux-operator
0.60.0:

- `tofu test` in `opentofu/bootstrap` passes all 52 runs. They cover the
  releases per cloud (aws gets Cilium and CoreDNS, azure gets BYOCNI, gcp,
  scaleway and `enabled = false` get nothing), the toggles, the client
  values layer and its refusals, the class name per cloud, and `gateway_api`
  on by default and refused on gcp.
- `tofu test` passes in `opentofu/aws`, where the policy document case is
  new, and in `opentofu/azure`, where the `pod_cidr` default and validation
  cases are new.
- The Helm values the module renders were extracted from the test plans and
  fed to `helm template` of the real charts: Cilium 1.20.2 from
  `oci://quay.io/cilium/charts` with digest
  `sha256:a7c12d330dd9…`, and CoreDNS 1.47.1. The agent configuration keys
  quoted in §2 are read from that render. kubeconform passes the Cilium and
  CoreDNS renders strictly.
- The whole static suite of `pr-static.yaml` passes locally: yamllint,
  fmt, validate, tflint, terraform-docs, both kubeconform passes, the
  kustomize builds, the two check scripts, and Trivy at HIGH and CRITICAL.

- The late-CRD sequence was run for real on Cilium 1.20.2 in a k3s with no
  CNI and no kube-proxy, as EKS starts. First Cilium with Gateway API on and
  no CRDs, then the CRDs from the pinned upstream directory, then the
  module's `cilium/` manifests. The class was `Accepted` 17 s later (§4).

**e2e.** floci's EKS is a k3s with flannel, kube-proxy and CoreDNS. The
production default installs Cilium, which would fight flannel. Both e2e roots
therefore set `cilium = { enabled = false }`, with a comment saying why: the
real root through `tests/floci.tfvars`, and the fixture root in
`tests/floci/main.tf`. The e2e jobs still prove that the rest of the
bootstrap path converges with the new inputs and the new ordering. They also
assert the Gateway API standard CRDs established from upstream through Flux.
No attempt
was made to run Cilium on k3s. The configuration that would converge there,
chaining over flannel with no ENI and no kube-proxy replacement, shares
nothing with production except the chart, so it would prove the chart and
not this design.

**Not verified, and why:**

- **Cilium converging on a real EKS or AKS.** Neither exists in CI. The first
  real apply is where ENI IPAM, the API endpoint and CoreDNS's address are
  proven.
- **The bootstrap node group on a real EKS.** Its sizing is the sum of
  chart requests above, not an observed cluster, and the Cilium-beside-the-
  group ordering is proven in `tofu graph`, not yet in a real apply. floci
  mocks the group. The first real apply proves the nodes going Ready under
  Cilium and the group reaching `ACTIVE`.
- **The operator's AWS identity.** It runs `hostNetwork`, so it uses its
  node's role through instance metadata, one hop. The bootstrap nodes' role
  carries `cilium_operator_policy_json`. Pod Identity would need its agent,
  an add-on that also waits for compute.

## 7. Open questions for the coordinator

1. **CoreDNS leaves the EKS managed add-on** (§3), which revises the
   foundations research. Confirm, or name the step that installs compute
   before the add-on could be created.
2. **The node role on EKS**: settled. The foundations create the bootstrap
   nodes' role and it carries the Cilium operator's policy (§2). Karpenter's
   node role is the Karpenter module's.
3. **Gateway API ownership**: the CRDs belong to the `gateway_api` module on
   aws, azure and scaleway, and to GKE on gcp. Templates target
   `inputs.gateway.className`.
4. **"Source kind: OCI only"** in `docs/flux-catalog.md` §3 needs one line:
   OCI for the socle's composition, plus pinned upstream `GitRepository`s
   for third-party CRDs (§4).
5. **Azure kube-proxy** keeps running beside Cilium's replacement until
   azurerm can disable it, or the azapi provider is accepted for this one
   property.
6. **Scaleway and Gateway API.** "Every client" includes Kapsule only if the
   socle installs the standard CRDs plus a neutral controller there. The
   CRDs are now installed there. The closed PR measured Envoy Gateway as the
   controller: its own CRDs would come from upstream the same way, never
   vendored. The controller chart `oci://docker.io/envoyproxy/gateway-helm` v1.9.1 then runs with
   `crds.enabled=false`. That is a catalog module, keyed on
   `inputs.cloud == "scaleway"`, setting `inputs.gateway.className` to
   `envoy-gateway`. Confirm the scope before it is built.
