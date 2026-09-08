# GKE base networking and security

The dataplane, how applications are exposed, how the control plane is reached,
and the network the module builds. Autopilot throughout — see
[cluster mode](README.md), and [managed scope](managed-scope.md) for upgrades,
add-ons and identity.

| Question | Position | In the module |
| --- | --- | --- |
| CNI | Dataplane V2, enforced by Autopilot | no variable |
| Self-managed Cilium | Refused — impossible on Autopilot | absent |
| Network policy | Plain Kubernetes NetworkPolicy, always on | catalog's, not the module's |
| FQDN and L7 policies | Refused as a default — GKE-specific, `v1alpha1` | absent |
| Dataplane V2 observability tools | Catalog option — Hubble relay costs Pod requests | `dpv2_observability_enabled`, default `false` |
| Application exposure | Gateway API, GKE Gateway controller | catalog's; the module builds the proxy subnet |
| In-cluster gateway (Envoy, Cilium) | Refused — 5× the cost, ours to operate | absent |
| Node addressing | Private nodes | `enable_private_nodes`, default `true` |
| Control plane access | DNS-based endpoint, IP endpoints off | `control_plane` variables |
| Authorized networks | Refused — the DNS endpoint replaces them | absent |
| Egress | Cloud NAT + Private Google Access | module creates both |
| Services range | GKE-managed `34.118.224.0/20` | no variable |
| Pod range | One secondary range, `/17` by default | `pod_range_cidr` |
| Auto IPAM | Refused — Preview | absent |
| VPC Service Controls | Catalog option — organisation-level | absent |

## 1. Dataplane V2 or Cilium

The question is closed twice over on Autopilot: Dataplane V2 is enabled by
default and cannot be changed after creation, and a self-managed Cilium needs
privileged DaemonSets and custom eBPF programs — both blocked, the second
explicitly by Dataplane V2's own limitations. There is no decision to make,
only an inventory to keep.

**What Dataplane V2 gives us.** An eBPF dataplane built on Cilium (`anetd` per
node), **Kubernetes NetworkPolicy always on** with no add-on to install,
built-in network policy logging, and Hubble — relay and CLI, with the UI
deployable separately. On Autopilot the flow metrics are on by default and the
observability tools are off.

**What we lose against a self-managed Cilium on the other clouds:**

| | On GKE Autopilot |
| --- | --- |
| `CiliumNetworkPolicy` (L7 rules) | CRD exists, but restricts the cluster to zonal limits of 1,000 nodes |
| FQDN policies | GKE's own `FQDNNetworkPolicy` CRD, `networking.gke.io/v1alpha1`, 50 resolved IPs max, no ClusterIP or headless Services |
| Inter-node transparent encryption | **Not supported on Autopilot** |
| Cluster mesh, egress gateway, BGP, Tetragon, custom eBPF | Absent |
| Endpoint scale | 260,000 entries across all Services |
| Other | Fragmented ICMP dropped; manually created internal passthrough NLBs unsupported |

**The consequence is for the catalog, not the module.** The only policy surface
that exists identically on four clouds is **plain Kubernetes NetworkPolicy**, so
that is what catalog modules must express. FQDN and L7 rules are per-cloud
extras a client asks for explicitly, and on GKE the FQDN one is still
`v1alpha1` — refused as a default on that ground alone.

Hubble's relay and UI stay a catalog option rather than a default: on Autopilot
they are Pod requests we pay for, on a cluster where the policy logs already
answer "was this flow dropped".

## 2. Gateway API as the exposure reference

**Confirmed, with one caveat that matters more than the maturity claim.**

The GKE Gateway controller is managed by Google, **offered at no additional
charge as part of GKE pricing**, and provisions Google's load balancers through
nine GatewayClasses — `gke-l7-regional-external-managed` and
`gke-l7-global-external-managed` for external traffic, `gke-l7-rilb` for
internal, plus multi-cluster variants. It tracks the specification closely:
Gateway API v1.3 CRDs from GKE 1.33.2-gke.1335000, v1.5 from 1.35.2-gke.1842000,
passing core conformance.

"Most mature on the market" is not a measurable claim and the document does not
make it. What is measurable: there is no data plane of ours to run, scale or
patch, and the routing objects are the upstream ones.

**The caveat: routing is portable, policy is not.** Anything beyond routing goes
through Google-specific CRDs in the `networking.gke.io` group —
`GCPGatewayPolicy` (SSL policies, global access), `GCPBackendPolicy` (Cloud
Armor, timeouts, session affinity, access logging), `HealthCheckPolicy`,
`GCPTrafficDistributionPolicy`. So a catalog module can ship one HTTPRoute for
four clouds, but health checks, WAF and session affinity are a per-cloud layer.
That is a real cost, and it is smaller than the alternative.

**The alternative we reject** is an in-cluster gateway — Envoy Gateway or
Cilium's — for byte-identical behaviour everywhere. Two Envoy replicas at
1 vCPU / 2 GiB are **$79/month per cluster** in Autopilot Pod requests, and a
Google L4 forwarding rule is still needed in front, so **~$98/month against
$18** for a managed regional Application Load Balancer — five times the price,
plus a data plane on our watch. Ingress is refused for new exposure: Gateway API
is where the features land.

## 3. Private nodes and control plane access

Yes to both, and one default has to be flipped: **Autopilot clusters are public
by default**.

**Nodes: private.** No external IP, egress through Cloud NAT, Private Google
Access on. Private Google Access is enabled automatically at creation unless
Shared VPC is used, and must not be disabled unless NAT covers internet access.

**Control plane: the DNS-based endpoint.** Google now recommends it as the
primary access path — a stable per-cluster FQDN, reachable from anywhere Google
Cloud APIs are reachable, authorised by IAM, with Private Service Connect
covering clients that have no internet route. It replaces the private-cluster
and VPC-peering model, the `/28` master CIDR, and the whole authorized-networks
maintenance problem: Google's own documentation notes that IP allowlists must be
updated when subnets grow and break for clients with dynamic addresses. Since
the pipeline that runs `tofu apply` and Flux's reconciliation both need control
plane access, an IP allowlist would be a permanent operational tax.

IP endpoints are disabled. **Authorized networks are absent from the module** —
they only apply to IP endpoints, and keeping both would be keeping the problem.

**State the trade-off plainly:** with the DNS endpoint open to external traffic,
the control plane is reachable from the internet and the only thing standing in
front of it is IAM. For clients who need a network boundary as well, the answer
is **VPC Service Controls**, which is an organisation-level perimeter and
therefore a catalog concern, not a module variable.

## 4. The reference network

One custom-mode VPC — never auto mode, so ranges can be chosen not to overlap —
and one subnet per cluster, in the cluster's region.

| Range | Size | Why |
| --- | --- | --- |
| Node primary range | `/24` | Autopilot node counts are small; the range is easy to widen |
| Pod secondary range | `/17` | Autopilot fixes 32 Pods per node, so `/26` per node: 512 nodes, 16,384 Pods |
| Services | none | GKE-managed `34.118.224.0/20` since Autopilot 1.27 — no secondary range to plan |
| Proxy-only subnet | `/23` | Required, `REGIONAL_MANAGED_PROXY`, one per region before any regional Gateway exists; `/26` is the hard minimum |
| Control plane `/28` | none | The DNS-based endpoint removes it |

Regional clusters. Cloud NAT per region for egress. **Auto IPAM is refused**:
it would remove the pod-range sizing question entirely, but it is Preview, and
a module default has to be GA.

Two things this section deliberately does not settle, because they belong to the
project and organisation layout rather than to a cluster module: Shared VPC —
which Google calls suitable for most organisations with a central team, and
which changes who owns the subnet — and one project per environment, which is
what actually isolates the Workload Identity principals flagged in
[managed scope](managed-scope.md).

## Cost impact on the reference estate

Same estate as the [cluster mode research](README.md): three Autopilot
clusters, us-central1 list price, 730-hour month, baseline **$1,488/month**.

| | Per month | vs baseline |
| --- | --- | --- |
| Three regional Application Load Balancers, one forwarding rule each | +$55 | +4% |
| Load balancer data processing, 200 GiB per cluster | +$5 | — |
| Three Cloud NAT gateways, ~4 nodes and one IP each | +$23 | +2% |
| NAT data processing, 100 GiB per cluster | +$14 | +1% |
| **Total** | **+$96** | **+6.5%** |
| *In-cluster Envoy instead of managed load balancers* | +$294 | +20% |

Rates, us-central1 list price read 8 September 2026: forwarding rule
$0.025/hour each for the first five, $0.01 after; load balancer data processed
$0.008/GiB in and out; Cloud NAT $0.0014 per VM-hour up to 32 VMs then $0.044
per gateway-hour, $0.045/GiB processed, $0.005/hour per external IP; Autopilot
Pod requests $0.0445/vCPU-hour and $0.0049225/GiB-hour. The Gateway controller
itself, Dataplane V2 and the DNS endpoint carry no charge. Re-price before
quoting.

## Module specification

| Variable | Type | Default | Constraint |
| --- | --- | --- | --- |
| `network_name` | `string` | **none — required** | existing custom-mode VPC, or created by the module when `create_network` is set |
| `create_network` | `bool` | `false` | the common case is a VPC the client already owns |
| `region` | `string` | **none — required** | regional cluster only |
| `node_range_cidr` | `string` | `"10.0.0.0/24"` | valid RFC 1918 CIDR |
| `pod_range_cidr` | `string` | `"10.4.0.0/17"` | `/17` or larger; must not overlap the node range |
| `proxy_only_range_cidr` | `string` | `"10.8.0.0/23"` | `/26` or larger — the hard limit of the load balancer |
| `enable_private_nodes` | `bool` | `true` | flips the Autopilot default |
| `control_plane_dns_endpoint_enabled` | `bool` | `true` | — |
| `control_plane_ip_endpoints_enabled` | `bool` | `false` | — |
| `control_plane_dns_allow_external_traffic` | `bool` | `true` | documented as IAM-gated; VPC-SC is the network boundary |
| `create_nat` | `bool` | `true` | a private cluster with no NAT cannot pull images |
| `dpv2_observability_enabled` | `bool` | `false` | Hubble relay and UI are Pod requests |

Absent by decision: any CNI or datapath variable, `master_authorized_networks`,
`master_ipv4_cidr_block`, a Services secondary range, `auto_ipam_config`, and
any Gateway or NetworkPolicy resource — exposure and policy are catalog
objects, and the module's job stops at the proxy-only subnet they need.

Outputs this adds: the DNS endpoint, the network and subnet self-links, the Pod
range name, and the proxy-only subnet.

## Known gaps

- **How Dataplane V2 flow metrics are billed is unverified.** Whether they fall
  under free GKE system metrics or chargeable Managed Service for Prometheus
  samples changes nothing in the module — observability tools are off by
  default either way — but it would change a client's bill if enabled, and the
  pricing page does not say.
- **The Cloud NAT figure assumes a node count we do not control.** Autopilot
  provisions nodes; four per cluster is a guess, and NAT is billed per VM-hour
  below 32 VMs. The per-unit rates are the reliable part.
- **Shared VPC is not evaluated.** Google recommends it for centrally managed
  organisations, and it changes who owns the subnet and the Private Google
  Access default. It needs a project-layout decision first.
- **`/17` for Pods is a default, not a study.** It sizes 512 nodes at
  Autopilot's fixed 32 Pods per node; nothing has been measured about what a
  real client estate consumes.
- **Leaving the DNS endpoint open to external traffic is a deliberate risk**,
  accepted because a closed control plane makes the pipeline and Flux depend on
  private connectivity we do not build. VPC Service Controls is the mitigation
  and it is out of the module's reach.

## Sources

Read 8 September 2026. [GKE Dataplane V2][dpv2] · [Dataplane V2
observability][dpv2-obs] · [FQDN network policies][fqdn] · [inter-node
transparent encryption][encryption] · [About Gateway API][gwapi] ·
[configure Gateway resources][gw-policies] · [network isolation][isolation] ·
[customize network isolation][private] · [VPC-native clusters][alias] ·
[best practices for GKE networking][net-bp] · [proxy-only subnets][proxy] ·
[auto IPAM][auto-ipam] · [VPC network pricing][net-pricing] · [Cloud NAT
pricing][nat-pricing] · [GKE pricing][pricing] ·
[`google_container_cluster`][tf-cluster].

[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[dpv2-obs]: https://cloud.google.com/kubernetes-engine/docs/concepts/about-dpv2-observability
[fqdn]: https://cloud.google.com/kubernetes-engine/docs/how-to/fqdn-network-policies
[encryption]: https://cloud.google.com/kubernetes-engine/docs/how-to/enable-inter-node-transparent-encryption
[gwapi]: https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api
[gw-policies]: https://cloud.google.com/kubernetes-engine/docs/how-to/configure-gateway-resources
[isolation]: https://cloud.google.com/kubernetes-engine/docs/concepts/network-isolation
[private]: https://cloud.google.com/kubernetes-engine/docs/how-to/private-clusters
[alias]: https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips
[net-bp]: https://cloud.google.com/kubernetes-engine/docs/best-practices/networking
[proxy]: https://cloud.google.com/load-balancing/docs/proxy-only-subnets
[auto-ipam]: https://cloud.google.com/kubernetes-engine/docs/how-to/enable-auto-ipam
[net-pricing]: https://cloud.google.com/vpc/network-pricing
[nat-pricing]: https://cloud.google.com/nat/pricing
[pricing]: https://cloud.google.com/kubernetes-engine/pricing
[tf-cluster]: https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster
