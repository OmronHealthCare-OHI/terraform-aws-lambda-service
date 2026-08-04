mock_provider "aws" {}

variables {
  service_name     = "hello-service"
  name_prefix      = "usnp-usw2"
  artifact_bucket  = "usnp-usw2-cicd-artifacts"
  artifact_key     = "hello-service/abc123.zip"
  artifact_version = "test-version-1"
}

run "names_follow_convention" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "usnp-usw2-hello-service"
    error_message = "Function name should be <name_prefix>-<service_name>"
  }

  assert {
    condition     = aws_iam_role.exec.name == "usnp-usw2-cicd-hello-service-exec"
    error_message = "Exec role must be named under -cicd- so the deploy role is allowed to create it"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/usnp-usw2-hello-service"
    error_message = "Log group should be /aws/lambda/<function_name>"
  }

  assert {
    condition     = aws_lambda_alias.live.name == "live"
    error_message = "The rollback alias must be named 'live'"
  }
}

run "artifact_is_pinned_by_version" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.s3_object_version == "test-version-1"
    error_message = "The function must pin the exact artifact version passed in"
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "publish must be true so each deploy makes an immutable version for rollback"
  }
}

run "runtime_permissions_are_inline_not_managed" {
  command = plan

  # See ADR 002 in the deployment-workflows repo.
  assert {
    condition     = aws_iam_role_policy.exec.name == "runtime"
    error_message = "Runtime permissions must be delivered as an inline role policy"
  }
}

run "no_boundary_when_unset" {
  command = plan

  assert {
    condition     = aws_iam_role.exec.permissions_boundary == null
    error_message = "The exec role must carry no boundary when none is supplied"
  }
}

run "boundary_applied_when_set" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/usnp-usw2-pipeline-permissions-boundary"
  }

  assert {
    condition     = aws_iam_role.exec.permissions_boundary == "arn:aws:iam::123456789012:policy/usnp-usw2-pipeline-permissions-boundary"
    error_message = "The exec role must carry the boundary when one is supplied"
  }
}

run "accepts_aws_managed_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
  }

  assert {
    condition     = aws_iam_role.exec.permissions_boundary == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "An AWS-managed policy must be usable as the boundary"
  }
}

run "rejects_boundary_that_is_not_a_policy_arn" {
  command = plan

  # A role ARN: plausible enough to paste by mistake, and silently unbounded
  # if it were accepted.
  variables {
    permissions_boundary_arn = "arn:aws:iam::123456789012:role/usnp-usw2-pipeline"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_bare_boundary_policy_name" {
  command = plan

  variables {
    permissions_boundary_arn = "usnp-usw2-pipeline-permissions-boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

# --- Guardrail caps: out-of-range values must be rejected ---

run "rejects_oversized_memory" {
  command = plan

  variables {
    memory_size = 4096
  }

  expect_failures = [var.memory_size]
}

run "rejects_excessive_timeout" {
  command = plan

  variables {
    timeout = 900
  }

  expect_failures = [var.timeout]
}

run "rejects_excessive_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = 500
  }

  expect_failures = [var.reserved_concurrent_executions]
}

run "rejects_zero_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = 0
  }

  expect_failures = [var.reserved_concurrent_executions]
}

run "defaults_to_x86_64" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["x86_64"])
    error_message = "Default architecture should be x86_64"
  }
}

run "accepts_arm64" {
  command = plan

  variables {
    architectures = ["arm64"]
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"])
    error_message = "arm64 must be selectable"
  }
}

run "rejects_multiple_architectures" {
  command = plan

  variables {
    architectures = ["x86_64", "arm64"]
  }

  expect_failures = [var.architectures]
}

run "rejects_unknown_architecture" {
  command = plan

  variables {
    architectures = ["i386"]
  }

  expect_failures = [var.architectures]
}

run "rejects_invalid_log_retention" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "kms_key_encrypts_function_and_logs_when_set" {
  command = plan

  variables {
    kms_key_arn           = "arn:aws:kms:us-west-2:123456789012:key/test-key-id"
    environment_variables = { LOG_LEVEL = "info" }
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:us-west-2:123456789012:key/test-key-id"
    error_message = "Function env vars must use the customer-managed KMS key when one is supplied"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/test-key-id"
    error_message = "Log group must use the customer-managed KMS key when one is supplied"
  }

  # NOTE: the role's kms:Decrypt grant cannot be asserted here. The policy JSON
  # depends on the log group ARN, which the mock provider leaves unknown at plan.
}

run "kms_key_skips_function_when_no_env_vars" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/test-key-id"
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == null
    error_message = "The function must not carry a KMS key when it has no environment variables"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/test-key-id"
    error_message = "The log group must still use the CMK even when the function has no env vars"
  }

}

run "rejects_kms_alias_arn" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:alias/platform-lambda"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_bare_kms_key_id" {
  command = plan

  variables {
    kms_key_arn = "1234abcd-12ab-34cd-56ef-1234567890ab"
  }

  expect_failures = [var.kms_key_arn]
}

# --- Naming: the exec role name must fit IAM's 64-character limit ---

run "rejects_names_too_long_for_the_exec_role" {
  command = plan

  variables {
    name_prefix  = "prodeuw1-platform-services"
    service_name = "document-ingestion-processor"
  }

  expect_failures = [var.service_name]
}

run "rejects_invalid_characters_in_service_name" {
  command = plan

  variables {
    service_name = "hello.service"
  }

  expect_failures = [var.service_name]
}

run "rejects_invalid_characters_in_name_prefix" {
  command = plan

  variables {
    name_prefix = "usnp usw2"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_empty_artifact_version" {
  command = plan

  variables {
    artifact_version = ""
  }

  expect_failures = [var.artifact_version]
}

run "rejects_empty_artifact_bucket" {
  command = plan

  variables {
    artifact_bucket = ""
  }

  expect_failures = [var.artifact_bucket]
}

run "rejects_empty_artifact_key" {
  command = plan

  variables {
    artifact_key = ""
  }

  expect_failures = [var.artifact_key]
}
