# lambda-service (Terraform module)

Ships a Lambda the way our pipeline expects it: the exact artifact your build
produced, an alias you can repoint to roll back, a role that starts out able to
write logs and nothing else, and a log group that does not keep logs forever.

## Usage

```hcl
# Naming and tags come from the shared label module. You state where you deploy
# once, and pass the resolved context down.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=0.1.1"

  country     = "us"
  aws_region  = "us-west-2"
  non_prd     = true # -> prefix usnp-usw2
  project     = "vlt"
  application = "platform"
  attributes  = [var.stage] # stages sharing an account must not collide
}

module "service" {
  source = "github.com/OmronHealthCare-OHI/terraform-aws-lambda-service?ref=0.1.0"

  service_name = "hello-service"
  context      = module.label.context

  # Required when the deploy role may only create boundary-bound roles.
  permissions_boundary_arn = var.permissions_boundary_arn

  # The exact artifact to deploy, from your build.
  artifact_bucket  = var.artifact_bucket
  artifact_key     = var.artifact_key
  artifact_version = var.artifact_version
}
```

Pin an exact `?ref=` tag on both. Never reference `main`. Full input list in
[`examples/complete`](examples/complete/main.tf).

Both module repos are public, so `terraform init` fetches them with no
credentials.

## What you get

- A Lambda named with the label's `id`
  (`{prefix}-{project}-{application}-{service_name}-{attributes}`, e.g.
  `usnp-usw2-vlt-platform-hello-service-test`) that publishes an immutable
  version per deploy.
- A `live` alias pointing at that version. Invoke the alias, never the function
  directly: rolling back is then just repointing the alias.
- A runtime role
  (`{prefix}-cicd-{project}-{application}-{service_name}-{attributes}-exec`, e.g.
  `usnp-usw2-cicd-vlt-platform-hello-service-test-exec`, carrying the permissions
  boundary when provided) that can write logs and nothing else. `cicd` follows the
  prefix directly because the boundary only permits the pipeline to create roles
  matching `{prefix}-cicd-*`; the hierarchy follows `cicd` rather than preceding
  it, so two services sharing a `service_name` under different
  `project`/`application` values do not end up sharing one role. The role name is
  therefore the function name plus `cicd-` and `-exec`, which makes it the first
  of the two to reach the 64-character limit. Add permissions via
  `extra_policy_json`; it becomes an **inline** policy, because boundaries here
  forbid `iam:AttachRolePolicy`. Statements merge by `sid`, so avoid
  `LambdaServiceLogs` and `LambdaServiceDecryptEnvVars`.
- A CloudWatch log group with configurable retention (default 30 days).
- The label's `ohi:*` tags and `Name` on all three, plus anything in
  `extra_tags`.

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

## Lifecycle

The log group is created with `skip_destroy`, so **Terraform never deletes it**.
Renaming the service, running `terraform destroy`, or removing the module all
leave the group and its history behind in AWS. That is deliberate: the role has
no `logs:CreateLogGroup`, so a deleted group means logging stops silently. The
trade-off is that the group can outlive the configuration that made it.

### Renaming a service

`service_name` and everything the label composes into the name — the prefix, the
`project`/`application` hierarchy, the attributes — feed the function, role and
log group names, so changing any of them replaces all three. The old log group is
left behind unmanaged. Remove it by hand once you no longer need its history.

### When the log group already exists

Any apply that would create `/aws/lambda/<function>` while it already exists
fails with `ResourceAlreadyExistsException`. Three ways to get there:

1. The function ran before this module managed it, so Lambda created the group.
2. A previous `terraform destroy` left the group behind.
3. You renamed the service and are now renaming it back.

In cases 1 and 2 nothing occupies `aws_cloudwatch_log_group.this` in state, so
import the existing group and keep its history:

```sh
terraform import \
  'module.service.aws_cloudwatch_log_group.this' \
  '/aws/lambda/usnp-usw2-vlt-platform-hello-service'
```

Case 3 is different: that address already holds the *current* group, so an import
would need a `terraform state rm` first — which just orphans another group.
Deleting the old one is simpler, at the cost of its history:

```sh
aws logs delete-log-group \
  --log-group-name '/aws/lambda/usnp-usw2-vlt-platform-hello-service'
```

## Inputs & outputs

The three `artifact_*` inputs come from whatever builds and uploads your Lambda
zip. Tags come from `context`, not from the caller's provider `default_tags`:
the module re-labels every resource it owns, so the generated `ohi:*` set is
applied even where a `default_tags` block is missing.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

### Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.58.0 |

### Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_label"></a> [label](#module\_label) | github.com/OmronHealthCare-OHI/terraform-null-label | 0.1.1 |

### Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_alias.live](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_alias) | resource |
| [aws_lambda_function.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_iam_policy_document.exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_architectures"></a> [architectures](#input\_architectures) | Instruction set for the function. arm64 (Graviton) is cheaper per GB-second; use x86\_64 if a dependency has no arm64 build. | `list(string)` | <pre>[<br/>  "x86_64"<br/>]</pre> | no |
| <a name="input_artifact_bucket"></a> [artifact\_bucket](#input\_artifact\_bucket) | S3 bucket holding the Lambda zip | `string` | n/a | yes |
| <a name="input_artifact_key"></a> [artifact\_key](#input\_artifact\_key) | S3 key of the Lambda zip | `string` | n/a | yes |
| <a name="input_artifact_version"></a> [artifact\_version](#input\_artifact\_version) | S3 object version: pins the exact zip that was built | `string` | n/a | yes |
| <a name="input_context"></a> [context](#input\_context) | Label context from the caller's terraform-null-label instance. Supplies the <country><stage>-<region> prefix, the ohi:* tag hierarchy and any attributes. The prefix is required: this module refuses to name resources without one. | <pre>object({<br/>    enabled              = optional(bool, true)<br/>    country              = optional(string, null)<br/>    stage                = optional(string, null)<br/>    aws_region           = optional(string, null)<br/>    deployment_region    = optional(string, null)<br/>    project              = optional(string, null)<br/>    application          = optional(string, null)<br/>    module               = optional(string, null)<br/>    stack_suffix         = optional(string, null)<br/>    stack_name_enabled   = optional(bool, true)<br/>    owner                = optional(string, null)<br/>    name                 = optional(string, null)<br/>    attributes           = optional(list(string), [])<br/>    non_prd              = optional(bool, false)<br/>    delimiter            = optional(string, "-")<br/>    prefix_enabled       = optional(bool, true)<br/>    tag_prefix           = optional(string, "ohi")<br/>    tag_delimiter        = optional(string, ":")<br/>    id_length_limit      = optional(number, null)<br/>    max_tag_key_length   = optional(number, null)<br/>    max_tag_value_length = optional(number, null)<br/>    tags                 = optional(map(string), {})<br/>  })</pre> | n/a | yes |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Environment variables for the function | `map(string)` | `{}` | no |
| <a name="input_extra_policy_json"></a> [extra\_policy\_json](#input\_extra\_policy\_json) | Optional additional runtime permissions as an IAM policy document JSON (merged into the role's inline policy). Use instead of attaching managed policies, which the permissions boundary forbids. Example: data.aws\_iam\_policy\_document.dynamo.json. Statements are merged by sid, so avoid the module's own: LambdaServiceLogs and LambdaServiceDecryptEnvVars. | `string` | `""` | no |
| <a name="input_extra_tags"></a> [extra\_tags](#input\_extra\_tags) | Additional tags merged on top of the label's generated ohi:* and Name tags. Passed through the label module, so its AWS tag constraints (50 tags, key/value length and character rules) apply. | `map(string)` | `{}` | no |
| <a name="input_handler"></a> [handler](#input\_handler) | Function entry point, e.g. handler.lambdaHandler | `string` | `"handler.lambdaHandler"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Optional customer-managed key ARN for the log group and, when environment\_variables is set, the function's env vars. Empty uses AWS-managed keys. The key is provided by the platform, not created here, and its key policy must grant the CloudWatch Logs service principal access — see the README. | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | How long CloudWatch keeps the logs. Must be a value CloudWatch Logs accepts. | `number` | `30` | no |
| <a name="input_memory_size"></a> [memory\_size](#input\_memory\_size) | Memory in MB. Capped by the module as a cost guardrail; raise the cap in the module deliberately if a service genuinely needs more. | `number` | `256` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | Pipeline permissions boundary. Required on the execution role: the deploy role that creates it may only create boundary-bound cicd-* roles. Leave empty only when applying outside the pipeline. | `string` | `""` | no |
| <a name="input_reserved_concurrent_executions"></a> [reserved\_concurrent\_executions](#input\_reserved\_concurrent\_executions) | Ceiling on the function's concurrent executions (the Lambda autoscaling limit). -1 leaves it unreserved. The module caps how much a single service may reserve from the shared account pool. | `number` | `-1` | no |
| <a name="input_runtime"></a> [runtime](#input\_runtime) | Lambda runtime | `string` | `"nodejs20.x"` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Service name, used as the label's leaf name and in the execution role name | `string` | n/a | yes |
| <a name="input_timeout"></a> [timeout](#input\_timeout) | Timeout in seconds. Capped by the module so a runaway invocation cannot run, and bill, for the full 15 minutes. | `number` | `10` | no |

### Outputs

| Name | Description |
|------|-------------|
| <a name="output_alias_name"></a> [alias\_name](#output\_alias\_name) | Name of the alias consumers invoke, for aws lambda invoke --qualifier and rollback tooling |
| <a name="output_exec_role_arn"></a> [exec\_role\_arn](#output\_exec\_role\_arn) | Runtime role ARN, for iam:PassRole conditions and trust policies |
| <a name="output_exec_role_name"></a> [exec\_role\_name](#output\_exec\_role\_name) | Runtime role name, for attaching further policies |
| <a name="output_function_arn"></a> [function\_arn](#output\_function\_arn) | ARN of the function (unqualified) |
| <a name="output_function_name"></a> [function\_name](#output\_function\_name) | Name of the Lambda function |
| <a name="output_label_context"></a> [label\_context](#output\_label\_context) | The context this module's label resolved to, for composing child labels that inherit the service's naming hierarchy |
| <a name="output_live_alias_arn"></a> [live\_alias\_arn](#output\_live\_alias\_arn) | ARN of the live alias: invoke THIS, it enables instant rollback |
| <a name="output_live_alias_invoke_arn"></a> [live\_alias\_invoke\_arn](#output\_live\_alias\_invoke\_arn) | Invoke ARN of the live alias, for API Gateway and EventBridge targets |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | ARN of the log group this module owns, for alarms and cross-account log destinations |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | Name of the log group this module owns, for metric filters and subscription filters |
| <a name="output_published_version"></a> [published\_version](#output\_published\_version) | The immutable version this deploy published |
| <a name="output_qualified_arn"></a> [qualified\_arn](#output\_qualified\_arn) | ARN of the published version, for pinning an event source to an exact version instead of the alias |
| <a name="output_tags"></a> [tags](#output\_tags) | The tags applied to every resource here: the label's ohi:* set and Name, merged with extra\_tags |
<!-- END_TF_DOCS -->

## Conventions

- Required inputs: `service_name`, and a `context` that resolves to a prefix.
- Naming and tags are owned by
  [terraform-null-label](https://github.com/OmronHealthCare-OHI/terraform-null-label),
  which is the source of truth for the `<country><stage>-<region>` prefix and
  the `ohi:*` tag set. This module composes nothing of its own beyond the
  `-cicd-…-exec` role name the permissions boundary requires.
- The composed names are checked at plan time: the function must fit Lambda's
  64-character limit, the role IAM's, and both may only hold letters, digits,
  hyphens and underscores.
- Breaking changes only in a new major version. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Ownership

Cloud Foundations. Changes via PR.
