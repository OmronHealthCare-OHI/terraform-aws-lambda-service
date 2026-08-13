# The caller owns the label: it states where it deploys and where it sits in the
# ohi:* hierarchy, and hands the resolved context to every module it calls.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=0.1.1"

  country    = "us"
  aws_region = "us-west-2"
  non_prd    = true # -> prefix usnp-usw2

  project     = "vlt"
  application = "platform"
  module      = "example"
  owner       = "cloud-foundations"

  # Two pipeline stages share the non-prod account, so the stage keeps their
  # resource names apart.
  attributes = ["test"]

  tags = {
    managed-by = "terraform"
  }
}

provider "aws" {
  region              = "us-west-2"
  allowed_account_ids = ["123456789012"]

  # Catches anything this configuration creates outside the module; the module
  # tags its own resources from the same label.
  default_tags {
    tags = module.label.tags
  }
}

module "example" {
  source = "../.."

  service_name = "example"
  context      = module.label.context

  artifact_bucket  = "omron-build-artifacts"
  artifact_key     = "example/abc123.zip"
  artifact_version = "3sL4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY+MTRCxf3vjVBH40Nr8X8gdRQBpUMLUo"

  handler                  = "handler.lambdaHandler"
  runtime                  = "nodejs20.x"
  architectures            = ["arm64"]
  memory_size              = 256
  timeout                  = 10
  environment_variables    = { LOG_LEVEL = "info" }
  log_retention_days       = 30
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/example-permissions-boundary"
  extra_policy_json        = ""
  extra_tags               = {}

  reserved_concurrent_executions = -1
  kms_key_arn                    = ""
}
