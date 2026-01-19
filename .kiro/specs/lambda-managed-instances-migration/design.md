# Design Document: Lambda Managed Instances Migration

## Overview

This design document outlines the migration of an existing AWS Lambda function (Fibonacci generator) from the standard Lambda execution model to Lambda Managed Instances using Terraform. Lambda Managed Instances is a capability that runs Lambda functions on customer-owned Amazon EC2 instances while maintaining serverless operational simplicity.

The migration will use native Terraform resources (`aws_lambda_capacity_provider` and `aws_lambda_function`) available in the AWS provider version 5.0+. The approach prioritizes minimal changes to the existing infrastructure while properly configuring the new Managed Instances components.

**Key Benefits:**
- Access to EC2 pricing advantages (Savings Plans, Reserved Instances)
- Multi-concurrent execution for better resource utilization
- Fully managed infrastructure (patching, scaling, routing)
- No cold starts (asynchronous scaling based on CPU utilization)

## Architecture

### Current Architecture
```
┌─────────────────────────────────────┐
│   Standard Lambda Execution        │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  Fibonacci Lambda Function   │  │
│  │  - Python 3.11               │  │
│  │  - 128 MB memory             │  │
│  │  - Multi-tenant execution    │  │
│  │  - Firecracker isolation     │  │
│  └──────────────────────────────┘  │
│                                     │
│  IAM Execution Role                 │
│  - AWSLambdaBasicExecutionRole     │
└─────────────────────────────────────┘
```

### Target Architecture
```
┌────────────────────────────────────────────────────────────┐
│   Lambda Managed Instances Architecture                    │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Capacity Provider                                   │  │
│  │  - VPC: xxxxx                      │  │
│  │  - Subnets: Multiple AZs                            │  │
│  │  - Security Group                                    │  │
│  │  - Operator Role (EC2 management permissions)       │  │
│  │  - Auto scaling mode                                 │  │
│  │  - x86_64 architecture                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Lambda Function                                     │  │
│  │  - Python 3.13 (upgraded for compatibility)         │  │
│  │  - 128 MB memory                                     │  │
│  │  - Attached to Capacity Provider                    │  │
│  │  - Multi-concurrent execution                        │  │
│  │  - Container isolation on EC2 Nitro                 │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  EC2 Instances (Managed by Lambda)                  │  │
│  │  - Launched in customer account                     │  │
│  │  - Fully managed by AWS Lambda service              │  │
│  │  - Cannot be terminated manually                    │  │
│  │  - Tagged: aws:lambda:capacity-provider             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  IAM Roles:                                                 │
│  - Lambda Execution Role (function permissions)             │
│  - Operator Role (EC2 management permissions)               │
└────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. VPC Network Discovery

**Purpose:** Query existing VPC resources to configure the capacity provider

**Terraform Resources:**
- `data "aws_vpc"` - Query existing VPC by ID
- `data "aws_subnets"` - Query available subnets in the VPC
- `data "aws_subnet"` - Get details for each subnet (AZ information)

**Implementation:**
```terraform
# Query existing VPC
data "aws_vpc" "existing" {
  id = "xxxxxx1c35ab3a0e906eb9a1c35ab3a"
}

# Query all subnets in the VPC
data "aws_subnets" "available" {
  filter {
    name   = "xxxxxx1c35ab3aid"
    values = [data.aws_vpc.existing.id]
  }
}

# Get subnet details for AZ distribution
data "aws_subnet" "selected" {
  for_each = toset(slice(data.aws_subnets.available.ids, 0, min(3, length(data.aws_subnets.available.ids))))
  id       = each.value
}
```

**Interface:**
- Input: VPC ID (xxxxxx1c35ab3a0e906eb9a1c35ab3a)
- Output: List of subnet IDs across multiple AZs

### 2. Security Group

**Purpose:** Control network access for Lambda Managed Instances

**Terraform Resource:** `aws_security_group`

**Configuration:**
- VPC: Existing VPC (xxxxxx1c35ab3a0e906eb9a1c35ab3a)
- Egress: Allow all outbound traffic (required for Lambda service communication)
- Ingress: No inbound rules needed (Lambda functions don't accept incoming connections)

**Implementation:**
```terraform
resource "aws_security_group" "lambda_managed_instances" {
  name_prefix = "${var.function_name}-managed-instances-"
  description = "Security group for Lambda Managed Instances"
  vpc_id      = data.aws_vpc.existing.id

  # Allow all outbound traffic for Lambda service communication
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic for Lambda service communication"
  } tags = {
    Name = "${var.function_name}-managed-instances-sg"
  }
}
```

### 3. IAM Operator Role

**Purpose:** Grant Lambda service permissions to manage EC2 instances within the capacity provider

**Terraform Resources:**
- `aws_iam_role` - Operator role
- `aws_iam_role_policy_attachment` - Attach AWS managed policy

**Required Permissions:**
- Launch, terminate, and manage EC2 instances
- Create and manage network interfaces
- Describe EC2 resources

**Implementation:**
```terraform
# IAM role for Lambda to manage EC2 instances
resource "aws_iam_role" "capacity_provider_operator" {
  name_prefix = "${var.function_name}-cp-operator-"

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
    Name = "${var.function_name}-capacity-provider-operator"
  }
}

# Attach AWS managed policy for Lambda Managed Instances operator
resource "aws_iam_role_policy_attachment" "operator_policy" {
  role       = aws_iam_role.capacity_provider_operator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaManagedInstancesOperatorRole"
}
```

**Interface:**
- Input: None
- Output: Operator role ARN

### 4. Lambda Capacity Provider

**Purpose:** Define compute infrastructure for Lambda Managed Instances

**Terraform Resource:** `aws_lambda_capacity_provider`

**Configuration:**
- Name: Unique identifier for the capacity provider
- VPC Config: Subnets and security groups
- Permissions Config: Operator role ARN
- Instance Requirements: x86_64 architecture, auto-selected instance types
- Scaling Policy: Automatic scaling mode

**Implementation:**
```terraform
resource "aws_lambda_capacity_provider" "main" {
  name = "${var.function_name}-capacity-provider"

  # VPC configuration using existing VPC resources
  vpc_config {
    subnet_ids         = [for s in data.aws_subnet.selected : s.id]
    security_group_ids = [aws_security_group.lambda_managed_instances.id]
  }

  # Permissions for Lambda to manage EC2 resources
  permissions_config {
    capacity_provider_operator_role_arn = aws_iam_role.capacity_provider_operator.arn
  }

  # Instance requirements
  instance_requirements {
    architectures = ["X86_64"]
    # Allow Lambda to automatically select optimal instance types
    # This provides better availability than restricting to specific types
  }

  # Scaling configuration
  capacity_provider_scaling_policy {
    scaling_mode = "AUTO"
    # Default max_vpcu_count is 400 if not specified
  }

  tags = {
    Name = "${var.function_name}-capacity-provider"
  }

  depends_on = [
    aws_iam_role_policy_attachment.operator_policy
  ]
}
```

**Interface:**
- Input: VPC config, operator role ARN, instance requirements
- Output: Capacity provider ARN

### 5. Lambda Function Migration

**Purpose:** Update existing Lambda function to use Managed Instances

**Terraform Resource:** `aws_lambda_function` (modified)

**Changes Required:**
1. Upgrade runtime from Python 3.11 to Python 3.13 (Managed Instances requirement)
2. Add `capacity_provider_config` block
3. Set `publish = true` (required for Managed Instances)
4. Add dependency on capacity provider

**Implementation:**
```terraform
resource "aws_lambda_function" "fibonacci" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # CHANGED: Upgrade to Python 3.13 for Managed Instances compatibility
  runtime = "python3.13"
  
  memory_size = var.memory_size
  timeout     = var.timeout

  # CHANGED: Publish function version (required for Managed Instances)
  publish = true

  # NEW: Attach function to capacity provider
  capacity_provider_config {
    lambda_managed_instances_capacity_provider_config {
      capacity_provider_arn = aws_lambda_capacity_provider.main.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_lambda_capacity_provider.main
  ]
}
```

**Interface:**
- Input: Function code, capacity provider ARN, execution role
- Output: Function ARN, invoke ARN

## Data Models

### Terraform Variables

**Existing Variables (Preserved):**
```terraform
variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "fibonacci-generator"
}

variable "memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 10
}
```

**New Variables (Optional):**
```terraform
variable "vpc_id" {
  description = "ID of the existing VPC for Lambda Managed Instances"
  type        = string
  default     = "xxxxxx1c35ab3a0e906eb9a1c35ab3a"
}

variable "capacity_provider_max_vcpu" {
  description = "Maximum number of vCPUs for the capacity provider"
  type        = number
  default     = 400
}
```

### Terraform Outputs

**Existing Outputs (Preserved):**
```terraform
output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.fibonacci.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.fibonacci.function_name
}
```

**New Outputs:**
```terraform
output "capacity_provider_arn" {
  description = "ARN of the Lambda Capacity Provider"
  value       = aws_lambda_capacity_provider.main.arn
}

output "capacity_provider_name" {
  description = "Name of the Lambda Capacity Provider"
  value       = aws_lambda_capacity_provider.main.name
}

output "operator_role_arn" {
  description = "ARN of the Capacity Provider operator role"
  value       = aws_iam_role.capacity_provider_operator.arn
}

output "security_group_id" {
  description = "ID of the security group for Managed Instances"
  value       = aws_security_group.lambda_managed_instances.id
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*


### Testable Properties

Based on the prework analysis, most of the acceptance criteria for this infrastructure migration are configuration validation examples rather than universal properties. The primary testable properties are:

**Property 1: Multi-AZ Distribution**
*For any* set of selected subnets for the capacity provider, the subnets should span at least two different Availability Zones to ensure high availability
**Validates: Requirements 1.4, 4.3**

**Property 2: Resource Naming Consistency**
*For any* resource created by the Terraform configuration, the resource name should follow a consistent naming pattern using the function name as a prefix
**Validates: Requirements 6.7**

### Configuration Validation Examples

The majority of requirements are validated through configuration examples that verify specific Terraform resources and attributes are correctly defined:

- Capacity provider creation with required attributes (1.1, 1.2, 1.3, 1.5, 1.6, 1.7, 1.8)
- IAM operator role configuration (2.1, 2.2, 2.3)
- Lambda function migration settings (3.1, 3.2, 3.3, 3.4, 3.5, 7.1, 7.2, 7.3)
- VPC and network configuration (4.1, 4.2, 4.4, 4.5)
- Terraform best practices (6.1, 6.2, 6.3, 6.4, 6.5, 6.6)
- Documentation and comments (7.4, 9.1-9.6, 10.1-10.5)
- State management (8.1, 8.2)

These will be validated through:
1. Terraform validation (`terraform validate`)
2. Terraform plan review
3. Code review for comments and documentation
4. Post-deployment verification

## Error Handling

### Terraform Validation Errors

**Scenario:** Invalid Terraform syntax or configuration
**Handling:**
- Run `terraform validate` before apply
- Fix syntax errors and missing required arguments
- Verify provider version compatibility

**Scenario:** VPC or subnet not found
**Handling:**
- Verify VPC ID is correct (xxxxxx1c35ab3a0e906eb9a1c35ab3a)
- Ensure subnets exist in the VPC
- Check AWS credentials and region configuration

### Deployment Errors

**Scenario:** Capacity provider creation fails
**Handling:**
- Verify operator role has correct permissions
- Check VPC and subnet configurations are valid
- Ensure security group rules allow required traffic
- Review CloudWatch logs for detailed error messages

**Scenario:** Lambda function update fails
**Handling:**
- Verify capacity provider is in ACTIVE state before attaching function
- Ensure runtime upgrade to Python 3.13 is compatible with function code
- Check that `publish = true` is set
- Review function logs for initialization errors

**Scenario:** Insufficient subnet capacity
**Handling:**
- Verify selected subnets have available IP addresses
- Consider using additional subnets across more AZs
- Check VPC CIDR block has sufficient address space

### Runtime Errors

**Scenario:** Function code incompatible with Python 3.13
**Handling:**
- Test function code with Python 3.13 locally before migration
- Update any deprecated syntax or libraries
- Review Python 3.13 migration guide for breaking changes
- Consider using Lambda layers for dependencies

**Scenario:** Multi-concurrency issues
**Handling:**
- Review function code for thread safety
- Ensure global state is properly managed
- Test with concurrent invocations
- Monitor CloudWatch metrics for errors

### Rollback Strategy

**Scenario:** Migration needs to be rolled back
**Handling:**
1. Remove `capacity_provider_config` block from Lambda function
2. Change runtime back to Python 3.11 if needed
3. Set `publish = false`
4. Run `terraform apply` to revert changes
5. Delete capacity provider resource
6. Clean up operator role and security group

## Testing Strategy

### Terraform Validation
- Run `terraform fmt` to ensure consistent formatting
- Run `terraform validate` to check syntax and configuration
- Run `terraform plan` to preview changes before applying

### Local Lambda Testing

After deployment, test the Lambda function locally using AWS CLI:

```bash
# Test with valid input
aws lambda invoke \
  --function-name fibonacci-generator \
  --payload '{"n": 10}' \
  --cli-binary-format raw-in-base64-out \
  response.json

# View the response
cat response.json

# Expected output:
# {
#   "statusCode": 200,
#   "headers": {"Content-Type": "application/json"},
#   "body": "{\"n\": 10, \"sequence\": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]}"
# }
```

Test error handling:
```bash
# Test with invalid input (negative number)
aws lambda invoke \
  --function-name fibonacci-generator \
  --payload '{"n": -5}' \
  --cli-binary-format raw-in-base64-out \
  response.json

# Test with missing input
aws lambda invoke \
  --function-name fibonacci-generator \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json
```

### Post-Deployment Verification
1. Verify capacity provider is in ACTIVE state
2. Confirm Lambda function is attached to capacity provider
3. Check EC2 instances are launched in your account
4. Test function invocations work correctly
5. Monitor CloudWatch logs for any errors

## Migration Steps

### Phase 1: Preparation
1. Review current Lambda function configuration
2. Test function code with Python 3.13 locally
3. Backup current Terraform state
4. Verify VPC and subnet availability
5. Review AWS documentation for Managed Instances

### Phase 2: Infrastructure Updates
1. Add VPC data sources to query existing resources
2. Create security group for Managed Instances
3. Create IAM operator role with required permissions
4. Create Lambda capacity provider resource
5. Add comprehensive comments explaining new resources

### Phase 3: Lambda Function Migration
1. Update Lambda function runtime to Python 3.13
2. Add capacity_provider_config block
3. Set publish = true
4. Add dependency on capacity provider
5. Update outputs to include new resource ARNs

### Phase 4: Deployment
1. Run `terraform fmt` and `terraform validate`
2. Run `terraform plan` and review changes carefully
3. Apply changes with `terraform apply`
4. Monitor capacity provider state until ACTIVE
5. Verify EC2 instances are launched
6. Test function invocations

### Phase 5: Validation
1. Run integration tests
2. Monitor CloudWatch metrics and logs
3. Verify no cold starts occur
4. Test concurrent invocations
5. Confirm cost tracking is working
6. Update documentation

## Key Design Decisions

### 1. Use Native Terraform Resources
**Decision:** Use `aws_lambda_capacity_provider` and `aws_lambda_function` resources
**Rationale:** Native Terraform support is available in AWS provider 5.0+, providing better integration and state management than CloudFormation or AWS CLI alternatives
**Trade-offs:** Requires AWS provider 5.0+, but this is already specified in the existing configuration

### 2. Automatic Instance Type Selection
**Decision:** Allow Lambda to automatically select instance types
**Rationale:** AWS recommends this approach for better availability. Restricting instance types can reduce availability if specific types are unavailable
**Trade-offs:** Less control over instance types, but better reliability and AWS handles optimization

### 3. Runtime Upgrade to Python 3.13
**Decision:** Upgrade from Python 3.11 to Python 3.13
**Rationale:** Lambda Managed Instances requires Python 3.13+ for multi-concurrent execution support
**Trade-offs:** Requires testing for compatibility, but Python 3.13 is backward compatible for most code

### 4. Automatic Scaling Mode
**Decision:** Use AUTO scaling mode for capacity provider
**Rationale:** Allows Lambda to dynamically scale based on CPU utilization without manual intervention
**Trade-offs:** Less predictable costs, but better resource utilization and performance

### 5. Multi-AZ Subnet Selection
**Decision:** Select subnets across multiple Availability Zones
**Rationale:** Provides high availability and fault tolerance as recommended by AWS
**Trade-offs:** Slightly more complex configuration, but essential for production workloads

### 6. Minimal Code Changes
**Decision:** Preserve existing function code without modifications
**Rationale:** Reduces migration risk and complexity. Python code is compatible with multi-concurrency by default (uses multiple processes)
**Trade-offs:** May not take full advantage of multi-concurrency optimizations, but ensures safe migration

### 7. Preserve Existing IAM Execution Role
**Decision:** Keep existing Lambda execution role unchanged
**Rationale:** Operator role is separate from execution role. Execution role permissions remain the same
**Trade-offs:** None - this is the correct approach per AWS documentation

## Cost Considerations

### Pricing Model
- **EC2 Instance Costs:** Standard EC2 pricing based on instance type and usage
- **Management Fee:** 15% fee on top of EC2 costs
- **Savings Opportunities:** EC2 Savings Plans and Reserved Instances can be applied
- **No Cold Start Costs:** Eliminates cold start latency and associated costs

### Cost Optimization Strategies
1. Use EC2 Savings Plans for predictable workloads
2. Monitor vCPU utilization and adjust max_vcpu_count
3. Leverage automatic scaling to match demand
4. Consider Reserved Instances for steady-state workloads
5. Monitor CloudWatch metrics to optimize memory and concurrency settings

### Cost Comparison
- **Standard Lambda:** Pay per request and duration
- **Managed Instances:** Pay for EC2 instances + 15% management fee
- **Break-even:** Managed Instances are cost-effective for high-volume, predictable workloads

## Security Considerations

### Network Security
- Security group restricts traffic to necessary outbound connections
- Instances run in private subnets (if configured)
- VPC provides network isolation

### IAM Security
- Operator role has minimal required permissions (AWS managed policy)
- Execution role permissions unchanged from current setup
- Principle of least privilege maintained

### Data Security
- Function code and environment variables encrypted at rest
- Network traffic encrypted in transit
- KMS encryption can be added for additional security

### Compliance
- Capacity provider serves as security boundary
- Separate capacity providers for different trust levels
- Audit trail via CloudTrail for all API calls

## Monitoring and Observability

### CloudWatch Metrics
- Monitor capacity provider state
- Track EC2 instance count and utilization
- Monitor Lambda invocation metrics
- Track error rates and duration

### CloudWatch Logs
- Lambda function logs (unchanged from current setup)
- Capacity provider events
- EC2 instance lifecycle events

### Alarms
- Alert on capacity provider state changes
- Monitor for high error rates
- Track unusual scaling patterns
- Alert on cost thresholds

## References

- [AWS Lambda Managed Instances Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Capacity Providers Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)
- [Terraform AWS Provider - Lambda Function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function)
- [Terraform AWS Provider - Lambda Capacity Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_capacity_provider)
- [Python 3.13 Runtime for Lambda](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-python-runtime.html)
