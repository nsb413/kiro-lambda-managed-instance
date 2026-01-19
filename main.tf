terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0"
    }
  }

  backend "s3" {
    bucket = "xxxxx"
    key    = "fibonacci-lambda/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# ============================================================================
# VPC Data Sources for Lambda Managed Instances
# ============================================================================
# Query existing VPC to use for Lambda Managed Instances capacity provider.
# Lambda Managed Instances run on EC2 instances within a VPC, providing
# network isolation and allowing use of VPC features like security groups.

data "aws_vpc" "existing" {
  id = var.vpc_id
}

# Query private subnets in the VPC to select appropriate subnets for the
# capacity provider. Lambda Managed Instances should be deployed across
# multiple Availability Zones for high availability. Private subnets are
# preferred for security and require NAT Gateway or VPC endpoints for AWS service access.
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

# Get detailed information for each subnet to determine Availability Zone
# distribution. We select up to 3 subnets across different AZs to ensure
# fault tolerance and high availability for the Lambda Managed Instances.
data "aws_subnet" "selected" {
  for_each = toset(slice(data.aws_subnets.available.ids, 0, min(3, length(data.aws_subnets.available.ids))))
  id       = each.value
}

# ============================================================================
# Security Group for Lambda Managed Instances
# ============================================================================
# Security group for Lambda Managed Instances capacity provider.
# Lambda Managed Instances run on EC2 instances within your VPC and require
# network access control. This security group allows outbound traffic for:
# - Communication with AWS Lambda service endpoints
# - Access to other AWS services (S3, DynamoDB, etc.)
# - Internet access for external API calls (if needed)
#
# No inbound rules are needed because Lambda functions don't accept incoming
# network connections - they only process invocations from the Lambda service.

resource "aws_security_group" "lambda_managed_instances" {
  name_prefix = "${var.function_name}-managed-instances-"
  description = "Security group for Lambda Managed Instances - allows outbound traffic for Lambda service communication"
  vpc_id      = data.aws_vpc.existing.id

  # Allow all outbound traffic for Lambda service communication and AWS API calls
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for Lambda service communication and AWS API access"
  }

  tags = {
    Name        = "${var.function_name}-managed-instances-sg"
    Purpose     = "Lambda Managed Instances"
    ManagedBy   = "Terraform"
    Environment = "production"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# IAM Resources
# ============================================================================

# ============================================================================
# IAM Operator Role for Lambda Managed Instances Capacity Provider
# ============================================================================
# This operator role grants the Lambda service permissions to manage EC2
# resources on your behalf within the capacity provider. The role is assumed
# by the Lambda service (lambda.amazonaws.com) and allows it to:
#
# - Launch and terminate EC2 instances for running Lambda functions
# - Create and manage Elastic Network Interfaces (ENIs) in your VPC
# - Describe EC2 resources for monitoring and scaling decisions
# - Tag EC2 instances with aws:lambda:capacity-provider identifier
#
# This role is separate from the Lambda execution role. The execution role
# defines what your Lambda function code can do (e.g., access S3, DynamoDB),
# while the operator role defines what the Lambda service can do to manage
# the underlying EC2 infrastructure.
#
# The AWS managed policy AWSLambdaManagedInstancesOperatorRole contains all
# the necessary permissions and is maintained by AWS to ensure compatibility
# with Lambda Managed Instances features.

resource "aws_iam_role" "capacity_provider_operator" {
  name_prefix = "${var.function_name}-cp-operator-"
  description = "Operator role for Lambda Managed Instances capacity provider - grants Lambda service permissions to manage EC2 resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.function_name}-capacity-provider-operator"
    Purpose     = "Lambda Managed Instances Operator"
    ManagedBy   = "Terraform"
    Environment = "production"
    Description = "Grants Lambda service permissions to manage EC2 instances for Managed Instances capacity provider"
  }
}

# Attach AWS managed policy for Lambda Managed Instances operator permissions.
# This policy grants the Lambda service the necessary permissions to:
# - ec2:RunInstances, ec2:TerminateInstances (manage instance lifecycle)
# - ec2:CreateNetworkInterface, ec2:DeleteNetworkInterface (manage VPC networking)
# - ec2:DescribeInstances, ec2:DescribeSubnets, ec2:DescribeSecurityGroups (query resources)
# - ec2:CreateTags (tag instances with capacity provider identifier)
#
# AWS maintains this managed policy to ensure it stays up-to-date with
# Lambda Managed Instances requirements.
resource "aws_iam_role_policy_attachment" "operator_policy" {
  role       = aws_iam_role.capacity_provider_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaManagedEC2ResourceOperator"
}

# ============================================================================
# Lambda Capacity Provider for Managed Instances
# ============================================================================
# Lambda Managed Instances is a capability that runs Lambda functions on
# customer-owned Amazon EC2 instances while maintaining serverless operational
# simplicity. The capacity provider is the foundational resource that defines:
#
# 1. VPC Configuration: Where EC2 instances will be launched (subnets, security groups)
# 2. Instance Requirements: What types of EC2 instances to use (architecture, families)
# 3. Scaling Policy: How Lambda scales the EC2 fleet based on demand
# 4. Permissions: What role Lambda uses to manage EC2 resources
#
# Key Benefits of Lambda Managed Instances:
# - Cost Optimization: Use EC2 pricing with Savings Plans and Reserved Instances
# - Multi-Concurrency: One execution environment handles multiple invocations simultaneously
# - No Cold Starts: Instances are pre-warmed and ready to handle requests
# - Fully Managed: AWS handles patching, scaling, and routing automatically
#
# How It Works:
# 1. Lambda launches EC2 instances in your VPC using the operator role
# 2. Instances are tagged with aws:lambda:capacity-provider for identification
# 3. Lambda deploys execution environments (containers) on these instances
# 4. Your function code runs in these containers with multi-concurrent execution
# 5. Lambda automatically scales instances based on CPU utilization
#
# Cost Model:
# - EC2 instance costs (per-second billing)
# - 15% management fee on top of EC2 costs
# - Can apply EC2 Savings Plans and Reserved Instances
# - More cost-effective for high-volume, predictable workloads
#
# Important Notes:
# - Instances cannot be terminated manually (managed by Lambda service)
# - Requires Python 3.13+, Node.js 22+, Java 21+, or .NET 8+ for multi-concurrency
# - Function must have publish = true to use Managed Instances
# - Asynchronous scaling based on CPU utilization (no cold starts)

resource "aws_lambda_capacity_provider" "main" {
  name = "${var.function_name}-capacity-provider"

  # VPC configuration defines where EC2 instances will be launched.
  # Instances are distributed across multiple Availability Zones for high
  # availability and fault tolerance. Private subnets are recommended for
  # security, requiring NAT Gateway or VPC endpoints for AWS service access.
  vpc_config {
    subnet_ids         = [for s in data.aws_subnet.selected : s.id]
    security_group_ids = [aws_security_group.lambda_managed_instances.id]
  }

  # Permissions configuration specifies the IAM role that Lambda service
  # uses to manage EC2 resources (launch instances, create ENIs, etc.).
  # This is separate from the Lambda execution role that your function code uses.
  permissions_config {
    capacity_provider_operator_role_arn = aws_iam_role.capacity_provider_operator.arn
  }

  # Instance requirements define what types of EC2 instances Lambda can use.
  # Using x86_64 architecture for broad compatibility. Lambda automatically
  # selects optimal instance types from available families. Not restricting
  # to specific instance types provides better availability - if one type is
  # unavailable, Lambda can use alternatives.
  instance_requirements = [{
    architectures           = ["x86_64"]
    allowed_instance_types  = null
    excluded_instance_types = null
    # Allowing Lambda to automatically select instance types provides:
    # - Better availability (can use alternative types if preferred ones unavailable)
    # - Automatic optimization (Lambda chooses best price/performance ratio)
    # - Future compatibility (new instance types automatically considered)
  }]

  # Scaling configuration controls how Lambda manages the EC2 fleet size.
  # Auto mode enables asynchronous scaling based on CPU utilization:
  # - Lambda monitors aggregate CPU usage across all instances
  # - Scales up when CPU is high (adds instances proactively)
  # - Scales down when CPU is low (removes instances to save costs)
  # - No cold starts because scaling happens before capacity is exhausted
  # - Lambda automatically manages scaling policies (no manual configuration needed)
  #
  # The max_vcpu_count limits the maximum compute capacity to control costs.
  # Default is 16 vCPUs (roughly 2-3 medium instances or 8 small instances).
  # This conservative limit prevents runaway costs while allowing sufficient
  # capacity for testing and light production workloads. Increase as needed
  # based on your actual traffic patterns.
  capacity_provider_scaling_config = [{
    scaling_mode     = "Auto"
    max_vcpu_count   = var.capacity_provider_max_vcpu
    scaling_policies = null
  }]

  tags = {
    Name        = "${var.function_name}-capacity-provider"
    Purpose     = "Lambda Managed Instances"
    ManagedBy   = "Terraform"
    Environment = "production"
    Description = "Capacity provider for running Lambda functions on EC2 instances"
  }

  # Ensure operator role and policy attachment are created before the
  # capacity provider. The Lambda service needs these permissions to
  # launch and manage EC2 instances.
  depends_on = [
    aws_iam_role_policy_attachment.operator_policy
  ]
}

# ============================================================================
# IAM Execution Role for Lambda Function
# ============================================================================
# This is the standard Lambda execution role that defines what permissions
# your Lambda function code has when it runs (e.g., writing to CloudWatch Logs).
# This role is separate from the operator role above.

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create ZIP archive of Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# ============================================================================
# Lambda Function with Managed Instances
# ============================================================================
# This Lambda function is configured to run on Lambda Managed Instances,
# which means it executes on customer-owned EC2 instances instead of the
# standard multi-tenant Lambda execution environment.
#
# Key Configuration Changes for Managed Instances:
# 1. Runtime upgraded to Python 3.13 (required for multi-concurrent execution)
# 2. publish = true (required to create function versions for Managed Instances)
# 3. capacity_provider_config links function to the capacity provider
#
# Runtime Upgrade Rationale:
# Lambda Managed Instances requires Python 3.13+ (or Node.js 22+, Java 21+,
# .NET 8+) to support multi-concurrent execution. Multi-concurrency allows
# one execution environment to handle multiple invocations simultaneously,
# improving resource utilization and cost efficiency. Python 3.13 is backward
# compatible with Python 3.11 for most code, but test thoroughly before
# deploying to production.
#
# How Managed Instances Work:
# - Function code runs in containers on EC2 instances (not Firecracker VMs)
# - Multiple invocations can run concurrently in the same container
# - No cold starts because instances are pre-warmed
# - Lambda handles all routing, scaling, and infrastructure management

resource "aws_lambda_function" "fibonacci" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Runtime upgraded from python3.11 to python3.13 for Lambda Managed Instances compatibility.
  # Python 3.13+ is required to support multi-concurrent execution, where one execution
  # environment can handle multiple invocations simultaneously. This improves resource
  # utilization and cost efficiency on EC2 instances.
  runtime = "python3.13"

  memory_size = var.memory_size
  timeout     = var.timeout

  # Publishing is required for Lambda Managed Instances. When publish = true,
  # Lambda creates a new version of the function with each deployment. Managed
  # Instances uses these versions to manage deployments across EC2 instances.
  publish = true

  # Capacity provider configuration attaches this function to the Lambda Managed
  # Instances capacity provider. This tells Lambda to run the function on EC2
  # instances managed by the capacity provider instead of the standard Lambda
  # execution environment.
  capacity_provider_config {
    lambda_managed_instances_capacity_provider_config {
      capacity_provider_arn = aws_lambda_capacity_provider.main.arn
    }
  }

  # Ensure the capacity provider and execution role are created before the function.
  # The capacity provider must be in ACTIVE state before Lambda can attach the function.
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_lambda_capacity_provider.main
  ]

  # Force recreation when adding capacity provider config to existing function
  lifecycle {
    create_before_destroy = true
  }
}
