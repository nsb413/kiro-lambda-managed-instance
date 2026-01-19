# ============================================================================
# Lambda Function Outputs
# ============================================================================
# These outputs provide information about the deployed Lambda function and
# are preserved from the original standard Lambda setup.

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.fibonacci.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.fibonacci.function_name
}

# ============================================================================
# Lambda Managed Instances Outputs
# ============================================================================
# These outputs provide information about the Lambda Managed Instances
# infrastructure components created for running Lambda functions on EC2 instances.
#
# Lambda Managed Instances Architecture:
# The capacity provider is the foundational resource that defines where and how
# Lambda runs your functions on EC2 instances. It includes:
# - VPC configuration (subnets, security groups)
# - Instance requirements (architecture, instance types)
# - Scaling policies (automatic scaling based on CPU utilization)
# - Permissions (operator role for EC2 management)
#
# The operator role grants Lambda service permissions to manage EC2 resources
# on your behalf, including launching instances, creating network interfaces,
# and tagging resources.
#
# Multi-Concurrency Implications:
# Lambda Managed Instances supports multi-concurrent execution, where one
# execution environment can handle multiple invocations simultaneously. This
# improves resource utilization and cost efficiency, especially for IO-heavy
# workloads. Your function code should be thread-safe if using shared state,
# though Python's default behavior (separate processes) handles this automatically.
#
# Monitoring and Verification:
# After deployment, verify the capacity provider is in ACTIVE state and check
# that EC2 instances are launched with the aws:lambda:capacity-provider tag.
# Monitor CloudWatch metrics for invocation counts, duration, and errors.
#
# References:
# - AWS Documentation: https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html
# - Monitoring Guide: https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-monitoring.html

output "capacity_provider_arn" {
  description = <<-EOT
    ARN of the Lambda Capacity Provider for Managed Instances.
    
    The capacity provider is the foundational resource that defines the compute
    infrastructure for Lambda Managed Instances. Use this ARN to:
    - Attach additional Lambda functions to the same capacity provider
    - Query capacity provider status and configuration
    - Monitor capacity provider metrics in CloudWatch
    
    The capacity provider manages EC2 instances in your account and handles
    automatic scaling based on CPU utilization. Instances are tagged with
    aws:lambda:capacity-provider for identification.
  EOT
  value       = aws_lambda_capacity_provider.main.arn
}

output "capacity_provider_name" {
  description = <<-EOT
    Name of the Lambda Capacity Provider for Managed Instances.
    
    Use this name to reference the capacity provider in AWS CLI commands:
    - aws lambda get-capacity-provider --name <name>
    - aws lambda list-functions --capacity-provider-name <name>
    
    The capacity provider name follows the pattern: <function-name>-capacity-provider
  EOT
  value       = aws_lambda_capacity_provider.main.name
}

output "operator_role_arn" {
  description = <<-EOT
    ARN of the IAM operator role for the capacity provider.
    
    This role grants the Lambda service permissions to manage EC2 resources
    on your behalf, including:
    - Launching and terminating EC2 instances
    - Creating and managing Elastic Network Interfaces (ENIs)
    - Describing EC2 resources for monitoring and scaling
    - Tagging instances with capacity provider identifiers
    
    The operator role is separate from the Lambda execution role. The execution
    role defines what your function code can do (e.g., access S3, DynamoDB),
    while the operator role defines what the Lambda service can do to manage
    the underlying EC2 infrastructure.
    
    This role uses the AWS managed policy AWSLambdaManagedInstancesOperatorRole,
    which is maintained by AWS to ensure compatibility with Lambda Managed
    Instances features.
  EOT
  value       = aws_iam_role.capacity_provider_operator.arn
}

output "security_group_id" {
  description = <<-EOT
    ID of the security group for Lambda Managed Instances.
    
    This security group controls network access for EC2 instances running
    Lambda functions. It is configured to:
    - Allow all outbound traffic (required for Lambda service communication)
    - No inbound rules (Lambda functions don't accept incoming connections)
    
    You can modify this security group to:
    - Restrict outbound access to specific destinations
    - Add VPC endpoint access for AWS services
    - Implement network segmentation policies
    
    Note: Changes to security group rules may affect Lambda function behavior.
    Test thoroughly before applying changes to production.
  EOT
  value       = aws_security_group.lambda_managed_instances.id
}
