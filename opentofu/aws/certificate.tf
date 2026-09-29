# The shared Gateways' certificate — docs/catalog/gateway-api.md.
#
# TLS for the socle's two Gateways terminates at the AWS load balancer, not in
# the cluster: the NLB in front of each Gateway holds this ACM certificate and
# forwards plain HTTP to Cilium's Envoy. No private key ever exists in the
# cluster, in a Secret or in the OpenTofu state, and ACM renews it by itself
# for as long as the validation records stay in the zone.
#
# One certificate, the domain and its wildcard, for both Gateways: every
# route the catalog or the client publishes is <name>.<domain>, whether it is
# served on the internet-facing Gateway or on the internal one. Validated by
# DNS in the client's Route 53 zone, which must be public — ACM resolves the
# validation records from the internet, including for a name only the
# internal Gateway serves.
#
# Null, the default, creates nothing, and the bootstrap module then creates
# no Gateway on aws: the socle never serves a route in clear text.

resource "aws_acm_certificate" "gateway" {
  count = var.gateway_certificate == null ? 0 : 1

  domain_name               = var.gateway_certificate.domain
  subject_alternative_names = ["*.${var.gateway_certificate.domain}"]
  validation_method         = "DNS"

  # A replacement is issued before the old one is released: the load
  # balancers reference the ARN, and ACM refuses to delete a certificate
  # still in use.
  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

# Keyed by domain, the one key known at plan: the record names are ACM's and
# exist only once the certificate does. The domain and its wildcard share one
# validation record, so both keys write the same one — the provider's own
# documented pattern, which allow_overwrite makes idempotent.
resource "aws_route53_record" "gateway_certificate_validation" {
  for_each = var.gateway_certificate == null ? {} : {
    for o in aws_acm_certificate.gateway[0].domain_validation_options : o.domain_name => o
  }

  zone_id = var.gateway_certificate.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300

  # The record is ACM's, not ours, and the two keys above share it; a
  # previous certificate for the same domain may also have left it behind.
  allow_overwrite = true
}

# Waits until ACM has issued the certificate, so the ARN the bootstrap module
# receives is one a load balancer can use.
resource "aws_acm_certificate_validation" "gateway" {
  count = var.gateway_certificate == null ? 0 : 1

  certificate_arn         = aws_acm_certificate.gateway[0].arn
  validation_record_fqdns = distinct([for r in aws_route53_record.gateway_certificate_validation : r.fqdn])
}
