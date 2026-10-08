---
title: Cilium before Flux
description: Why the bootstrap installs Cilium, CoreDNS and the EKS add-ons ahead of Flux on the clouds created with no CNI, and in what order.
sidebar:
  order: 5
---

On aws and azure the foundations create a cluster with no network plugin, so
Flux cannot start and the catalog cannot deliver the network. The bootstrap
installs it first, with Helm, in the same apply.

## The chicken-and-egg

EKS is created with no VPC CNI, kube-proxy or CoreDNS; AKS with
`network_plugin = "none"`. Every pod without `hostNetwork` stays `Pending`,
Flux included. Cilium's agent, operator and Envoy run `hostNetwork`, so Helm
can install them there.
Cilium is therefore not a catalog module: one release, one owner.

## What is installed, per cloud

| | AWS (EKS) | Azure (AKS, BYO CNI) | GCP (Autopilot) | Scaleway (Kapsule) |
| --- | --- | --- | --- | --- |
| Cilium | the socle's: ENI IPAM, native routing | the socle's: cluster-pool IPAM, VXLAN | Dataplane V2, Google's | Scaleway's |
| kube-proxy | none; Cilium replaces it | AKS's; Cilium replaces it too | Google's | Scaleway's |
| CoreDNS | the socle's, by Helm | AKS's | Google's | Scaleway's |
| EKS add-ons | Pod Identity Agent, snapshot controller, EBS CSI; EFS CSI on request | — | — | — |
| Gateway API CRDs | `gateway_api` module, after Flux | `gateway_api` module | GKE's | `gateway_api` module |

On GKE and Kapsule the `cilium` variable is refused at plan.

## The order of the releases

On aws, in one apply:

1. **`cilium`** (chart 1.20.2). It follows the cluster, not the node group:
   the nodes become Ready only once Cilium runs on them.
2. **The Pod Identity Agent**, without which Crossplane's AWS providers hang
   on `169.254.170.23`.
3. **`coredns`** (chart 1.47.1), once Cilium gives its pods a network.
4. **`snapshot-controller`**, the **EBS CSI** driver and, with
   `eks_addons.efs_csi`, the **EFS CSI** driver, each with its own role.
5. **`flux-operator`**, then the instance and the envelope
   ([The Flux catalog](flux-catalog.md#what-opentofu-deposits)).

On azure, the same without CoreDNS and the add-ons. On every cloud, what
hands out cloud identities runs before the first module.

Everything after Cilium waits for the node group through `schedulable_nodes`,
and is uninstalled before it on a destroy. Zero nodes fails the plan with
"The cluster has no schedulable node".

## Cilium's configuration

Requests set, no limits (a wrong memory limit on the CNI kills the network);
Hubble Relay and UI only with `cilium.hubble = true`; the Gateway controller
follows `cilium.gateway_api`, the class being the catalog's.

<details>
<summary>Under the hood</summary>

**AWS.** `eni.enabled: true`: ENI IPAM, native routing, masquerade off; pods
carry VPC addresses and leave through the NAT Gateway. `kubeProxyReplacement:
true`, with `k8sServiceHost`/`Port` from the foundations' `cluster_endpoint`.
The operator creates ENIs from the bootstrap nodes' role.

**Azure.** `aksbyocni.enabled: true`: cluster-pool IPAM over VXLAN, with
masquerade. The pool is the foundations' `pod_cidr` (`10.244.0.0/16`), since
the chart's `10.0.0.0/8` contains the default VNet. AKS keeps deploying
kube-proxy (azurerm cannot turn it off); both run.

**Both.** One operator replica, `rollOutCiliumPods` on. Requests: agent 100m
and 256Mi, Envoy and operator 50m and 128Mi. `gatewayClass.create: "false"`.

</details>

## CoreDNS

On aws CoreDNS is installed by Helm, not as the EKS add-on: the add-on
cannot be created before a CNI and would sit `DEGRADED` until a 20-minute
timeout.
On azure AKS deploys its own once Cilium runs.

<details>
<summary>Under the hood</summary>

`fullnameOverride: coredns`; a Service `kube-dns` (label `k8s-app:
kube-dns`) at the `.10` address of the foundations' `service_cidr`, the
kubelet's `clusterDNS`; two replicas spread across nodes;
`system-cluster-critical`; a disruption budget of one; the add-on's requests
and limits. Chart 1.47.1 ships CoreDNS 1.14.6: the socle tracks which
CoreDNS runs on which Kubernetes minor.

</details>

## Gateway API

Cilium starts with no Gateway API CRDs and switches its controller off. The
[gateway-api](../catalog/gateway-api.md) module brings the CRDs after Flux,
creates the `cilium` class and restarts the Cilium operator once.

## What you may set

`cilium = { enabled, hubble, gateway_api, values }` on aws and azure,
`coredns = { values }` and `eks_addons = { … }` on aws, each validated like
`kube` ([Inputs](../reference/inputs.md#cilium-coredns-and-the-eks-add-ons)).
The cluster's network facts come from the foundations, never the tfvars.

## What is not proven

floci's EKS is a k3s with its own CNI and no add-on API, so every e2e root
sets `cilium = { enabled = false }`. Cilium, CoreDNS and the add-ons on a
real EKS or AKS are proven by the first real apply; the ordering is checked
in `tofu graph`.
