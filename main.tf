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

  # IAM roles created by the pipeline must be named "<prefix>-cicd-*": the
  # pipeline's permissions boundary only permits creating/managing/passing
  # roles under that path. So the execution role goes under -cicd-, even
  # though the function name itself does not need to.
  exec_role_name = "${var.name_prefix}-cicd-${var.service_name}-exec"
}

# The function. s3_object_version pins the exact zip the build produced:
# a deploy can never silently pick up a different artifact.
resource "aws_lambda_function" "this" {
  function_name = local.function_name
  handler       = var.handler
  runtime       = var.runtime
  memory_size   = var.memory_size
  timeout       = var.timeout
  role          = aws_iam_role.exec.arn

  kms_key_arn = var.kms_key_arn != "" ? var.kms_key_arn : null

  reserved_concurrent_executions = var.reserved_concurrent_executions

  s3_bucket         = var.artifact_bucket
  s3_key            = var.artifact_key
  s3_object_version = var.artifact_version

  # Every deploy publishes an immutable version; the alias below points
  # at it. Rollback = repoint the alias, near-instant.
  publish = true

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
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

# The stable address consumers invoke. Traffic follows this alias,
# which is what makes instant rollback possible.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}

# Runtime role: what the function may do while running. Named under -cicd-
# and carrying the pipeline permissions boundary, because the deploy role
# that creates it may only create boundary-bound cicd-* roles.
resource "aws_iam_role" "exec" {
  name                 = local.exec_role_name
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

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

# Runtime permissions as a single INLINE policy (not a managed-policy
# attachment): the deploy role is not allowed iam:AttachRolePolicy under the
# permissions boundary, only iam:PutRolePolicy. Starts with logs (the
# equivalent of AWSLambdaBasicExecutionRole, scoped to this function's log
# group); extra permissions are merged in from extra_policy_json so they stay
# explicit in the consumer's code. See ADR 002 in Omron-Deployment-Workflows.
data "aws_iam_policy_document" "exec" {
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  # Optional: additional runtime permissions, supplied as an IAM policy
  # document JSON (e.g. rendered from a dynamodb-table module output).
  source_policy_documents = var.extra_policy_json != "" ? [var.extra_policy_json] : []
}

resource "aws_iam_role_policy" "exec" {
  name   = "runtime"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.exec.json
}

# NOTE: when kms_key_arn is set, this group is created encrypted with that CMK
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags              = var.extra_tags
}
