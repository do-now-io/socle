---
title: Cilium before Flux
description: Why the bootstrap installs Cilium, CoreDNS and the EKS add-ons ahead of Flux on the clouds created with no CNI, and in what order.
sidebar:
  order: 5
---

On two of the four clouds the foundations create a cluster with no network
plugin. Flux cannot run on such a cluster, so the catalog, which Flux
renders, cannot deliver the network. The bootstrap module installs it first,
with Helm, in the same apply.

## The chicken-and-egg

EKS is created with `bootstrap_self_managed_addons = false`: no VPC CNI, no
kube-proxy, no CoreDNS. AKS is created with `network_plugin = "none"`. On
both, every node is `NotReady` and every pod without `hostNetwork` stays
`Pending` until a CNI runs, flux-operator and the four Flux controllers
included.

Cilium's agent, operator and Envoy all run `hostNetwork` (the 1.20.2 chart
renders it on `DaemonSet/cilium`, `DaemonSet/cilium-envoy` and
`Deployment/cilium-operator`, in both the ENI and the BYOCNI configuration).
Helm can therefore install them on a cluster with no CNI, and Helm is
already the applier in the bootstrap module. So on aws and azure, and only
there, [`cilium.tf`](../../opentofu/bootstrap/cilium.tf) installs Cilium
before `flux-operator`
([SOCLE-02](../decisions/socle.md#socle-02-cilium-and-coredns-before-flux-from-the-bootstrap)).
Cilium is not a catalog module: Hubble and the Gateway API toggle are values
of that one release, and a second owner of it would be worse than none.

## What is installed, per cloud

| | AWS (EKS) | Azure (AKS, BYO CNI) | GCP (Autopilot) | Scaleway (Kapsule) |
| --- | --- | --- | --- | --- |
| Cilium | the socle's: ENI IPAM, native routing | the socle's: cluster-pool IPAM, VXLAN overlay | Dataplane V2, Google's | `cni = "cilium"`, Scaleway's |
| kube-proxy | none; Cilium replaces it | AKS's own; Cilium replaces it too | Google's | Scaleway's |
| CoreDNS | the socle's, by Helm | AKS's own | Google's | Scaleway's |
| EKS add-ons | Pod Identity Agent, snapshot controller, EBS CSI; EFS CSI on request | — | — | — |
| Gateway API CRDs | the `gateway_api` module, after Flux | the `gateway_api` module, after Flux | GKE's | the `gateway_api` module, after Flux |

On GKE and Kapsule nothing is installed, and the `cilium` variable is refused
at plan.

## The order of the releases

On aws, in one apply:

1. **`cilium`**, from `oci://quay.io/cilium/charts`, chart 1.20.2, in
   `kube-system`. It follows the cluster, not the node group: the bootstrap
   nodes boot `NotReady` and become Ready only once Cilium's agent runs on
   them, and a managed node group is `ACTIVE` only once its nodes are Ready.
   So Cilium cannot wait for the group, and the group cannot wait for Cilium.
2. **`aws_eks_addon.pod_identity_agent`**, a `hostNetwork` DaemonSet that
   needs nodes but not the network. It hands every Pod Identity association
   its credentials: without it, Crossplane's AWS providers hang on
   `169.254.170.23` without logging a line.
3. **`coredns`**, from `oci://ghcr.io/coredns/charts`, chart 1.47.1, after
   Cilium: its pods need a network.
4. **`snapshot-controller`**, then **`aws-ebs-csi-driver`** and, when
   `eks_addons.efs_csi` is set, **`aws-efs-csi-driver`**: Deployments, after
   Cilium and CoreDNS, the drivers after the agent, each with its own role
   bound through the add-on's `pod_identity_association`.
5. **`flux-operator`**, which `depends_on` Cilium, CoreDNS and the Pod
   Identity Agent; then the instance and the envelope
   ([The Flux catalog](flux-catalog.md#what-opentofu-deposits)).

On azure the same order without CoreDNS and without the add-ons. The ordering
point holds on every cloud: whatever hands out cloud identities runs before
the first catalog module
([SOCLE-23](../decisions/socle.md#socle-23-eks-add-ons-from-the-bootstrap-the-pod-identity-agent-before-flux)).

**Waiting for nodes.** Everything after Cilium waits for the foundations'
node group through `schedulable_nodes`
(`module.foundations.bootstrap_node_group.node_count`), so it starts once
nodes exist and is uninstalled before them on a destroy. Zero fails the plan
with "The cluster has no schedulable node", instead of a Helm timeout ten
minutes later; on aws `bootstrap_node_count` below 1 is already refused by the
foundations. The check reads the group's size, not a live node count. With no
node at all, Cilium's release returns (a DaemonSet with nothing to schedule)
and CoreDNS's pods stay `Pending` until Helm's timeout; the add-ons report
`DEGRADED`. The node group itself, its sizing and its cost are the AWS
foundations' ([AWS decisions](../decisions/aws.md)).

## Cilium's configuration

**AWS.** `eni.enabled: true` alone yields `ipam: eni`, `routing-mode:
native`, endpoint routes and masquerade off: pods carry VPC addresses and
leave through the NAT Gateway like the nodes. ENIs go in the node's own
subnet and inherit `eth0`'s security groups. `kubeProxyReplacement: true`,
with `k8sServiceHost` and `k8sServicePort` taken from the foundations'
`cluster_endpoint` output: without kube-proxy there is no ClusterIP to reach
the API server through. The operator creates ENIs from its node's role: it
runs `hostNetwork`, and the foundations attach its policy to the bootstrap
nodes' role.

**Azure.** `aksbyocni.enabled: true` yields cluster-pool IPAM over a VXLAN
tunnel, with masquerade, the overlay the foundations' network assumes (the
subnet is sized for nodes only). The pool is the foundations' `pod_cidr`
(default `10.244.0.0/16`): the chart's default, `10.0.0.0/8`, contains the
default VNet. `kubeProxyReplacement: true` with the private FQDN as
`k8sServiceHost`. AKS keeps deploying kube-proxy, because azurerm cannot
turn it off; both run.

**Both.** One operator replica. Hubble in the agent always; Relay and UI only
with `cilium.hubble = true`. `rollOutCiliumPods` on, so a configuration
change restarts the agents. Requests set, limits not: agent 100m and 256Mi,
Envoy 50m and 128Mi, operator 50m and 128Mi. A memory limit on the CNI is a
guess that kills the network when it is wrong. `gatewayAPI.enabled` follows
`cilium.gateway_api`, with `gatewayClass.create: "false"`: the class is the
catalog's.

## CoreDNS

On aws the bootstrap installs CoreDNS by Helm rather than as the EKS managed
add-on
([SOCLE-24](../decisions/socle.md#socle-24-coredns-by-helm-on-aws-not-the-eks-add-on)).
The add-on cannot be created before a CNI: its pods never schedule, it sits
`DEGRADED`, and the aws provider waits for `ACTIVE` until its 20-minute
timeout. Helm with `wait` is the same dependency in the right order.

It gets `fullnameOverride: coredns`, a Service named `kube-dns` with label
`k8s-app: kube-dns` at the `.10` address of the cluster's service range (what
every EKS node's kubelet is given as `clusterDNS`; the range is the
foundations' `service_cidr` output), two replicas spread across nodes when
there are two, `system-cluster-critical`, a disruption budget of one, and
the managed add-on's own requests and limits. The chart's CoreDNS
configuration is unchanged. Chart 1.47.1 ships CoreDNS 1.14.6; the socle,
not AWS, tracks which CoreDNS runs on which Kubernetes minor.

On azure AKS deploys CoreDNS as a system component whatever the network
plugin; it starts once Cilium runs.

## Gateway API

Cilium starts with `gatewayAPI.enabled` and no CRDs. Its operator stays
Ready, switches its Gateway controller off, and never looks again. The CRDs
arrive after Flux, through the `gateway_api` catalog module, which then
creates the `cilium` GatewayClass and restarts the Cilium operator once. See
[gateway-api](../catalog/gateway-api.md).

## What a client may set

`cilium = { enabled, hubble, gateway_api, values }` on aws and azure,
`coredns = { values }` on aws, `eks_addons = { … }` on aws, each validated
like `kube`. The cluster's own facts (`cluster_network`: API endpoint,
service range, pod range) come from the foundations' outputs in the root,
never from the tfvars. The attributes are listed in
[Inputs](../reference/inputs.md#cilium-coredns-and-the-eks-add-ons).

## What is not proven

floci's EKS is a k3s with flannel, kube-proxy and CoreDNS, and floci 2.1.0
has no add-on API. Every e2e root therefore sets `cilium = { enabled = false
}` and leaves the add-ons off: CI proves the rest of the bootstrap path with
the same inputs and ordering, not Cilium itself. Cilium converging on a real
EKS or AKS, the ENI IPAM, CoreDNS's address and the node group going Ready
under Cilium are proven by the first real apply. The ordering beside the
node group is checked in `tofu graph`: `helm_release.cilium` reaches the
cluster and not the group; CoreDNS, the operator and the envelope reach both.
