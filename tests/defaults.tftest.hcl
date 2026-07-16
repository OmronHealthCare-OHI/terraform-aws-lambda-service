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

  # The deploy role cannot attach managed policies under the permissions
  # boundary, only PutRolePolicy. The runtime permissions must therefore be an
  # inline role policy. See ADR 002 in the deployment-workflows repo.
  assert {
    condition     = aws_iam_role_policy.exec.name == "runtime"
    error_message = "Runtime permissions must be delivered as an inline role policy"
  }
}

run "no_boundary_when_unset" {
  command = plan

  # permissions_boundary_arn defaults to "", so the attribute must be null.
  assert {
    condition     = aws_iam_role.exec.permissions_boundary == null
    error_message = "The exec role must carry no boundary when none is supplied"
  }
}

run "boundary_applied_when_set" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::689344065739:policy/usnp-usw2-pipeline-permissions-boundary"
  }

  assert {
    condition     = aws_iam_role.exec.permissions_boundary == "arn:aws:iam::689344065739:policy/usnp-usw2-pipeline-permissions-boundary"
    error_message = "The exec role must carry the boundary when one is supplied"
  }
}

# --- Guardrail caps: values outside the module's limits must be rejected ---

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
    kms_key_arn = "arn:aws:kms:us-west-2:689344065739:key/test-key-id"
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:us-west-2:689344065739:key/test-key-id"
    error_message = "Function env vars must use the customer-managed KMS key when one is supplied"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:689344065739:key/test-key-id"
    error_message = "Log group must use the customer-managed KMS key when one is supplied"
  }
}
