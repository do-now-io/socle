# The example tfvars is what a client copies, so it must plan as written.
# tests/example.auto.tfvars is a symlink to ../prod.tfvars.example (a Windows
# checkout needs core.symlinks), which tofu test loads for every file in this
# directory; this one sets no variable of its own. aws is not mocked: the run
# plans through the root's own stub provider, proving it makes no AWS call.

provider "google" {
  project      = "acme-prod"
  region       = "europe-west1"
  access_token = "offline-fixture-token"
}

override_data {
  target = module.foundations.data.google_project.this
  values = {
    number = "123456789012"
  }
}

mock_provider "helm" {}

run "the_example_plans" {
  command = plan

  assert {
    condition     = output.inputs.cluster.projectId == "acme-prod" && output.inputs.modules.hello.replicas == 2
    error_message = "prod.tfvars.example must plan as written, its values reaching the catalog."
  }
}
