# Identities — docs/gcp/managed-scope.md.
#
# Workload Identity Federation itself has nothing to configure: Autopilot
# pre-configures it and it cannot be disabled. No Google service account is
# created, here or anywhere in the socle: a workload's identity is its
# Kubernetes ServiceAccount as a federated principal, and what a catalog
# module's principal may do is bound by Crossplane, from that module — the one
# exception being Crossplane's own grants, below.

# Read-only metric access for the central observability cluster. A federated
# principal, never a key — the module refuses to accept a credential as input,
# so there is nothing here to leak.
resource "google_project_iam_member" "observability_reader" {
  for_each = toset(var.observability_reader_members)

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = each.value
}

# --- crossplane — docs/catalog/crossplane.md ----------------------------------
#
# The one workload identity the socle cannot make for itself: Crossplane binds
# every other one, and something has to bind Crossplane's. Its principal is
# known before the cluster has a node — the socle artifact runs every GCP
# provider pod as crossplane-system/provider-gcp — so its grants are written
# here, and only when asked. No Google service account: the principal is the
# Kubernetes ServiceAccount itself, federated by the pool Autopilot enforces,
# as every module's will be.
#
# An identity that can grant IAM roles is the most powerful thing in the
# cluster. What bounds it, grant by grant below:
# - project-level roles through Project IAM Admin, under a condition on
#   iam.googleapis.com/modifiedGrantsByRole: it may grant and revoke the roles
#   the client allows (crossplane.allowed_roles) and the socle's DNS records
#   role, nothing else — not Project IAM Admin itself, so it can never lift
#   its own condition;
# - buckets under the cluster's own name prefix only, through a custom role
#   with no delete and no object access, bounded by the same role list when it
#   sets a bucket's IAM policy;
# - nothing of Cloud DNS: no zone's IAM policy (below, at dns_records).
# What it cannot bound: who a role is granted to. The condition names roles,
# not members, so a compromised Crossplane could grant an allowed role to any
# principal. The list is the answer — such a grant is worth exactly the
# allowed roles, never an identity, the project, or a role that grants roles:
# owner, editor, viewer, iam.* and resourcemanager.* are refused at plan, and
# so is every predefined admin or owner role (roles/storage.admin,
# roles/compute.instanceAdmin.v1, roles/bigquery.dataOwner,
# roles/storage.legacyBucketOwner, …): those carry a setIamPolicy permission,
# and Crossplane could grant one to itself, unconditioned, and step outside
# this bound on every resource of that service — Google's own warning:
# https://cloud.google.com/iam/docs/setting-limits-on-granting-roles
# One exception, roles/storage.objectAdmin, which Velero needs: its
# storage.objects.setIamPolicy writes object ACLs, which a bucket with
# uniform bucket-level access does not have. What the plan cannot refuse is a
# custom role carrying setIamPolicy; that stays the reviewer's job.
#
# The list names roles, not resources: which secret, which bucket a module
# reaches is that module's own binding, so a new module never needs a change
# here, only, when it needs a new role, one line in the client's tfvars.
#
# Measured on a sandbox project (2026-10-07), on top of what the documents
# below say: under the Project IAM Admin condition, granting an allowed role
# succeeded and granting roles/owner was denied; under the bucket condition,
# creating a bucket inside the prefix succeeded and outside it was denied,
# granting roles/storage.objectAdmin on a bucket to a module's principal
# succeeded and roles/storage.admin was denied.
#
# Custom roles are soft-deleted: a destroy followed by an apply within Google's
# retention window finds the ID taken, and the provider undeletes and updates
# the role rather than failing.

locals {
  crossplane_principal = "${local.workload_identity_principal_prefix}/ns/crossplane-system/sa/provider-gcp"

  # Built from the role's ID rather than read off its name attribute, which
  # stays unknown until Google creates the role: the conditions below embed
  # it, and the bootstrap module receives it, on the very first plan.
  dns_records_role = var.crossplane == null ? "" : "projects/${var.project_id}/roles/${google_project_iam_custom_role.dns_records[0].role_id}"

  # Google accepts at most ten roles in hasOnly(), which is why the variable
  # caps the client's list at nine: the DNS records role is always the tenth.
  crossplane_granted_roles = concat(try(var.crossplane.allowed_roles, []), var.crossplane == null ? [] : [local.dns_records_role])

  # The limited IAM admin condition, verbatim from Google's documentation:
  # https://cloud.google.com/iam/docs/setting-limits-on-granting-roles
  # The attribute is defined only on a request that sets an allow policy;
  # everywhere else it is the default [], which hasOnly() accepts — so the
  # condition limits grants and nothing else.
  crossplane_grants_only_these = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(${jsonencode(local.crossplane_granted_roles)})"
}

# Only projects, folders and organisations accept modifiedGrantsByRole in
# their allow policies, so the bound sits on the project's policy, and Project
# IAM Admin is the role Google documents for it:
# https://cloud.google.com/iam/docs/setting-limits-on-granting-roles
resource "google_project_iam_member" "crossplane_project_grants" {
  count = var.crossplane == null ? 0 : 1

  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = local.crossplane_principal

  condition {
    title       = "socle-${var.cluster_name}-grants-only-allowed-roles"
    description = "Crossplane may grant and revoke only the roles the client allows."
    expression  = local.crossplane_grants_only_these
  }
}

# A module's own bucket, as on AWS: under a prefix the cluster owns
# (docs/catalog/crossplane.md §3, docs/catalog/velero.md §8). Create it, read
# and update its configuration, set its IAM policy so the module's principal
# can use it. No delete of any kind and no object permission: Crossplane can
# never delete the bucket, nor read what is in it, whatever a managed
# resource's deletionPolicy says. It can still change the bucket:
# storage.buckets.update writes its lifecycle rules and its uniform
# bucket-level access, as the AWS statement writes lifecycle. No
# storage.buckets.list either: it is checked on the project, where a
# bucket-name condition never grants it.
resource "google_project_iam_custom_role" "crossplane_buckets" {
  count = var.crossplane == null ? 0 : 1

  project     = var.project_id
  role_id     = "socleCrossplaneBuckets_${local.cluster_snake}"
  title       = "Socle ${var.cluster_name} Crossplane buckets"
  description = "Create and configure the ${var.cluster_name} socle's buckets, never delete them."
  permissions = [
    "storage.buckets.create",
    "storage.buckets.get",
    "storage.buckets.update",
    "storage.buckets.getIamPolicy",
    "storage.buckets.setIamPolicy",
  ]
}

# resource.name is a bucket's projects/_/buckets/<name>
# (https://cloud.google.com/iam/docs/conditions-resource-attributes), and it
# bounds storage.buckets.create too — measured, see above: Google's documents
# do not say so, and storage.buckets.create is described as a project
# permission. Cloud Storage recognises modifiedGrantsByRole
# (https://cloud.google.com/iam/docs/conditions-attribute-reference), so the
# same role list bounds a bucket's IAM policy.
#
# The prefix is <cluster_name>-, the shape AWS's bucket statement has, and
# like it not exclusive between clusters: cluster socle reaches the buckets of
# a cluster named socle-prod in the same project. Two clusters of one project
# take names neither of which prefixes the other.
resource "google_project_iam_member" "crossplane_buckets" {
  count = var.crossplane == null ? 0 : 1

  project = var.project_id
  role    = "projects/${var.project_id}/roles/${google_project_iam_custom_role.crossplane_buckets[0].role_id}"
  member  = local.crossplane_principal

  condition {
    title       = "socle-${var.cluster_name}-own-buckets"
    description = "Only buckets under the ${var.cluster_name}- prefix, and only the allowed roles on them."
    expression  = "resource.name.startsWith('projects/_/buckets/${var.cluster_name}-') && ${local.crossplane_grants_only_these}"
  }
}

# What the socle hands external-dns: its records, at project level. Never a
# zone's IAM policy, and so nothing of Cloud DNS for Crossplane itself —
# measured on a sandbox project (2026-10-07): dns.managedZones.getIamPolicy
# and setIamPolicy granted on a managed zone, by a custom role and even by
# roles/dns.admin, are never honoured (403 for minutes on end), while record
# operations granted on the same zone are. A zone's IAM therefore needs a
# project-level grant, and IAM conditions do not apply to Cloud DNS to bound
# it to a zone. So the socle creates this role, Crossplane grants it to
# external-dns's principal on the project under the hasOnly() condition
# above, and the bound on what external-dns writes is its --domain-filter.
# One socle cluster per project, then: this role reaches every zone of it.
#
# The socle's custom roles are created here, not by a module: Crossplane is
# denied iam.roles.create, and only Crossplane grants them to a module.
resource "google_project_iam_custom_role" "dns_records" {
  count = var.crossplane == null ? 0 : 1

  project     = var.project_id
  role_id     = "socleDnsRecords_${local.cluster_snake}"
  title       = "Socle ${var.cluster_name} DNS records"
  description = "Find the project's managed zones and write their records, for the ${var.cluster_name} socle's external-dns."
  permissions = [
    "dns.managedZones.get",
    "dns.managedZones.list",
    "dns.changes.create",
    "dns.changes.get",
    "dns.changes.list",
    "dns.resourceRecordSets.create",
    "dns.resourceRecordSets.delete",
    "dns.resourceRecordSets.get",
    "dns.resourceRecordSets.list",
    "dns.resourceRecordSets.update",
  ]
}
