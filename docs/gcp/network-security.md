# GKE base networking and security

Dataplane, exposure, control plane access and the reference network, on an
Autopilot cluster — see [cluster mode](cluster-mode.md).

| Question | Position |
| --- | --- |
| CNI | Dataplane V2, enforced by Autopilot |
| Self-managed Cilium | Refused — impossible on Autopilot |
| Network policy | Plain Kubernetes NetworkPolicy, always on |
| FQDN and L7 policies | Refused as a default — GKE-specific and still alpha |
| Exposure | Gateway API, Google's controller |
| In-cluster gateway (Envoy, Cilium) | Refused — 5× the cost, ours to operate |
| Nodes | Private |
| Control plane access | DNS-based endpoint, IP endpoints off |
| Authorized networks | Refused — the DNS endpoint replaces them |
| Egress | Cloud NAT + Private Google Access |
| Services range | GKE-managed, nothing to size |
| Auto IPAM | Refused — still Preview |

## Dataplane V2

No decision to make: Autopilot enables it and cannot be changed, and a
self-managed Cilium needs privileged DaemonSets and custom eBPF, both blocked.

We get an eBPF dataplane, **Kubernetes NetworkPolicy always on** with nothing
to install, built-in policy logging, and Hubble. We lose, against a
self-managed Cilium on the other clouds: L7 policy rules at scale, cluster
mesh, egress gateway, BGP, Tetragon, and **inter-node transparent encryption,
which is not supported on Autopilot at all**. FQDN policies exist but through a
GKE-specific alpha CRD.

**The consequence is for the catalog:** plain Kubernetes NetworkPolicy is the
only policy surface that exists identically on four clouds, so that is what
catalog modules express. Hubble's relay and UI stay a catalog option — on
Autopilot they are Pod requests we pay for.

## Exposure: Gateway API

**Decision: Gateway API with Google's own controller, for simplicity.** It is
managed, free, and provisions Google's load balancers, so there is no data
plane of ours to run, scale or patch. Ingress is refused for new exposure.

Routing objects are portable across clouds; anything beyond routing — health
checks, WAF, session affinity — goes through Google-specific policy resources,
so that layer is per-cloud.

The alternative, an in-cluster Envoy for byte-identical behaviour everywhere,
costs ~$98/month per cluster against $18 for a managed load balancer, and
would be ours to operate.

## Control plane and nodes

**Nodes are private** — this flips Autopilot's default, which is public.
Egress through Cloud NAT, Private Google Access on.

**The control plane is reached through its DNS-based endpoint**, which Google
now recommends: a stable FQDN, authorised by IAM, reachable wherever Google
Cloud APIs are. IP endpoints are off, and authorized networks are absent
rather than defaulted — they only apply to the IP endpoints we disable, and
they would have to be rewritten every time a subnet or a CI runner address
changes.

The trade-off, stated plainly: the control plane is then reachable from the
internet with IAM as the only gate. Clients who need a network boundary get
VPC Service Controls, which is an organisation-level perimeter and therefore
not a module variable.

## Reference network

One custom-mode VPC, one subnetwork per cluster in the cluster's region.

| Range | Size | Why |
| --- | --- | --- |
| Nodes (primary) | `/24` | Autopilot node counts are small |
| Pods (secondary) | `/17` | 32 Pods per node on Autopilot, so `/26` each: 512 nodes |
| Services | none | GKE manages its own range |
| Proxy-only subnet | `/23` | Required before any regional Gateway exists; `/26` is the minimum |
| Control plane `/28` | none | The DNS endpoint removes it |

Regional clusters, Cloud NAT per region. Auto IPAM would remove the Pod range
question entirely but is still Preview, and a default has to be GA.

Shared VPC and one project per environment are deliberately left to a
project-layout decision — the latter is what actually isolates the Workload
Identity principals flagged in [managed scope](managed-scope.md).

## Cost impact

Reference estate of three clusters, baseline **$1,488/month**.

| | Per month |
| --- | --- |
| Three regional load balancers, one forwarding rule each | +$55 |
| Three Cloud NAT gateways | +$23 |
| Data processing, load balancer and NAT | +$19 |
| **Total** | **+$96 (+6.5%)** |
| *In-cluster Envoy instead* | +$294 |

The Gateway controller, Dataplane V2 and the DNS endpoint carry no charge.
us-central1 list price, read 8 September 2026. Re-price before quoting.

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
exposure and policy are catalog concerns, and the module stops at the
proxy-only subnet a Gateway needs.

## Known gaps

- **How Dataplane V2 flow metrics are billed is not documented.** It changes
  nothing while the observability tools are off by default.
- **The Cloud NAT figure assumes a node count we do not control**, since
  Autopilot provisions nodes and NAT is billed per VM-hour below 32 VMs.
- **Leaving the DNS endpoint open is a deliberate risk**, accepted because a
  closed control plane makes the pipeline and Flux depend on private
  connectivity we do not build.

## Sources

Read 8 September 2026. [Dataplane V2][dpv2] · [FQDN network
policies][fqdn] · [inter-node transparent encryption][encryption] ·
[Gateway API][gwapi] · [network isolation][isolation] · [VPC-native
clusters][alias] · [best practices for GKE networking][net-bp] ·
[proxy-only subnets][proxy] · [auto IPAM][auto-ipam] · [VPC network
pricing][net-pricing] · [Cloud NAT pricing][nat-pricing].

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
