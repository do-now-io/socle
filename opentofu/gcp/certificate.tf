# The shared Gateways' certificates — docs/catalog/gateway-api.md.
#
# TLS for the socle's two Gateways terminates at the Google load balancer, not
# in the cluster: no private key ever exists in the cluster, in a Secret or in
# the OpenTofu state, and Certificate Manager renews the certificates by
# itself for as long as the authorization records stay in the zone.
#
# Two certificates for the same names, because GKE's two Gateway classes take
# them differently
# (https://cloud.google.com/kubernetes-engine/docs/how-to/secure-gateway):
# - the public Gateway (gke-l7-global-external-managed) takes a certificate
#   map, through the networking.gke.io/certmap annotation;
# - the internal Gateway (gke-l7-rilb) takes no map — certificate maps are not
#   supported on regional Gateways — but regional Certificate Manager
#   certificates by name, in its HTTPS listener's
#   tls.options networking.gke.io/cert-manager-certs (a listener option, not
#   an annotation).
#
# Both are Google-managed and authorised by DNS in the client's Cloud DNS
# zone: a DNS authorization resolves from the internet, so it also covers a
# name only the internal Gateway serves. Null, the default, creates nothing,
# and the bootstrap module then creates no Gateway on gcp: the socle never
# serves a route in clear text.

locals {
  gateway_domains = try(var.gateway_certificate.domains, [])

  # An authorization covers one domain, and a wildcard is authorised on its
  # parent: *.acme.example and acme.example share acme.example's.
  # https://cloud.google.com/certificate-manager/docs/dns-authorizations
  gateway_authorized_domains = toset(distinct([for d in local.gateway_domains : trimprefix(d, "*.")]))

  # Named after the cluster, so two clusters in a project stay apart. Per
  # domain, names take a short digest of it: Certificate Manager names are
  # lowercase letters, digits and dashes, 63 at most, which a domain does not
  # fit, and a digest stays stable when the list is reordered.
  gateway_name = "${var.cluster_name}-gateway"

  # A certificate's domains cannot change in place, so a new list is a new
  # certificate — under a new name, the digest of the sorted list, so that it
  # can exist next to the one still in use until it replaces it.
  gateway_certificate_name = "${local.gateway_name}-${substr(sha1(join(",", sort(local.gateway_domains))), 0, 8)}"
}

# Global, for the global certificate: FIXED_RECORD, the default type, whose
# record is _acme-challenge.<domain>. That name must be free in the zone — a
# record another ACME client left there makes this apply fail on a conflict,
# and Cloud DNS has no overwrite. PER_PROJECT_RECORD would sidestep it, and
# global certificates accept that type too
# (https://cloud.google.com/certificate-manager/docs/deploy-google-managed-dns-auth),
# but its record is per project and documented with one example only: nothing
# says a global and a regional authorization of the same domain get distinct
# names, and two record sets of the same name would conflict on every apply.
resource "google_certificate_manager_dns_authorization" "gateway" {
  for_each = local.gateway_authorized_domains

  project = var.project_id
  name    = "${local.gateway_name}-${substr(sha1(each.value), 0, 8)}"
  domain  = each.value
  type    = "FIXED_RECORD"

  labels = local.labels
}

# Regional, for the regional certificate: a regional certificate takes only
# regional authorizations, and only of the PER_PROJECT_RECORD type — whose
# record, _acme-challenge_<project digest>.<domain>, differs from the global
# one, so both live in the zone together.
# https://cloud.google.com/certificate-manager/docs/deploy-google-managed-regional
resource "google_certificate_manager_dns_authorization" "gateway_regional" {
  for_each = local.gateway_authorized_domains

  project  = var.project_id
  location = var.region
  name     = "${local.gateway_name}-${substr(sha1(each.value), 0, 8)}"
  domain   = each.value
  type     = "PER_PROJECT_RECORD"

  labels = local.labels
}

# Keyed by scope and domain, the one key known at plan: the record names are
# Certificate Manager's and exist only once the authorization does. Always a
# CNAME.
resource "google_dns_record_set" "gateway_certificate_authorization" {
  for_each = merge(
    { for d, a in google_certificate_manager_dns_authorization.gateway : "global/${d}" => a.dns_resource_record[0] },
    { for d, a in google_certificate_manager_dns_authorization.gateway_regional : "${var.region}/${d}" => a.dns_resource_record[0] },
  )

  project      = var.project_id
  managed_zone = var.gateway_certificate.dns_zone
  name         = each.value.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [each.value.data]
}

resource "google_certificate_manager_certificate" "gateway" {
  count = var.gateway_certificate == null ? 0 : 1

  project     = var.project_id
  name        = local.gateway_certificate_name
  description = "The ${var.cluster_name} socle's public Gateway."

  managed {
    domains            = local.gateway_domains
    dns_authorizations = [for a in google_certificate_manager_dns_authorization.gateway : a.id]
  }

  # A replacement is issued before the old one is released: the certificate map
  # references it, and Certificate Manager refuses to delete a certificate
  # still in use.
  lifecycle {
    create_before_destroy = true
  }

  labels = local.labels
}

resource "google_certificate_manager_certificate_map" "gateway" {
  count = var.gateway_certificate == null ? 0 : 1

  project     = var.project_id
  name        = local.gateway_name
  description = "What the ${var.cluster_name} socle's public Gateway serves, through networking.gke.io/certmap."

  labels = local.labels
}

# One hostname entry per domain, wildcard included: the load balancer serves
# a name only if an entry matches it.
resource "google_certificate_manager_certificate_map_entry" "gateway" {
  for_each = toset(local.gateway_domains)

  project      = var.project_id
  name         = "${local.gateway_name}-${substr(sha1(each.value), 0, 8)}"
  map          = google_certificate_manager_certificate_map.gateway[0].name
  hostname     = each.value
  certificates = [google_certificate_manager_certificate.gateway[0].id]

  labels = local.labels
}

resource "google_certificate_manager_certificate" "gateway_regional" {
  count = var.gateway_certificate == null ? 0 : 1

  project     = var.project_id
  location    = var.region
  name        = local.gateway_certificate_name
  description = "The ${var.cluster_name} socle's internal Gateway."

  managed {
    domains            = local.gateway_domains
    dns_authorizations = [for a in google_certificate_manager_dns_authorization.gateway_regional : a.id]
  }

  # A replacement is issued before the old one is released: the internal Gateway's listener
  # references it, and Certificate Manager refuses to delete a certificate
  # still in use.
  lifecycle {
    create_before_destroy = true
  }

  labels = local.labels
}
