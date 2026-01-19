# ============================================================================
# Lambda Function Configuration Variables
# ============================================================================
# These variables define the core Lambda function configuration and are
# preserved from the original standard Lambda setup.

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "fibonacci-generator"
}

variable "memory_size" {
  description = "Memory allocation for Lambda function in MB (minimum 2048 MB for Managed Instances)"
  type        = number
  default     = 2048
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 10
}

# ============================================================================
# Lambda Managed Instances Configuration Variables
# ============================================================================
# These variables configure Lambda Managed Instances, which runs Lambda
# functions on customer-owned EC2 instances instead of the standard multi-tenant
# Lambda execution environment.
#
# Lambda Managed Instances Overview:
# Lambda Managed Instances is a capability that allows you to run Lambda
# functions on Amazon EC2 instances in your AWS account while maintaining
# serverless operational simplicity. AWS Lambda handles all infrastructure
# management including instance provisioning, patching, scaling, and routing.
#
# Key Benefits:
# - Cost Optimization: Use EC2 pricing with Savings Plans and Reserved Instances
# - Multi-Concurrency: One execution environment handles multiple invocations
# - No Cold Starts: Instances are pre-warmed and ready to handle requests
# - Specialized Compute: Access to EC2 instance families and configurations
#
# Cost Model:
# - EC2 instance costs (per-second billing based on instance type)
# - 15% management fee on top of EC2 costs
# - Can apply EC2 Savings Plans and Reserved Instances for additional savings
# - More cost-effective for high-volume, predictable workloads
# - Example: t3.medium at $0.0416/hour + 15% = $0.0478/hour total
#
# When to Use Managed Instances:
# - High-volume workloads with predictable traffic patterns
# - IO-heavy workloads that benefit from multi-concurrency
# - Cost-sensitive applications that can leverage EC2 pricing
# - Applications requiring specialized EC2 instance features
#
# References:
# - AWS Documentation: https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html
# - Capacity Providers: https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html

variable "vpc_id" {
  description = <<-EOT
    ID of the existing VPC for Lambda Managed Instances.
    
    Lambda Managed Instances run on EC2 instances within your VPC, providing
    network isolation and allowing use of VPC features like security groups,
    NACLs, and VPC endpoints. The VPC should have:
    - Private subnets across multiple Availability Zones for high availability
    - NAT Gateway or VPC endpoints for AWS service access
    - Sufficient IP address space for EC2 instances and ENIs
    
    Default: vpc-0e906eb9a1c35ab3a (existing VPC in this account)
  EOT
  type        = string
  default     = "vpc-0e906eb9a1c35ab3a"
}

variable "capacity_provider_max_vcpu" {
  description = <<-EOT
    Maximum number of vCPUs for the Lambda Managed Instances capacity provider.
    
    This setting controls the maximum compute capacity and acts as a cost ceiling
    for the EC2 instances managed by Lambda. The capacity provider will scale up
    to this limit based on CPU utilization and then stop adding instances.
    
    Cost Implications:
    - Each vCPU corresponds to EC2 instance capacity (e.g., t3.medium = 2 vCPUs)
    - 16 vCPUs ≈ 2-3 medium instances or 8 small instances
    - At t3.medium pricing ($0.0416/hour), 16 vCPUs ≈ $0.38/hour + 15% = $0.44/hour
    - Monthly cost estimate: ~$320/month for continuous operation
    
    Scaling Behavior:
    - Lambda automatically scales instances based on CPU utilization
    - Scaling is asynchronous (no cold starts)
    - Lower values reduce maximum cost but may limit throughput
    - Higher values allow more concurrent invocations but increase costs
    
    Recommendations:
    - Start with 16 vCPUs (default) for testing and light production
    - Monitor CloudWatch metrics to determine actual usage
    - Increase based on traffic patterns and performance requirements
    - Use EC2 Savings Plans or Reserved Instances for cost optimization
    
    Default: 16 vCPUs (conservative limit for cost control)
  EOT
  type        = number
  default     = 16
}
