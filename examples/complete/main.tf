# Complete example: every input shown, with realistic values.
provider "aws" {
  region              = "us-west-2"
  allowed_account_ids = ["123456789012"]

  default_tags {
    tags = {
      team    = "example"
      service = "example"
      stage   = "test"
    }
  }
}

module "example" {
  source = "../.."

  service_name = "example"
  name_prefix  = "myapp-euw1"

  artifact_bucket  = "omron-build-artifacts"
  artifact_key     = "example/abc123.zip"
  artifact_version = "3sL4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY+MTRCxf3vjVBH40Nr8X8gdRQBpUMLUo"

  handler                  = "handler.lambdaHandler"
  runtime                  = "nodejs20.x"
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
