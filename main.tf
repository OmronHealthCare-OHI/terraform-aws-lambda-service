terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Naming and tags for every resource here. The caller passes its own label's
# context, so region, stage and the ohi:* hierarchy are inputs to the label, not
# strings assembled in this module.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  context = var.context
  name    = var.service_name
  tags    = var.extra_tags
}

locals {
  function_name = module.label.id

  # 1.0.0 has no `prefix` output: the id is composed straight from the label
  # order. This is the leading part of it, the segments that carry environment
  # and region, which the boundary conditions role names on.
  # Joined with the context's delimiter, not a hardcoded "-": the label composes
  # its id the same way, and the checks below compare the two.
  name_prefix = join(coalesce(var.context.delimiter, "-"), compact([module.label.namespace, module.label.region, module.label.stage]))

  # The boundary only lets the pipeline create roles named "<name_prefix>-cicd-*",
  # so cicd follows those segments directly and application follows cicd. Without
  # application, two services sharing a service_name under different hierarchies
  # would get distinct function names but one role, and the second stack would
  # overwrite the first one's inline policy. Attributes do the same one level
  # down, keeping two stages in one account apart.
  exec_role_name = join("-", compact(concat(
    [
      local.name_prefix,
      "cicd",
      module.label.name, # 1.0.0 folds <application>-<service_name>, normalised
    ],
    module.label.context.attributes,
    ["exec"],
  )))

  tags = module.label.tags

  # Letters, digits, hyphens and underscores: the intersection of what Lambda
  # and IAM accept. A label delimiter of "/" would otherwise reach AWS.
  name_charset = "^[a-zA-Z0-9_-]+$"

  # These label invariants are asserted on every resource that takes its name
  # from the label, because `terraform apply -target` can plan one of them
  # without the function: a check that lived only there would be skipped.
  # namespace is guaranteed by the label itself, and stage is covered by the
  # context validation in variables.tf. region is the one nothing else enforces.
  label_region_error   = "The label carries no region, so two regions would resolve to the same function, role and log group. Set region on the context you pass in."
  label_disabled_error = "The label produced an empty id, so there is no name to give this module's resources. Remove enabled = false from the context you pass in: this module cannot be switched off through the label."

  # Non-empty leading segments are not enough on their own: an id_length_limit
  # shorter than them truncates into the id. The exec role name would still
  # carry them, since this module composes that one itself, leaving the function
  # and its log group as the only unprefixed names.
  label_unprefixed_name_error = "The label's id \"${local.function_name}\" does not begin with \"${local.name_prefix}\", so the function and its log group would carry no region or stage and two stages would fight over one name. Keep id_length_limit (when set) longer than those leading segments."

  has_env_vars = length(var.environment_variables) > 0

  # Optional inputs use "" as the unset sentinel; normalise to null here.
  kms_key_arn              = var.kms_key_arn != "" ? var.kms_key_arn : null
  permissions_boundary_arn = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  extra_policy_documents   = var.extra_policy_json != "" ? [var.extra_policy_json] : []

  # On the function a CMK encrypts only env vars, so skip it when there are
  # none: the key would encrypt nothing and drift on every plan.
  function_kms_key_arn = local.has_env_vars ? local.kms_key_arn : null
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  handler       = var.handler
  runtime       = var.runtime
  architectures = var.architectures
  memory_size   = var.memory_size
  timeout       = var.timeout
  role          = aws_iam_role.exec.arn

  kms_key_arn = local.function_kms_key_arn

  reserved_concurrent_executions = var.reserved_concurrent_executions

  s3_bucket         = var.artifact_bucket
  s3_key            = var.artifact_key
  s3_object_version = var.artifact_version

  publish = true

  dynamic "environment" {
    for_each = local.has_env_vars ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  tags = local.tags

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.exec,
  ]

  lifecycle {
    # Without a prefix the name carries no environment or region, so two stages
    # would fight over one function. Checked here rather than on the input: it
    # is only known once the label has resolved.
    precondition {
      condition     = module.label.region != ""
      error_message = local.label_region_error
    }

    # A disabled label yields an empty id. This module has no matching disabled
    # mode, so it would go on to create resources with empty names.
    precondition {
      condition     = local.function_name != ""
      error_message = local.label_disabled_error
    }

    # Guarded on the empty id so a disabled label reports the check above rather
    # than both.
    precondition {
      condition     = local.function_name == "" || startswith(local.function_name, local.name_prefix)
      error_message = local.label_unprefixed_name_error
    }

    precondition {
      condition     = length(local.function_name) <= 64
      error_message = "The composed function name \"${local.function_name}\" is longer than Lambda's 64-character limit. Shorten service_name, or the project/application segments of the context."
    }

    precondition {
      condition     = can(regex(local.name_charset, local.function_name))
      error_message = "The composed function name \"${local.function_name}\" contains characters Lambda rejects. Names may only hold letters, digits, hyphens and underscores, so keep the label delimiter to \"-\" or \"_\"."
    }
  }
}

# The stable address consumers invoke. Repointing it is an instant rollback.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

resource "aws_iam_role" "exec" {
  name                 = local.exec_role_name
  permissions_boundary = local.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.tags

  lifecycle {
    # Without a prefix the composed name starts at "cicd-", which no boundary
    # statement matches, so the pipeline would be denied at apply time.
    precondition {
      condition     = module.label.region != ""
      error_message = local.label_region_error
    }

    precondition {
      condition     = local.function_name != ""
      error_message = local.label_disabled_error
    }

    # Replaces the old name_prefix + service_name <= 53 input validation: the
    # prefix now comes from the label, so the cap can only be checked here.
    precondition {
      condition     = length(local.exec_role_name) <= 64
      error_message = "The composed execution role name \"${local.exec_role_name}\" is longer than IAM's 64-character limit. It carries the same segments as the function name plus \"cicd-\" and \"-exec\", so it is the first name to run out of room: shorten service_name, or the project/application segments or attributes carried in the context."
    }

    precondition {
      condition     = can(regex(local.name_charset, local.exec_role_name))
      error_message = "The composed execution role name \"${local.exec_role_name}\" contains characters IAM rejects. Names may only hold letters, digits, hyphens and underscores, so keep the label delimiter to \"-\" or \"_\"."
    }
  }
}

# Inline, not a managed-policy attachment: the boundary forbids
# iam:AttachRolePolicy. See ADR 002 in Omron-Deployment-Workflows.
data "aws_iam_policy_document" "exec" {
  statement {
    sid    = "LambdaServiceLogs"
    effect = "Allow"
    # No logs:CreateLogGroup: the group is managed here, and granting it would
    # let Lambda silently recreate it without the CMK or retention.
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  # Lambda decrypts env vars with this role, not the service principal.
  # Without it every invocation fails.
  dynamic "statement" {
    for_each = local.function_kms_key_arn != null ? [1] : []
    content {
      sid       = "LambdaServiceDecryptEnvVars"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [local.function_kms_key_arn]
    }
  }

  source_policy_documents = local.extra_policy_documents
}

resource "aws_iam_role_policy" "exec" {
  name   = "runtime"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.exec.json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn

  # A rename would otherwise destroy the log history, and the role has no
  # logs:CreateLogGroup to recreate the group.
  skip_destroy = true
  tags         = local.tags

  lifecycle {
    # An empty id would leave the bare "/aws/lambda/" group, which no function
    # writes to and which the boundary's log-group pattern does not cover.
    precondition {
      condition     = module.label.region != ""
      error_message = local.label_region_error
    }

    precondition {
      condition     = local.function_name != ""
      error_message = local.label_disabled_error
    }

    precondition {
      condition     = local.function_name == "" || startswith(local.function_name, local.name_prefix)
      error_message = local.label_unprefixed_name_error
    }
  }
}
