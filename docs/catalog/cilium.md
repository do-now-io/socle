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
| Gateway API CRDs | socle, v1.6.1 | socle, v1.6.1 | GKE's, standard channel | none yet |
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

## 4. Gateway API on every cloud

The goal is Gateway API installed by default for every client, and no
Ingress anywhere. The socle ships no Ingress object and no Ingress
controller. The gateway-api PR (#35) was closed and its scope moved here.

- **aws, azure: the CRDs are installed here, by the bootstrap module.** They
  come from the standard channel at the exact version Cilium 1.20 documents,
  v1.6.1. They are the upstream `standard-install.yaml`, vendored verbatim;
  `.github/scripts/check-gateway-api-crds.sh` fails when the file is not
  that release byte for byte, or when the chart and `cilium.tf` disagree.
  The CRDs stay in place when `gateway_api` is false, because the API is the
  same on every cloud and only the implementation differs. Cilium serves the
  `cilium` GatewayClass.
- **Ordering constraint.** Cilium's operator looks for the CRDs once, at
  start-up, and disables its Gateway API controller if they are absent
  (Cilium docs: "Required GatewayAPI resources are not found"). The CRD
  release therefore precedes Cilium. Installing the CRDs later from the
  catalog would leave Cilium's controller off until the operator restarts.
- **gcp: GKE's own.** GKE installs and upgrades the standard-channel CRDs and
  runs the managed controller, with classes `gke-l7-global-external-managed`,
  `gke-l7-regional-external-managed` and `gke-l7-rilb`. Autopilot does this
  by default. The foundations now state it rather than inherit it:
  `gateway_api_enabled`, default true, sets `gateway_api_config` to
  `CHANNEL_STANDARD`, and `tofu test` covers both states. This is Hugo's
  commit from the closed PR, cherry-picked. The socle installs nothing for
  Gateway API on GKE.
- **scaleway: nothing yet.** Kapsule's Cilium is operated by Scaleway and
  cannot enable Gateway API, so no class exists there. The closed PR's
  answer was the standard CRDs plus Envoy Gateway as a neutral controller.
  It is not built here until Scaleway's scope is confirmed (question 6).
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
- Not implemented here: any `Gateway`, `HTTPRoute`, or exposure of Hubble UI.

## 5. What the client may set

On the bootstrap module and on the AWS root, `cilium = { … }` and
`coredns = { … }`, where every key is optional:

| Variable | Attribute | Default | Meaning |
| --- | --- | --- | --- |
| `cilium` | `enabled` | `true` | Install Cilium, and CoreDNS on aws, before Flux. `false` is for a cluster that brings its own CNI and DNS; the e2e k3s is the only such cluster |
| `cilium` | `hubble` | `false` | Adds Hubble Relay and UI. Hubble in the agent is always on |
| `cilium` | `gateway_api` | `true` | Cilium serves the `cilium` GatewayClass. The CRDs stay either way |
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

The Gateway API CRDs take no values. They are the upstream file, verbatim.

## 6. What was measured, and what was not

Measured on 2026-09-23 with OpenTofu 1.12.6, helm 4.1.0 and flux-operator
0.60.0:

- `tofu test` in `opentofu/bootstrap` passes all 47 runs; the client-values
  layer added two default runs and seven validation runs. Five of them are
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
   aws and azure, and to GKE on gcp. Templates target `inputs.gateway.className`.
4. **Removing the CRDs removes every Gateway.** Setting `enabled = false` on
   a live cluster uninstalls the `gateway-api-crds` release. The file is
   vendored verbatim, so it cannot carry `helm.sh/resource-policy: keep`.
   Accepted, because `enabled = false` is for test doubles only. The
   alternative is a `lifecycle` guard.
5. **Azure kube-proxy** keeps running beside Cilium's replacement until
   azurerm can disable it, or the azapi provider is accepted for this one
   property.
6. **Scaleway and Gateway API.** "Every client" includes Kapsule only if the
   socle installs the standard CRDs plus a neutral controller there. The
   closed PR measured Envoy Gateway: its CRDs chart exceeds Helm's 1 MiB
   release Secret, so the release asset must be vendored. The controller
   chart `oci://docker.io/envoyproxy/gateway-helm` v1.9.1 then runs with
   `crds.enabled=false`. That is a catalog module, keyed on
   `inputs.cloud == "scaleway"`, setting `inputs.gateway.className` to
   `envoy-gateway`. Confirm the scope before it is built.
