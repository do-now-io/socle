# The example tfvars is what a client copies, so it must plan as written.
# tests/example.auto.tfvars is a symlink to ../prod.tfvars.example (a Windows
# checkout needs core.symlinks), which tofu test loads for every file in this
# directory; this one sets no variable of its own. Offline as in
# root.tftest.hcl.

provider "aws" {
  region                      = "eu-west-3"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
}

override_data {
  target = module.foundations.data.aws_caller_identity.current
  values = { account_id = "000000000000" }
}

override_data {
  target = module.socle.data.aws_caller_identity.current
  values = { account_id = "000000000000" }
}

mock_provider "helm" {}

run "the_example_plans" {
  command = plan

  assert {
    condition     = output.inputs.cluster.name == "acme-prod" && output.inputs.cluster.region == "eu-west-3" && output.inputs.modules.hello.enabled == true
    error_message = "prod.tfvars.example must plan as written, its values reaching the catalog."
  }
}
