# AWS CodeBuild

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.72.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.72.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_codebuild_project.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project) | resource |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume_role_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_build_timeout"></a> [build\_timeout](#input\_build\_timeout) | Number of minutes, from 5 to 480 (8 hours), for AWS CodeBuild to wait until timing out any related build that does not get marked as completed. The default is 10 minutes | `number` | `10` | no |
| <a name="input_buildspec_path"></a> [buildspec\_path](#input\_buildspec\_path) | Path to for the Buildspec file | `string` | n/a | yes |
| <a name="input_create_iam_role"></a> [create\_iam\_role](#input\_create\_iam\_role) | Set this variable to true if you want to create a role for AWS DevOps Tools | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | Short description of the project | `string` | `null` | no |
| <a name="input_ecr_repository"></a> [ecr\_repository](#input\_ecr\_repository) | The ECR repositories to which grant IAM access | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | CodeBuild environment configuration details. At least one attribute is required since `environment` is a required by CodeBuild | `any` | <pre>{<br/>  "image": "aws/codebuild/standard:4.0"<br/>}</pre> | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | The name for the Role | `string` | n/a | yes |
| <a name="input_iam_role_use_name_prefix"></a> [iam\_role\_use\_name\_prefix](#input\_iam\_role\_use\_name\_prefix) | Determines whether the IAM role name (`iam_role_name`) is used as a prefix | `bool` | `true` | no |
| <a name="input_logs_config"></a> [logs\_config](#input\_logs\_config) | CodeBuild logs configuration details | `any` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | CodeBuild Project name | `string` | n/a | yes |
| <a name="input_s3_bucket"></a> [s3\_bucket](#input\_s3\_bucket) | S3 bucket used for the artifact store | <pre>object({<br/>    s3_bucket_id  = string<br/>    s3_bucket_arn = string<br/>  })</pre> | n/a | yes |
| <a name="input_service_role"></a> [service\_role](#input\_service\_role) | Amazon Resource Name (ARN) of the AWS Identity and Access Management (IAM) role that enables AWS CodeBuild to interact with dependent AWS services on behalf of the AWS account | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_codebuild_role_arn"></a> [codebuild\_role\_arn](#output\_codebuild\_role\_arn) | The ARN of the IAM role |
| <a name="output_codebuild_role_name"></a> [codebuild\_role\_name](#output\_codebuild\_role\_name) | The name of the IAM role |
| <a name="output_project_arn"></a> [project\_arn](#output\_project\_arn) | The ARN of the CodeBuild project |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The ID of the CodeBuild project |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
