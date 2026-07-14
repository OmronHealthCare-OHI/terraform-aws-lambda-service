# lambda-service

A Lambda function the OMRON way: versioned artifact pinning, alias-based
instant rollback, minimal runtime permissions, logs with retention.

## Usage

```hcl
module "service" {
  source = "github.com/OmronHealthCare-OHI/Omron-Terraform-Modules//modules/lambda-service?ref=v0.1.0"

  service_name = "hello-service"
  name_prefix  = "usnp-usw2"

  # Required so the pipeline deploy role is allowed to create this role.
  permissions_boundary_arn = var.permissions_boundary_arn

  # From the build workflow's outputs:
  artifact_bucket  = var.artifact_bucket
  artifact_key     = var.artifact_key
  artifact_version = var.artifact_version
}
```

See `examples/complete` for every input.

## What you get

- `{prefix}-{service}` Lambda, publishing an immutable version per deploy
- A `live` alias pointing at that version: invoke the alias, never the
  function directly. Rollback = repointing the alias (near-instant)
- A runtime role (named `{prefix}-cicd-{service}-exec`, carrying the pipeline
  permissions boundary) that can only write logs by default. Extra permissions
  are added via an **inline** policy from `extra_policy_json` — managed-policy
  attachment is intentionally not used, because the pipeline boundary forbids it
- A log group with 30-day retention (configurable)

## What you must provide

The three `artifact_*` inputs come from the `build-lambda` reusable
workflow in Omron-Deployment-Workflows. `permissions_boundary_arn` is the
pipeline boundary (see ADR 002) and is required whenever the module is applied
by the pipeline's deploy role. Tags (`team`, `service`, `stage`)
come from your provider `default_tags`, per the pipeline conventions.
