# What the root adds over its two modules: the values it derives for the
# catalog from the foundations, and the warning when Crossplane has no
# identity. helm and aws are mocked; google is kept offline by a static
# token: no run reaches Google, AWS or a cluster.

# A static access token keeps the google provider offline, as in the
# foundations' own tests: a plan creates every resource, so it reads none.
# A mock would not do: it invents a cluster CA the helm provider's
# kubernetes block cannot base64-decode, and a block cannot be overridden.
provider "google" {
  project      = "socle-test-project"
  region       = "europe-west1"
  access_token = "offline-fixture-token"
}

# The project's number is the one value the foundations read from the API.
override_data {
  target = module.foundations.data.google_project.this
  values = {
    number = "123456789012"
  }
}

mock_provider "helm" {}

mock_provider "aws" {}

# kube is reset here: tests/example.auto.tfvars, the example a client copies,
# is loaded for every file in this directory.
variables {
  socle_version = "0.0.0"
  kube          = {}
  gcp = {
    project_id     = "socle-test-project"
    region         = "europe-west1"
    cluster_name   = "socle-test"
    owner          = "platform"
    environment    = "prod"
    create_network = true
    maintenance_window = {
      start_time = "2026-01-03T02:00:00Z"
      end_time   = "2026-01-03T14:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }
}

run "the_project_comes_from_the_foundations" {
  command = plan

  assert {
    condition     = output.inputs.cluster.projectId == "socle-test-project" && output.inputs.cluster.projectNumber == "123456789012"
    error_message = "the catalog's project is the foundations' project_id and the number they read, which every Workload Identity principal names."
  }
}

run "crossplane_inputs_come_from_the_foundations" {
  command = plan
  variables {
    gcp = {
      project_id     = "socle-test-project"
      region         = "europe-west1"
      cluster_name   = "socle-test"
      owner          = "platform"
      environment    = "prod"
      create_network = true
      maintenance_window = {
        start_time = "2026-01-03T02:00:00Z"
        end_time   = "2026-01-03T14:00:00Z"
        recurrence = "FREQ=WEEKLY;BYDAY=SA"
      }
      crossplane = { allowed_roles = ["roles/secretmanager.secretAccessor"] }
    }
    kube = { crossplane = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.crossplane.dns_records_role == "projects/socle-test-project/roles/socleDnsRecords_socle_test"
    error_message = "kube.crossplane.dns_records_role must be the foundations' dns_records_role when gcp.crossplane is set."
  }

  assert {
    condition     = !contains(keys(output.inputs.modules.crossplane), "dns_zones")
    error_message = "Crossplane holds nothing of Cloud DNS: no zone list reaches the catalog."
  }
}

run "crossplane_inputs_stay_empty_without_an_identity" {
  command = plan

  assert {
    condition     = output.inputs.modules.crossplane.dns_records_role == ""
    error_message = "without gcp.crossplane there is no DNS records role: the catalog gets none."
  }
}

run "client_value_wins" {
  command = plan
  variables {
    gcp = {
      project_id     = "socle-test-project"
      region         = "europe-west1"
      cluster_name   = "socle-test"
      owner          = "platform"
      environment    = "prod"
      create_network = true
      maintenance_window = {
        start_time = "2026-01-03T02:00:00Z"
        end_time   = "2026-01-03T14:00:00Z"
        recurrence = "FREQ=WEEKLY;BYDAY=SA"
      }
      crossplane          = {}
      gateway_certificate = { dns_zone = "sandbox-gcp-do-now-io", domains = ["sandbox-gcp.do-now.io"] }
    }
    kube = {
      crossplane   = { enabled = true, dns_records_role = "projects/socle-test-project/roles/clientDnsRecords" }
      external_dns = { enabled = false }
    }
  }

  assert {
    condition     = output.inputs.modules.crossplane.dns_records_role == "projects/socle-test-project/roles/clientDnsRecords"
    error_message = "a dns_records_role the client wrote under kube.crossplane must win over the derived one."
  }

  assert {
    condition     = output.inputs.modules.crossplane.enabled == true
    error_message = "a key the client wrote alongside it is kept."
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == false
    error_message = "external_dns = { enabled = false } must turn the derived default off."
  }
}

run "external_dns_follows_the_certificate" {
  command = plan
  variables {
    gcp = {
      project_id     = "socle-test-project"
      region         = "europe-west1"
      cluster_name   = "socle-test"
      owner          = "platform"
      environment    = "prod"
      create_network = true
      maintenance_window = {
        start_time = "2026-01-03T02:00:00Z"
        end_time   = "2026-01-03T14:00:00Z"
        recurrence = "FREQ=WEEKLY;BYDAY=SA"
      }
      crossplane          = {}
      gateway_certificate = { dns_zone = "sandbox-gcp-do-now-io", domains = ["sandbox-gcp.do-now.io", "*.sandbox-gcp.do-now.io"] }
    }
    kube = { crossplane = { enabled = true } }
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == true
    error_message = "with the certificate, Crossplane on and its identity, external_dns is on by default — no zone list: it writes through a project role."
  }

  assert {
    condition     = tolist(output.inputs.modules.external_dns.domain_filters) == tolist(["sandbox-gcp.do-now.io"])
    error_message = "external_dns is filtered to the certificate's domains, a wildcard counted once by its apex."
  }
}

run "external_dns_stays_off_without_crossplane" {
  command = plan
  variables {
    gcp = {
      project_id     = "socle-test-project"
      region         = "europe-west1"
      cluster_name   = "socle-test"
      owner          = "platform"
      environment    = "prod"
      create_network = true
      maintenance_window = {
        start_time = "2026-01-03T02:00:00Z"
        end_time   = "2026-01-03T14:00:00Z"
        recurrence = "FREQ=WEEKLY;BYDAY=SA"
      }
      crossplane          = { allowed_roles = ["roles/secretmanager.secretAccessor"] }
      gateway_certificate = { dns_zone = "sandbox-gcp-do-now-io", domains = ["sandbox-gcp.do-now.io"] }
    }
    kube = { crossplane = { enabled = false } }
  }

  assert {
    condition     = output.inputs.modules.external_dns.enabled == false
    error_message = "without the crossplane module on, nothing binds external-dns's role: it stays off."
  }
}

run "crossplane_without_identity_warns" {
  command = plan
  variables {
    kube = { crossplane = { enabled = true } }
  }

  expect_failures = [check.crossplane_has_an_identity]
}

# On a destroy, the catalog must be uninstalled — Crossplane deleting every
# module's binding — while Crossplane still holds its grants, or each delete
# is a 403 and the binding stays in the project. A plan targeting the
# catalog's envelope alone evaluates only what it depends on: the
# foundations' crossplane_principal is there only if the root threads it
# into the catalog's inputs. That it is read off the grants is the
# foundations' own test (crossplane_principal_is_read_off_the_grants).
run "the_catalog_depends_on_crossplane_grants" {
  command = plan
  variables {
    gcp = {
      project_id     = "socle-test-project"
      region         = "europe-west1"
      cluster_name   = "socle-test"
      owner          = "platform"
      environment    = "prod"
      create_network = true
      maintenance_window = {
        start_time = "2026-01-03T02:00:00Z"
        end_time   = "2026-01-03T14:00:00Z"
        recurrence = "FREQ=WEEKLY;BYDAY=SA"
      }
      crossplane = {}
    }
    kube = { crossplane = { enabled = true } }
  }

  plan_options {
    target = [module.socle.helm_release.socle]
  }

  assert {
    condition     = module.foundations.crossplane_principal != null
    error_message = "the catalog's envelope must depend on Crossplane's grants, so a destroy uninstalls the catalog before it removes them."
  }
}
