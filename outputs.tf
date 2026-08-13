output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN of the function (unqualified)"
  value       = aws_lambda_function.this.arn
}

output "qualified_arn" {
  description = "ARN of the published version, for pinning an event source to an exact version instead of the alias"
  value       = aws_lambda_function.this.qualified_arn
}

output "live_alias_arn" {
  description = "ARN of the live alias: invoke THIS, it enables instant rollback"
  value       = aws_lambda_alias.live.arn
}

output "live_alias_invoke_arn" {
  description = "Invoke ARN of the live alias, for API Gateway and EventBridge targets"
  value       = aws_lambda_alias.live.invoke_arn
}

output "alias_name" {
  description = "Name of the alias consumers invoke, for aws lambda invoke --qualifier and rollback tooling"
  value       = aws_lambda_alias.live.name
}

output "published_version" {
  description = "The immutable version this deploy published"
  value       = aws_lambda_function.this.version
}

output "exec_role_name" {
  description = "Runtime role name, for attaching further policies"
  value       = aws_iam_role.exec.name
}

output "exec_role_arn" {
  description = "Runtime role ARN, for iam:PassRole conditions and trust policies"
  value       = aws_iam_role.exec.arn
}

output "log_group_name" {
  description = "Name of the log group this module owns, for metric filters and subscription filters"
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the log group this module owns, for alarms and cross-account log destinations"
  value       = aws_cloudwatch_log_group.this.arn
}

output "label_context" {
  description = "The context this module's label resolved to, for composing child labels that inherit the service's naming hierarchy. The leaf name is withheld: the label has a single name slot, so a child that inherited it would compose an id identical to this service's function. Child labels must set their own name, and it replaces this service's rather than nesting under it, so keep child names unique within the project/application hierarchy."
  value       = merge(module.label.context, { name = null })
}

output "tags" {
  description = "The tags applied to every resource here: the label's ohi:* set and Name, merged with extra_tags"
  value       = local.tags
}
