# The shared Gateways — `public` and `private`

The `gateway_api` module brings the Gateway API CRDs and, where the socle runs
Cilium, the `cilium` GatewayClass ([cilium.md §4](cilium.md)). On gcp it
brings neither: GKE owns both. It also creates the two Gateways that every
catalog module and the client attach their routes to:

| Gateway | Exposure | aws | azure | gcp |
| --- | --- | --- | --- | --- |
| `gateway-system/public` | internet-facing | NLB in the public subnets (`kubernetes.io/role/elb`) | public Azure load balancer | global external Application Load Balancer (`gke-l7-global-external-managed`) |
| `gateway-system/private` | internal to the network | internal NLB in the private subnets (`kubernetes.io/role/internal-elb`) | internal Azure load balancer | regional internal Application Load Balancer (`gke-l7-rilb`), in the foundations' proxy-only subnetwork |

| Question | Position |
| --- | --- |
| Where | aws and azure, where the socle's Cilium serves the `cilium` class; gcp, on GKE's own classes — the module installs no CRD and no class there, only the two Gateways. Not on scaleway, where no controller serves a class yet |
| Default | On (`kube.gateway_api.gateways = true`). On aws and gcp only once the foundations have issued the certificates (`aws.gateway_certificate`, `gcp.gateway_certificate`), because the socle never serves a route in clear text |
| Listeners | `https` on 443, where routes attach from every namespace. On azure and gcp also `http` on 80, where a single `HTTPRoute` redirects everything to https with a 301. **No port 80 on aws** — see below |
| TLS on aws | Terminated at the NLB with an ACM certificate for `domain` and `*.domain`, issued and DNS-validated by the foundations in the public Route 53 zone of that name, found by name (`aws.gateway_certificate = { domain }`). The NLB forwards plain HTTP, so `https` is an `HTTP` listener on 443. No private key ever exists in the cluster, in a Secret or in the OpenTofu state, and ACM renews the certificate by itself |
| TLS on azure | Azure's load balancer is L4 only, so Envoy terminates TLS with the `gateway-system/gateway-tls` Secret, which the client creates. Until it exists, the `https` listener is not programmed and the redirect still answers |
| TLS on gcp | Terminated at the Google load balancer with Google-managed Certificate Manager certificates for the `gcp.gateway_certificate` domains, DNS-authorised in the client's Cloud DNS zone by the foundations. The two classes take them differently ([Secure a Gateway](https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway)): `public` names a certificate map in the `networking.gke.io/certmap` annotation, and its `https` listener has no `tls` block; `private` — a regional Gateway, which takes no map — names the regional certificate in its `https` listener's `tls.options` `networking.gke.io/cert-manager-certs`, a listener option and not an annotation. No key exists in the cluster, and Certificate Manager renews both |
| Who routes | `argocd` attaches to `private` by default (`kube.argocd.gateway`). A client's route names a Gateway and `sectionName: https` |

## How the load balancer is chosen

On gcp there is no Service: GKE's controller builds the Google load balancer
from the Gateway itself, by its class, and the template sets no
`spec.infrastructure`. The rest of this section is aws and azure.

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

## Why there is no port 80 on aws

Cilium serves every listener of a Gateway from **one** Envoy listener, and
splits route tables by transport only — `listener-insecure` for plain
traffic, `listener-secure` for TLS — never by port. On aws the NLB
terminates TLS, so 80 and 443 both reach Envoy in clear text and share
`listener-insecure`, matched on the Host header alone. Measured on EKS
with both listeners in place: `http://argocd.<domain>` served ArgoCD in
clear instead of redirecting, and `https://<unknown>.<domain>` answered the
redirect to itself — a loop. The `sectionName` of a route selects its
Gateway listener in the API, not a port in Envoy.

So on aws the Gateways expose 443 only, until 443 reaches Envoy in TLS —
which puts it in its own route table, as on azure. Two ways, both follow-ups:
the NLB re-encrypting to Envoy (a TLS target group, Envoy terminating with an
internal certificate — cert-manager's self-signed issuer), or an ALB through
the AWS Load Balancer Controller, whose listener rule redirects natively.

## Why port 80 works on azure and gcp

On azure, 443 reaches Envoy in TLS, so it has its own route table. On gcp,
the Google load balancer has a forwarding rule and target proxy per
protocol, and GKE attaches a route to the listener its `sectionName` names,
so the redirect answers on 80 only — the sandbox has to confirm it, with
`curl` on both ports. GKE supports the redirect
filter (`scheme: https`, `statusCode: 301`) on both classes the socle uses
([GatewayClass capabilities](https://cloud.google.com/kubernetes-engine/docs/how-to/gatewayclass-capabilities);
it is the older `gke-l7-gxlb` classes that cannot redirect,
[Deploying Gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)).

## Ordering

A Gateway can be applied only once its CRD and class exist. The Gateways sit
in a child `ResourceSet`, `gateway-api-gateways`, which `dependsOn` the
`gateway-api-cilium` Kustomization being Ready — on gcp, GKE's two classes,
`gke-l7-global-external-managed` and `gke-l7-rilb`, being `Accepted`.

The child waits (`wait: true`) as on the other clouds, and that wait ends
when the Gateways are applied, not when their load balancers exist: a
Gateway has no `Ready` condition for the operator's health check to read.
GKE programs a Google load balancer minutes after accepting its Gateway;
routes only need it `Accepted`. ArgoCD's route follows the
same pattern: `argocd-route` `dependsOn` its Gateway being `Accepted`. The
route is the socle's own object and not the chart's, because the chart's
route would be applied with the release, possibly before the CRDs, and a
failed install stalls the release.

## What the bootstrap module tells the templates

```yaml
gateway:
  className: cilium            # gke-l7-global-external-managed on gcp
  shared: true                 # the two Gateways exist: a route may attach
  namespace: gateway-system
  certificateArn: arn:aws:acm:…  # aws; empty elsewhere
  certificateMap: ""           # gcp: the public Gateway's certificate map
  regionalCertificate: ""      # gcp: the private Gateway's regional certificate
```

`shared` is computed from these conditions: the module and `gateways` are on,
the class is `cilium` — or the cloud is gcp — and on aws and gcp a
certificate exists. A template that routes tests `shared`, never the
presence of the Gateway.

## Not measured yet

floci's k3s runs no Cilium, so `shared` is false there, and the e2e jobs create
no Gateway — `tests/e2e/chainsaw-test.yaml` (`gateway-api-floci`,
`platform: floci`) asserts exactly that: `shared` false in the inputs, no
`gateway-api-gateways` ResourceSet, no `gateway-system` namespace. The proof
is a sandbox EKS apply with `aws.gateway_certificate` set. It has to show
three things:

- both NLBs come up in the right subnets;
- on azure, `curl -I http://…` answers 301 (aws has no port 80);
- `https://argocd.<domain>` answers from inside the VPC only.

On gcp the proof is `gateway-api-gke` (`platform: gke`), run by hand against
the sandbox's GKE Autopilot: no CRD fetched by the socle, GKE's classes
Accepted, both Gateways `Programmed` with an address and the certificate
names from the inputs, the redirect accepted on both. What only the sandbox
shows, beyond it:

- how long each Gateway takes to be `Programmed` (the test allows 15
  minutes) — `private` waits for the regional proxy pool;
- `curl -I http://<public address>` answers 301, and `https://` presents the
  Certificate Manager certificate;
- `private` answers from inside the VPC only, with the regional certificate;
- the backends are healthy: GKE health-checks each Service on `/` unless a
  `HealthCheckPolicy` says otherwise, so a backend that does not answer 200
  there — Grafana redirects `/` to `/login` — is unhealthy behind GKE.

## Follow-ups

- **gRPC for the `argocd` CLI.** It needs a `GRPCRoute`, or `--grpc-web`,
  which works over the current HTTPRoute.
- **The NLB's TLS policy.** The in-tree controller applies AWS's default
  policy. A stricter one is a matter of one annotation, once it has been
  measured on the in-tree NLB.
- **Access to `public`.** The listener accepts routes from every namespace.
  Restricting it to labelled namespaces is a decision the first public module
  should make.
