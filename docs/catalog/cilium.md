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
| Gateway API CRDs | Standard channel v1.6.1, installed by the bootstrap module before Cilium, on AWS and Azure |
| Gateway API implementation on AWS and Azure | Cilium's `cilium` GatewayClass, on by default |
| Client surface | `cilium = { enabled, hubble, gateway_api }` on the bootstrap module and the AWS root |
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

1. `gateway-api-crds`, a local chart over the vendored upstream
   `standard-install.yaml`.
2. `cilium`, from `oci://quay.io/cilium/charts`, in `kube-system`.
3. `coredns`, from `oci://ghcr.io/coredns/charts`, on `aws` only.
4. `flux-operator` then `depends_on` Cilium and CoreDNS. The rest of the
   module is unchanged.

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
| Gateway API CRDs | socle, v1.6.1 | socle, v1.6.1 | gateway-api worktree | gateway-api worktree |
| GatewayClass `cilium` | yes, default | yes, default | no | no |

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
  The foundations now output them as `cilium_operator_policy_json`, a policy
  document and not a resource: nothing billable, and nothing to attach to
  while the foundations create no node role (§6).

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

## 4. Gateway API: what the gateway-api worktree can rely on

- **The CRDs are installed here, on `aws` and `azure`.** They come from the
  standard channel at the exact version Cilium 1.20 documents, v1.6.1. They
  are the upstream `standard-install.yaml`, vendored verbatim;
  `.github/scripts/check-gateway-api-crds.sh` fails when the file is not
  that release byte for byte, or when the chart and `cilium.tf` disagree.
  The CRDs stay in place when `gateway_api` is false, because the API is the
  same on every cloud and only the implementation differs.
- **Ordering constraint.** Cilium's operator looks for the CRDs once, at
  start-up, and disables its Gateway API controller if they are absent
  (Cilium docs: "Required GatewayAPI resources are not found"). The CRD
  release therefore precedes Cilium. Installing the CRDs later from the
  catalog would leave Cilium's controller off until the operator restarts.
- **The contract with the templates** is a new block in the inputs every
  `ResourceSet` sees:

  ```yaml
  cilium:
    installed: true    # the socle's Cilium runs here, and so do the Gateway API CRDs
    gatewayApi: true   # the `cilium` GatewayClass exists; no other implementation is needed
    hubble: false      # Hubble Relay and UI exist
  ```

  All three are false on `gcp` and `scaleway`. On those clouds the
  gateway-api module owns the CRDs and the implementation. On `aws` and
  `azure` it should install neither while `inputs.cilium.installed` is true,
  or two owners will fight over the same CRDs. The block is outside
  `modules` on purpose: it is a bootstrap fact, not something `kube` sets.
- **Assumption, easy to adjust:** the gateway-api worktree names Cilium's
  `GatewayClass` `cilium`, the chart's default. Changing it is one value in
  `cilium.tf`.
- Not implemented here: any `Gateway`, `HTTPRoute`, or exposure of Hubble UI.

## 5. What the client may set

On the bootstrap module and on the AWS root, `cilium = { … }`, where every
key is optional:

| Attribute | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Install Cilium, and CoreDNS on aws, before Flux. `false` is for a cluster that brings its own CNI and DNS; the e2e k3s is the only such cluster |
| `hubble` | `false` | Adds Hubble Relay and UI. Hubble in the agent is always on |
| `gateway_api` | `true` | Cilium serves the `cilium` GatewayClass. The CRDs stay either way |

It is validated like `kube`: a typo or a wrong type is refused at plan, and
any key at all is refused on `gcp` and `scaleway`. The cluster's own facts
(`cluster_network`: API endpoint, service range, pod range) come from the
foundations' outputs in the root and never from the tfvars.

**Deliberately not configurable:** chart versions, IPAM and routing mode,
kube-proxy replacement, the operator replica count, resources, the
GatewayClass name, WireGuard encryption, cluster mesh, the BGP control plane,
egress gateway, and Cilium's L2 announcements. Each one is either dictated by
the foundations' network design or has no socle use case yet. Adding one is
an entry in `local.cilium_schema`, a value in `cilium.tf`, and a test.

## 6. What was measured, and what was not

Measured on 2026-09-23 with OpenTofu 1.12.6, helm 4.1.0 and flux-operator
0.60.0:

- `tofu test` in `opentofu/bootstrap` passes all 38 runs. Five of them are
  new default cases: aws gets three releases in order; azure gets BYOCNI and
  no CoreDNS; gcp gets nothing; `enabled = false` gets nothing; and the
  toggles reach both the chart values and the inputs. The scaleway run also
  asserts that nothing is installed. Eight are new validation cases.
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
  kustomize builds, the three check scripts, and Trivy at HIGH and CRITICAL.

**e2e.** floci's EKS is a k3s with flannel, kube-proxy and CoreDNS. The
production default installs Cilium, which would fight flannel. Both e2e roots
therefore set `cilium = { enabled = false }`, with a comment saying why: the
real root through `tests/floci.tfvars`, and the fixture root in
`tests/floci/main.tf`. The e2e jobs still prove that the rest of the
bootstrap path converges with the new inputs and the new ordering. No attempt
was made to run Cilium on k3s. The configuration that would converge there,
chaining over flannel with no ENI and no kube-proxy replacement, shares
nothing with production except the chart, so it would prove the chart and
not this design.

**Not verified, and why:**

- **Cilium converging on a real EKS or AKS.** Neither exists in CI. The first
  real apply is where ENI IPAM, the API endpoint and CoreDNS's address are
  proven.
- **Compute.** The foundations create no node on AWS, and on AKS only the
  system pool exists. Helm's `wait` on the Cilium operator, CoreDNS and
  flux-operator needs a schedulable node. AKS's system pool provides one.
  On EKS, whatever brings the first nodes (Karpenter is a factory component,
  and it also needs a network) must come before this module. That question
  predates this change and is not answered here.
- **The operator's AWS identity.** It runs `hostNetwork`, so it uses the node
  role through instance metadata. That role must carry
  `cilium_operator_policy_json`. Pod Identity would need its agent, an
  add-on that also waits for compute.

## 7. Open questions for the coordinator

1. **CoreDNS leaves the EKS managed add-on** (§3), which revises the
   foundations research. Confirm, or name the step that installs compute
   before the add-on could be created.
2. **The node role on EKS**: who creates it, and whether it or a Pod Identity
   association carries the Cilium operator's policy.
3. **Gateway API ownership**: the CRDs belong to the bootstrap module on
   aws/azure and to the gateway-api module elsewhere, keyed on
   `inputs.cilium.installed`. The gateway-api worktree must follow this.
4. **Removing the CRDs removes every Gateway.** Setting `enabled = false` on
   a live cluster uninstalls the `gateway-api-crds` release. The file is
   vendored verbatim, so it cannot carry `helm.sh/resource-policy: keep`.
   Accepted, because `enabled = false` is for test doubles only. The
   alternative is a `lifecycle` guard.
5. **Azure kube-proxy** keeps running beside Cilium's replacement until
   azurerm can disable it, or the azapi provider is accepted for this one
   property.
