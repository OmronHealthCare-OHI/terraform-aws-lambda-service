# lambda-service (Terraform module)

A Terraform module for a Lambda service the pipeline-friendly way: versioned
artifact pinning, alias-based instant rollback, a minimal runtime role, and a
log group with retention.

## Usage

```hcl
module "service" {
  source = "github.com/OmronHealthCare-OHI/terraform-aws-lambda-service?ref=0.1.0"

  service_name = "hello-service"
  name_prefix  = "myapp-euw1" # <env><region>-style prefix used in resource names

  # Required when the caller (e.g. a CI deploy role) may only create IAM roles
  # that carry a permissions boundary. Leave unset when applying without one.
  permissions_boundary_arn = var.permissions_boundary_arn

  # The exact build artifact to deploy (produced by your build/CI):
  artifact_bucket  = var.artifact_bucket
  artifact_key     = var.artifact_key
  artifact_version = var.artifact_version
}
```

Pin an exact `?ref=` tag. Never reference `main`. Full input list in
[`examples/complete`](examples/complete/main.tf).

## What you get

- A `{name_prefix}-{service_name}` Lambda that publishes an immutable version
  per deploy.
- A `live` alias pointing at that version — invoke the alias, never the
  function directly. Rollback = repoint the alias (near-instant).
- A runtime role (`{name_prefix}-cicd-{service_name}-exec`, carrying the
  permissions boundary when provided) that can only write logs by default.
  Extra permissions are added via an **inline** policy from `extra_policy_json`
  — managed-policy attachment is deliberately not used, so the module works
  under permission boundaries that forbid `iam:AttachRolePolicy`.
- A CloudWatch log group with configurable retention (default 30 days).

## Inputs & outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). The three
`artifact_*` inputs come from whatever builds and uploads your Lambda zip;
tags (`team`, `service`, `stage`) come from the caller's provider
`default_tags`.

## Conventions

- Required inputs: `service_name`, `name_prefix`.
- Resource names: `{name_prefix}-{service_name}[-suffix]`.
- Breaking changes only in a new major version — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Ownership

Cloud Foundations. Changes via PR.
