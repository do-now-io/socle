# The shared Gateways — `public` and `private`

The `gateway_api` module brings the Gateway API CRDs and, where the socle runs
Cilium, the `cilium` GatewayClass ([cilium.md §4](cilium.md)). It also
creates the two Gateways that every catalog module and the client attach
their routes to:

| Gateway | Exposure | aws | azure |
| --- | --- | --- | --- |
| `gateway-system/public` | internet-facing | NLB in the public subnets (`kubernetes.io/role/elb`) | public Azure load balancer |
| `gateway-system/private` | internal to the network | internal NLB in the private subnets (`kubernetes.io/role/internal-elb`) | internal Azure load balancer |

| Question | Position |
| --- | --- |
| Where | aws and azure, where the socle's Cilium serves the `cilium` class. Not on gcp, where GKE owns Gateway API and the module is not offered. Not on scaleway, where no controller serves a class yet |
| Default | On (`kube.gateway_api.gateways = true`). On aws only once the foundations have issued the certificate (`aws.gateway_certificate`), because the socle never serves a route in clear text |
| Listeners | `http` on 80, where a single `HTTPRoute` redirects everything to https with a 301. `https` on 443, where routes attach from every namespace |
| TLS on aws | Terminated at the NLB with an ACM certificate for `domain` and `*.domain`, issued and DNS-validated by the foundations. The NLB forwards plain HTTP, so `https` is an `HTTP` listener on 443. No private key ever exists in the cluster, in a Secret or in the OpenTofu state, and ACM renews the certificate by itself |
| TLS on azure | Azure's load balancer is L4 only, so Envoy terminates TLS with the `gateway-system/gateway-tls` Secret, which the client creates. Until it exists, the `https` listener is not programmed and the redirect still answers |
| Who routes | `argocd` attaches to `private` by default (`kube.argocd.gateway`). A client's route names a Gateway and `sectionName: https` |

## How the load balancer is chosen

Cilium creates one `LoadBalancer` Service per Gateway. It copies
`spec.infrastructure.annotations` onto that Service, where the cloud's own
service controller reads them. There is no AWS Load Balancer Controller: on EKS
the in-tree controller reads these annotations.

```yaml
# aws, both Gateways
service.beta.kubernetes.io/aws-load-balancer-type: nlb
service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
service.beta.kubernetes.io/aws-load-balancer-ssl-cert: <inputs.gateway.certificateArn>
service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
# aws, private only
service.beta.kubernetes.io/aws-load-balancer-internal: "true"
# azure, private only
service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

## Ordering

A Gateway can be applied only once its CRD and class exist. The Gateways sit
in a child `ResourceSet`, `gateway-api-gateways`, which `dependsOn` the
`gateway-api-cilium` Kustomization being Ready. ArgoCD's route follows the
same pattern: `argocd-route` `dependsOn` its Gateway being `Accepted`. The
route is the socle's own object and not the chart's, because the chart's
route would be applied with the release, possibly before the CRDs, and a
failed install stalls the release.

## What the bootstrap module tells the templates

```yaml
gateway:
  className: cilium
  shared: true                 # the two Gateways exist: a route may attach
  namespace: gateway-system
  certificateArn: arn:aws:acm:…  # aws; empty elsewhere
```

`shared` is computed from these conditions: the module and `gateways` are on,
the class is `cilium`, and on aws a certificate exists. A template that
routes tests `shared`, never the presence of the Gateway.

## Not measured yet

floci's k3s runs no Cilium, so `shared` is false there, and the e2e jobs create
no Gateway. The proof is a sandbox EKS apply with `aws.gateway_certificate`
set. It has to show three things:

- both NLBs come up in the right subnets;
- `curl -I http://…` answers 301;
- `https://argocd.<domain>` answers from inside the VPC only.

## Follow-ups

- **gRPC for the `argocd` CLI.** It needs a `GRPCRoute`, or `--grpc-web`,
  which works over the current HTTPRoute.
- **The NLB's TLS policy.** The in-tree controller applies AWS's default
  policy. A stricter one is a matter of one annotation, once it has been
  measured on the in-tree NLB.
- **Access to `public`.** The listener accepts routes from every namespace.
  Restricting it to labelled namespaces is a decision the first public module
  should make.
