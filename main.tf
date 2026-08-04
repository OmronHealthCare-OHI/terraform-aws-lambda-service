terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  function_name = "${var.name_prefix}-${var.service_name}"

  # The boundary only lets the pipeline create roles named "<prefix>-cicd-*".
  exec_role_name = "${var.name_prefix}-cicd-${var.service_name}-exec"

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

  tags = var.extra_tags

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.exec,
  ]
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

  tags = var.extra_tags
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
  tags         = var.extra_tags
}
