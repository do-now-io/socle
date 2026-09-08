# GKE base networking and security

Dataplane, exposure, control plane access, reference network — see
[cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| CNI | Dataplane V2, enforced by Autopilot |
| Self-managed Cilium | Refused — impossible on Autopilot |
| Network policy | Plain Kubernetes NetworkPolicy, always on |
| FQDN and L7 policies | Refused as a default — GKE-specific, still alpha |
| Hubble relay and UI | Catalog option — Pod requests we pay for |
| Exposure | Gateway API, Google's controller |
| In-cluster gateway | Refused — 5× the cost, ours to operate |
| Nodes | Private |
| Control plane access | DNS-based endpoint, IP endpoints off |
| Authorized networks | Refused — the DNS endpoint replaces them |
| Egress | Cloud NAT + Private Google Access |
| Services range | GKE-managed, nothing to size |
| Auto IPAM | Refused — still Preview |

## Dataplane V2

Nothing to decide: Autopilot enables it and blocks what a self-managed Cilium
needs (privileged DaemonSets, custom eBPF).

**What we get:** eBPF dataplane, Kubernetes NetworkPolicy always on with
nothing to install, built-in policy logging, Hubble.

**What we lose** against a self-managed Cilium on the other clouds:

- L7 policy rules at scale, cluster mesh, egress gateway, BGP, Tetragon.
- Inter-node transparent encryption — not supported on Autopilot at all.
- FQDN policies only through a GKE-specific alpha CRD.

**Consequence for the catalog:** plain Kubernetes NetworkPolicy is the only
policy surface identical on four clouds, so that is what catalog modules
express.

## Exposure

**Decision: Gateway API with Google's controller, for simplicity.**

- Managed and free: no data plane of ours to run, scale or patch.
- Routing objects are portable; health checks, WAF and session affinity go
  through Google-specific policy resources, so that layer is per-cloud.
- Ingress is refused for new exposure.
- Rejected alternative — in-cluster Envoy for identical behaviour everywhere:
  ~$98/month per cluster against $18 for a managed load balancer.

## Control plane and nodes

**Nodes are private** — this flips Autopilot's default, which is public.
Egress through Cloud NAT, Private Google Access on.

**The control plane is reached through its DNS-based endpoint**, which Google
recommends: a stable FQDN, authorised by IAM.

- IP endpoints off; authorized networks absent rather than defaulted — they
  only apply to those endpoints, and would need rewriting every time a subnet
  or CI runner address changes.
- Accepted risk: the control plane is reachable from the internet with IAM as
  the only gate. Clients needing a network boundary get VPC Service Controls,
  which is organisation-level and therefore not a module variable.

## Reference network

One custom-mode VPC, one subnetwork per cluster in its region, regional
clusters, Cloud NAT per region.

| Range | Size | Why |
| --- | --- | --- |
| Nodes (primary) | `/24` | Autopilot node counts are small |
| Pods (secondary) | `/17` | 32 Pods per node, so `/26` each: 512 nodes |
| Services | none | GKE manages its own range |
| Proxy-only subnet | `/23` | No regional Gateway without it; `/26` is the minimum |
| Control plane | none | The DNS endpoint removes it |

Left to a project-layout decision: Shared VPC, and one project per
environment — the latter is what isolates the principals flagged in
[managed scope](managed-scope.md).

## Cost impact

Reference estate, baseline **$1,488/month**.

| | Per month |
| --- | --- |
| Three regional load balancers | +$55 |
| Three Cloud NAT gateways | +$23 |
| Data processing, load balancer and NAT | +$19 |
| **Total** | **+$96 (+6.5%)** |
| *In-cluster Envoy instead* | +$294 |

The Gateway controller, Dataplane V2 and the DNS endpoint carry no charge.
us-central1 list price, read 8 September 2026.

## Module specification

| Variable | Default | Constraint |
| --- | --- | --- |
| `network_name` / `create_network` | existing VPC / `false` | exactly one of the two |
| `node_range_cidr` | `"10.0.0.0/24"` | valid CIDR |
| `pod_range_cidr` | `"10.4.0.0/17"` | `/17` or larger |
| `proxy_only_range_cidr` | `"10.8.0.0/23"` | `/26` or larger |
| `enable_private_nodes` | `true` | flips the Autopilot default |
| `control_plane_ip_endpoints_enabled` | `false` | — |
| `create_nat` | `true` | private nodes cannot pull images without it |
| `dpv2_observability_enabled` | `false` | Hubble relay costs Pod requests |

Absent by decision: any CNI or datapath variable, authorized networks, a
Services secondary range, Auto IPAM, and any Gateway or NetworkPolicy object —
the module stops at the proxy-only subnet a Gateway needs.

## Sources

Read 8 September 2026. [Dataplane V2][dpv2] · [FQDN network policies][fqdn] ·
[inter-node transparent encryption][encryption] · [Gateway API][gwapi] ·
[network isolation][isolation] · [VPC-native clusters][alias] ·
[networking best practices][net-bp] · [proxy-only subnets][proxy] ·
[auto IPAM][auto-ipam] · [VPC network pricing][net-pricing] ·
[Cloud NAT pricing][nat-pricing].

[dpv2]: https://cloud.google.com/kubernetes-engine/docs/concepts/dataplane-v2
[fqdn]: https://cloud.google.com/kubernetes-engine/docs/how-to/fqdn-network-policies
[encryption]: https://cloud.google.com/kubernetes-engine/docs/how-to/enable-inter-node-transparent-encryption
[gwapi]: https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api
[isolation]: https://cloud.google.com/kubernetes-engine/docs/concepts/network-isolation
[alias]: https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips
[net-bp]: https://cloud.google.com/kubernetes-engine/docs/best-practices/networking
[proxy]: https://cloud.google.com/load-balancing/docs/proxy-only-subnets
[auto-ipam]: https://cloud.google.com/kubernetes-engine/docs/how-to/enable-auto-ipam
[net-pricing]: https://cloud.google.com/vpc/network-pricing
[nat-pricing]: https://cloud.google.com/nat/pricing
