mock_provider "aws" {}

variables {
  service_name = "hello-service"

  # A non-prod US context: prefix usnp-usw2, hierarchy vlt-platform. non_prd
  # collapses the stage out of the prefix, so the context must carry an attribute
  # to keep this deployment apart from the other stages in the same account.
  context = {
    country     = "us"
    aws_region  = "us-west-2"
    non_prd     = true
    project     = "vlt"
    application = "platform"
    attributes  = ["test"]
  }

  artifact_bucket  = "usnp-usw2-cicd-artifacts"
  artifact_key     = "hello-service/abc123.zip"
  artifact_version = "test-version-1"
}

run "names_follow_convention" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "usnp-usw2-vlt-platform-hello-service-test"
    error_message = "Function name should be the label id: <prefix>-<project>-<application>-<service_name>-<attributes>"
  }

  assert {
    condition     = aws_iam_role.exec.name == "usnp-usw2-cicd-vlt-platform-hello-service-test-exec"
    error_message = "Exec role must be named <prefix>-cicd-<project>-<application>-<service_name>-exec: cicd follows the prefix so the deploy role is allowed to create it under the boundary, and the hierarchy follows cicd so two services with one service_name do not share a role"
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/usnp-usw2-vlt-platform-hello-service-test"
    error_message = "Log group should be /aws/lambda/<function_name>"
  }

  assert {
    condition     = aws_lambda_alias.live.name == "live"
    error_message = "The rollback alias must be named 'live'"
  }
}

run "attributes_reach_both_the_id_and_the_exec_role" {
  command = plan

  # Two pipeline stages share the non-prod account, so the stage attribute is
  # the only thing keeping their resource names apart. A different attribute to
  # the default context's, so the assertions below prove the value is carried
  # through rather than matching a constant.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "vlt"
      application = "platform"
      attributes  = ["acceptance"]
    }
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "usnp-usw2-vlt-platform-hello-service-acceptance"
    error_message = "Attributes from the context must be appended to the function name"
  }

  assert {
    condition     = aws_iam_role.exec.name == "usnp-usw2-cicd-vlt-platform-hello-service-acceptance-exec"
    error_message = "Attributes must reach the exec role name too, or two stages in one account collide on it"
  }
}

run "hierarchy_keeps_one_service_name_from_sharing_a_role" {
  command = plan

  # Same service_name as the default context, different hierarchy. Without the
  # hierarchy in the role name both would resolve to usnp-usw2-cicd-hello-service-exec
  # while their function names differed, and the second apply would take over the
  # role and overwrite its inline "runtime" policy.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "common"
      application = "iam"
      attributes  = ["test"]
    }
  }

  assert {
    condition     = aws_iam_role.exec.name == "usnp-usw2-cicd-common-iam-hello-service-test-exec"
    error_message = "The context hierarchy must reach the exec role name, or two services sharing a service_name collide on one role"
  }
}

run "tags_come_from_the_label" {
  command = plan

  variables {
    extra_tags = { managed-by = "terraform" }
  }

  assert {
    condition     = aws_lambda_function.this.tags["ohi:project"] == "vlt"
    error_message = "The ohi:* tags must come from the label, not from the caller's provider default_tags"
  }

  assert {
    condition     = aws_lambda_function.this.tags["ohi:application"] == "vlt-platform"
    error_message = "The label's composed hierarchy must reach the resources"
  }

  assert {
    condition     = aws_lambda_function.this.tags["Name"] == "usnp-usw2-vlt-platform-hello-service-test"
    error_message = "The Name tag must carry the generated id"
  }

  assert {
    condition     = aws_lambda_function.this.tags["managed-by"] == "terraform"
    error_message = "extra_tags must be merged on top of the generated tags"
  }

  assert {
    condition     = aws_iam_role.exec.tags["ohi:project"] == "vlt" && aws_cloudwatch_log_group.this.tags["ohi:project"] == "vlt"
    error_message = "Every resource this module owns must carry the label's tags"
  }
}

run "rejects_a_disabled_label" {
  command = plan

  # The label can be switched off; this module cannot follow it, so it must say
  # so rather than create resources with empty names.
  variables {
    context = {
      enabled     = false
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "vlt"
      application = "platform"
      attributes  = ["test"]
    }
  }

  # The role and the log group carry the same checks as the function, so none of
  # them can be applied on its own with -target. The function itself is never
  # reached: it depends on both, and Terraform skips a resource whose
  # dependencies failed.
  expect_failures = [
    aws_iam_role.exec,
    aws_cloudwatch_log_group.this,
  ]
}

# --- Stages sharing an account must not resolve to the same names ---

run "rejects_a_non_prd_context_without_attributes" {
  command = plan

  # non_prd collapses dev/test/acceptance into the single usnp segment, so every
  # non-prod stage in this account would name its function, role and log group
  # identically and the second to apply would take the first one over.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      stage       = "dev"
      project     = "vlt"
      application = "platform"
    }
  }

  expect_failures = [var.context]
}

run "rejects_a_context_with_neither_a_stage_nor_attributes" {
  command = plan

  # The other way to erase the stage: non_prd is off, but stage is unset, so the
  # prefix is just <country>-<region> and carries no stage either.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      project     = "vlt"
      application = "platform"
    }
  }

  expect_failures = [var.context]
}

run "accepts_a_staged_context_without_attributes" {
  command = plan

  # A real stage in the prefix distinguishes the deployment on its own, so
  # attributes are not required here.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = false
      stage       = "prd"
      project     = "vlt"
      application = "platform"
    }
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "usprd-usw2-vlt-platform-hello-service"
    error_message = "A context with a stage and no attributes must be accepted, with the stage carried in the prefix"
  }
}

run "rejects_a_context_that_keeps_the_prefix_out_of_the_id" {
  command = plan

  # prefix_enabled = false drops the prefix from the id but not from the label's
  # prefix output, so a check on the prefix alone would pass while the function
  # and log group names carried no environment or region. The exec role is
  # unaffected, because this module composes its name from the prefix directly:
  # the log group is what reports, and the function is skipped because it depends
  # on the group.
  variables {
    context = {
      country        = "us"
      aws_region     = "us-west-2"
      non_prd        = true
      project        = "vlt"
      application    = "platform"
      attributes     = ["test"]
      prefix_enabled = false
    }
  }

  expect_failures = [aws_cloudwatch_log_group.this]
}

run "rejects_a_context_without_a_prefix" {
  command = plan

  # No country or region: names would carry no environment, and both stages
  # would resolve to the same function. The attribute is only here to satisfy the
  # stage-distinctness validation, so the prefix precondition is what reports.
  variables {
    context = {
      project    = "vlt"
      attributes = ["test"]
    }
  }

  # The role and the log group carry the same checks as the function, so none of
  # them can be applied on its own with -target. The function itself is never
  # reached: it depends on both, and Terraform skips a resource whose
  # dependencies failed.
  expect_failures = [
    aws_iam_role.exec,
    aws_cloudwatch_log_group.this,
  ]
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

# --- Log history must outlive the configuration ---

run "log_group_is_kept_when_the_configuration_goes_away" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.skip_destroy == true
    error_message = "The log group must keep skip_destroy = true: a rename or destroy would otherwise delete the log history, and the role has no logs:CreateLogGroup to recreate the group"
  }
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

# --- Naming: the composed names must fit what IAM and Lambda accept ---

run "rejects_an_exec_role_name_over_the_iam_limit" {
  command = plan

  # No hierarchy segments, so only the role name (which adds "cicd-" and
  # "-exec") crosses 64 characters — the function name stays legal.
  variables {
    service_name = "document-ingestion-processor-with-a-very-long-name"
    context = {
      country    = "us"
      aws_region = "us-west-2"
      non_prd    = true
      attributes = ["test"]
    }
  }

  expect_failures = [aws_iam_role.exec]
}

run "rejects_a_long_hierarchy_that_pushes_the_names_over_the_limit" {
  command = plan

  # The hierarchy now reaches the role name too, so a long project/application
  # pair counts against IAM's cap. The role reports it rather than the function:
  # the role name is the function name plus "cicd-" and "-exec", so it always
  # crosses 64 first, and the function takes the role's ARN so its own length
  # precondition is never evaluated. That check stays as defence in depth.
  variables {
    service_name = "document-ingestion-processor-batch-runner"
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "voltron"
      application = "platform-services"
      attributes  = ["test"]
    }
  }

  expect_failures = [aws_iam_role.exec]
}

run "rejects_a_delimiter_aws_will_not_accept_in_a_name" {
  command = plan

  # The delimiter reaches the prefix, so the role name is the first to break.
  # The function name is equally illegal, but it is never evaluated: the
  # function takes the role's ARN, so the role's precondition fails first.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "vlt"
      application = "platform"
      attributes  = ["test"]
      delimiter   = "/"
    }
  }

  expect_failures = [aws_iam_role.exec]
}

run "rejects_hierarchy_characters_aws_will_not_accept_in_a_name" {
  command = plan

  # The hierarchy reaches both names, and the role is evaluated first because the
  # function takes its ARN, so the role's character check is what reports it.
  variables {
    context = {
      country     = "us"
      aws_region  = "us-west-2"
      non_prd     = true
      project     = "vlt.core"
      application = "platform"
      attributes  = ["test"]
    }
  }

  expect_failures = [aws_iam_role.exec]
}

run "rejects_invalid_characters_in_service_name" {
  command = plan

  variables {
    service_name = "hello.service"
  }

  expect_failures = [var.service_name]
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
