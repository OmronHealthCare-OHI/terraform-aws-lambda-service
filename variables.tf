variable "service_name" {
  type        = string
  description = "Service name, used in resource naming"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names, e.g. an <env><region> code like myapp-euw1"
}

# The exact build artifact to deploy, as produced by the build workflow.
variable "artifact_bucket" {
  type        = string
  description = "S3 bucket holding the Lambda zip"
}

variable "artifact_key" {
  type        = string
  description = "S3 key of the Lambda zip"
}

variable "artifact_version" {
  type        = string
  description = "S3 object version: pins the exact zip that was built"
}

variable "handler" {
  type        = string
  description = "Function entry point, e.g. handler.lambdaHandler"
  default     = "handler.lambdaHandler"
}

variable "runtime" {
  type        = string
  description = "Lambda runtime"
  default     = "nodejs20.x"
}

variable "memory_size" {
  type        = number
  description = "Memory in MB"
  default     = 256
}

variable "timeout" {
  type        = number
  description = "Timeout in seconds"
  default     = 10
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the function"
  default     = {}
}

variable "log_retention_days" {
  type        = number
  description = "How long CloudWatch keeps the logs"
  default     = 30
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Pipeline permissions boundary. Required on the execution role: the deploy role that creates it may only create boundary-bound cicd-* roles. Leave empty only when applying outside the pipeline."
  default     = ""
}

variable "extra_policy_json" {
  type        = string
  description = "Optional additional runtime permissions as an IAM policy document JSON (merged into the role's inline policy). Use instead of attaching managed policies, which the permissions boundary forbids. Example: data.aws_iam_policy_document.dynamo.json"
  default     = ""
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags beyond the provider default_tags"
  default     = {}
}
