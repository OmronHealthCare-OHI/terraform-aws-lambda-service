variable "service_name" {
  type        = string
  description = "Service name, used as the label's leaf name and in the execution role name"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.service_name))
    error_message = "service_name may only contain letters, digits, hyphens and underscores — the characters Lambda and IAM accept in a name."
  }
}

# Naming and tags come from the shared label module. Its context object is
# reproduced here verbatim so callers can pass `context = module.label.context`
# and the module inherits country/stage/region and the ohi:* hierarchy. The
# lengths that IAM and Lambda cap are checked on the composed names, not here:
# they are only known after the label resolves. See the preconditions in main.tf.
variable "context" {
  description = "Label context from the caller's terraform-null-label instance. Supplies the <country><stage>-<region> prefix, the ohi:* tag hierarchy and any attributes. The prefix is required: this module refuses to name resources without one."
  type = object({
    enabled              = optional(bool, true)
    country              = optional(string, null)
    stage                = optional(string, null)
    aws_region           = optional(string, null)
    deployment_region    = optional(string, null)
    project              = optional(string, null)
    application          = optional(string, null)
    module               = optional(string, null)
    stack_suffix         = optional(string, null)
    stack_name_enabled   = optional(bool, true)
    owner                = optional(string, null)
    name                 = optional(string, null)
    attributes           = optional(list(string), [])
    non_prd              = optional(bool, false)
    delimiter            = optional(string, "-")
    prefix_enabled       = optional(bool, true)
    tag_prefix           = optional(string, "ohi")
    tag_delimiter        = optional(string, ":")
    id_length_limit      = optional(number, null)
    max_tag_key_length   = optional(number, null)
    max_tag_value_length = optional(number, null)
    tags                 = optional(map(string), {})
  })
  default = {}
}

variable "artifact_bucket" {
  type        = string
  description = "S3 bucket holding the Lambda zip"

  validation {
    condition     = length(trimspace(var.artifact_bucket)) > 0
    error_message = "artifact_bucket must be non-empty."
  }
}

variable "artifact_key" {
  type        = string
  description = "S3 key of the Lambda zip"

  validation {
    condition     = length(trimspace(var.artifact_key)) > 0
    error_message = "artifact_key must be non-empty."
  }
}

variable "artifact_version" {
  type        = string
  description = "S3 object version: pins the exact zip that was built"

  validation {
    condition     = length(trimspace(var.artifact_version)) > 0
    error_message = "artifact_version must be a non-empty S3 object version ID"
  }
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

variable "architectures" {
  type        = list(string)
  description = "Instruction set for the function. arm64 (Graviton) is cheaper per GB-second; use x86_64 if a dependency has no arm64 build."
  default     = ["x86_64"]

  validation {
    condition     = length(var.architectures) == 1 && alltrue([for a in var.architectures : contains(["x86_64", "arm64"], a)])
    error_message = "architectures must be exactly one of [\"x86_64\"] or [\"arm64\"]. Lambda accepts a single architecture per function."
  }
}

variable "memory_size" {
  type        = number
  description = "Memory in MB. Capped by the module as a cost guardrail; raise the cap in the module deliberately if a service genuinely needs more."
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 2048
    error_message = "memory_size must be between 128 and 2048 MB (module cost guardrail)."
  }
}

variable "timeout" {
  type        = number
  description = "Timeout in seconds. Capped by the module so a runaway invocation cannot run, and bill, for the full 15 minutes."
  default     = 10

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 300
    error_message = "timeout must be between 1 and 300 seconds (module guardrail)."
  }
}

variable "reserved_concurrent_executions" {
  type        = number
  description = "Ceiling on the function's concurrent executions (the Lambda autoscaling limit). -1 leaves it unreserved. The module caps how much a single service may reserve from the shared account pool."
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions == -1 || (var.reserved_concurrent_executions >= 1 && var.reserved_concurrent_executions <= 100)
    error_message = "reserved_concurrent_executions must be -1 (unreserved) or between 1 and 100 (module autoscaling guardrail). 0 is rejected because it hard-throttles the function."
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Environment variables for the function"
  default     = {}
}

variable "log_retention_days" {
  type        = number
  description = "How long CloudWatch keeps the logs. Must be a value CloudWatch Logs accepts."
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be one of the values CloudWatch Logs accepts (e.g. 1, 7, 14, 30, 90, 365, 731)."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Optional customer-managed key ARN for the log group and, when environment_variables is set, the function's env vars. Empty uses AWS-managed keys. The key is provided by the platform, not created here, and its key policy must grant the CloudWatch Logs service principal access — see the README."
  default     = ""

  validation {
    condition     = var.kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN like arn:aws:kms:<region>:<account>:key/<key-id>. Alias ARNs and bare key IDs are rejected: IAM does not resolve them, so the execution role's kms:Decrypt grant would not apply."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Pipeline permissions boundary. Required on the execution role: the deploy role that creates it may only create boundary-bound cicd-* roles. Leave empty only when applying outside the pipeline."
  default     = ""

  # This input decides whether the role is bounded at all, so a typo must not
  # pass silently as "unbounded". The account field also accepts "aws" so an
  # AWS-managed policy can be used as the boundary.
  validation {
    condition     = var.permissions_boundary_arn == "" || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN like arn:aws:iam::<account>:policy/<name>. Role ARNs, truncated ARNs and bare policy names are rejected: the role would be created unbounded."
  }
}

variable "extra_policy_json" {
  type        = string
  description = "Optional additional runtime permissions as an IAM policy document JSON (merged into the role's inline policy). Use instead of attaching managed policies, which the permissions boundary forbids. Example: data.aws_iam_policy_document.dynamo.json. Statements are merged by sid, so avoid the module's own: LambdaServiceLogs and LambdaServiceDecryptEnvVars."
  default     = ""
}

variable "extra_tags" {
  type        = map(string)
  description = "Additional tags merged on top of the label's generated ohi:* and Name tags. Passed through the label module, so its AWS tag constraints (50 tags, key/value length and character rules) apply."
  default     = {}
}
