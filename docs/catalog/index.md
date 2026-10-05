---
title: Catalog
description: The seventeen catalog modules, what each gives you, whether it is on by default, the clouds it runs on, and how kube turns them on.
sidebar:
  label: Overview
  order: 0
---

The catalog is what Flux installs on a socle cluster, one module at a time.
Each module is one Flux Operator `ResourceSet` in the signed artifact,
rendered from your `kube` block. Some are on by default; the others wait for
you to turn them on.

| Module | What it gives you | Category | Default | Clouds | Requires |
| --- | --- | --- | :---: | --- | --- |
| [`argocd`](argocd.md) | ArgoCD, the GitOps layer you ship your applications with | gitops | on | all | |
| [`gateway_api`](gateway-api.md) | Gateway API CRDs, the `cilium` GatewayClass and the shared `public` and `private` Gateways | networking | on | aws, azure, scaleway | |
| [`crossplane`](crossplane.md) | the tooling each module uses to declare its own cloud access | platform | off | all (providers on aws) | |
| [`external_dns`](external-dns.md) | DNS records for your Services, Ingresses and HTTPRoutes in your cloud's zone | networking | off | all | |
| [`external_secrets`](external-secrets.md) | Kubernetes Secrets read from your cloud's secret manager, kept in step when they rotate | secrets | off | all | |
| [`reloader`](reloader.md) | rolls a workload when a ConfigMap or Secret it reads changes | secrets | off | all | |
| [`keda`](keda.md) | event-driven autoscaling, down to zero | autoscaling | off | all | `crossplane` on aws, for a role |
| [`kyverno`](kyverno.md) | the Kyverno admission engine, with no policy | security | off | all | |
| [`kyverno_policies`](kyverno-policies.md) | Pod Security and image policies, in Audit, any of them enforceable natively | security | off | all | `kyverno` |
| [`velero`](velero.md) | backup and restore of your applications' volumes and objects, chosen by two labels | backup | off | aws | `crossplane` |
| [`victoria_metrics`](victoria-metrics.md) | metrics storage, 15 days | observability | on | all | |
| [`victoria_logs`](victoria-logs.md) | logs storage, 7 days | observability | on | all | |
| [`victoria_traces`](victoria-traces.md) | traces storage, off until VictoriaTraces is GA | observability | off | all | |
| [`otel_agent`](otel-agent.md) | node-level collector: kubelet metrics and container logs | observability | on | all | |
| [`otel_gateway`](otel-gateway.md) | cluster-level collector: object state, Prometheus scrapes, your applications' OTLP | observability | on | all | |
| [`grafana`](grafana.md) | one Grafana with a datasource per backend and every module's dashboards | observability | on | all | |
| [`hello`](hello.md) | podinfo, a smoke test that your socle renders, converges and garbage-collects | platform | on | all | |

"Clouds" is where the socle offers the module. On a cloud it is not offered
on, `tofu plan` refuses it. CI proves every module on AWS (floci); the other
clouds are offered and not yet applied. How the six observability modules
fit together is in [Observability](../architecture/observability.md).

Cilium, CoreDNS and the EKS add-ons are not catalog modules: they run before
Flux. See [Cilium before Flux](../architecture/cilium-before-flux.md).

## How kube turns them on

`kube` in your tfvars is `{ <module> = { <attribute> = <value> } }`. List
only what differs from the defaults; a module you leave out is at its
defaults, on or off as the table says.

```hcl
kube = {
  argocd     = { domain = "argocd.acme.example" }   # on by default: change an attribute
  kyverno    = { enabled = true }                   # off by default: turn it on
  hello      = { enabled = false }                  # on by default: turn it off
}
```

- Names are `snake_case`; the page, the folder and the namespace use the
  same name in `kebab-case`.
- Every module with a chart takes `values`, any chart value, yours winning
  over the socle's, and `values_secret`, the name of a Secret for what must
  not reach the OpenTofu state.
- A typo, a wrong type, or a module not offered on your cloud fails at plan,
  with the allowed list in the message.
- Turning a module off removes everything it installed; CRDs that hold your
  objects stay.

Each module's page lists its attributes. The whole schema is in
[Inputs](../reference/inputs.md#the-catalog-schema); the steps are in
[Enable a module](../guides/enable-a-module.md).
