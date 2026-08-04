# lambda-service (Terraform module)

Ships a Lambda the way our pipeline expects it: the exact artifact your build
produced, an alias you can repoint to roll back, a role that starts out able to
write logs and nothing else, and a log group that does not keep logs forever.

## Usage

```hcl
module "service" {
  source = "github.com/OmronHealthCare-OHI/terraform-aws-lambda-service?ref=0.1.0"

  service_name = "hello-service"
  name_prefix  = "myapp-euw1" # <env><region>-style prefix used in resource names

  # Required when the deploy role may only create boundary-bound roles.
  permissions_boundary_arn = var.permissions_boundary_arn

  # The exact artifact to deploy, from your build.
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
- A `live` alias pointing at that version. Invoke the alias, never the function
  directly: rolling back is then just repointing the alias.
- A runtime role (`{name_prefix}-cicd-{service_name}-exec`, carrying the
  permissions boundary when provided) that can write logs and nothing else.
  Add permissions via `extra_policy_json`; it becomes an **inline** policy,
  because boundaries here forbid `iam:AttachRolePolicy`. Statements merge by
  `sid`, so avoid `LambdaServiceLogs` and `LambdaServiceDecryptEnvVars`.
- A CloudWatch log group with configurable retention (default 30 days).

## Encryption

`kms_key_arn` is optional. Leaving it empty still encrypts at rest, with
AWS-managed keys. When set:

- Must be the **key ARN**, not an alias or bare key ID. IAM does not resolve
  those, so the role's `kms:Decrypt` grant would authorize nothing.
- The **key policy must grant `logs.<region>.amazonaws.com`** `kms:Encrypt*`,
  `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*` and `kms:Describe*`,
  or log-group creation fails with `AccessDeniedException`.
- The log group always uses it; the function only when `environment_variables`
  is set, and the role then gets `kms:Decrypt`.

## Inputs & outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). The three
`artifact_*` inputs come from whatever builds and uploads your Lambda zip;
tags (`team`, `service`, `stage`) come from the caller's provider
`default_tags`.

## Conventions

- Required inputs: `service_name`, `name_prefix`.
- Resource names: `{name_prefix}-{service_name}[-suffix]`.
- Letters, digits, hyphens and underscores only, **53 characters combined** at
  most, so the derived role name fits IAM's 64-character cap.
- Breaking changes only in a new major version. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Ownership

Cloud Foundations. Changes via PR.
