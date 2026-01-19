# Requirements Document

## Introduction

This document specifies the requirements for migrating an existing AWS Lambda function (Fibonacci generator) from the standard Lambda execution model to Lambda Managed Instances. Lambda Managed Instances is a capability that runs Lambda functions on customer-owned Amazon EC2 instances while maintaining serverless operational simplicity. This migration aims to leverage EC2 pricing advantages and specialized compute configurations while making minimal changes to the existing infrastructure.

## Glossary

- **Lambda_Function**: The existing Fibonacci generator Lambda function currently deployed using standard Lambda execution model
- **Managed_Instances**: AWS Lambda Managed Instances execution environment that runs on EC2 instances
- **Capacity_Provider**: The foundational resource that defines VPC configuration, instance requirements, and scaling policies for Managed Instances
- **Operator_Role**: IAM role that grants Lambda service permissions to manage EC2 resources within the capacity provider
- **Execution_Environment**: Container running on EC2 instances that processes Lambda invocations
- **Multi_Concurrency**: Capability where one execution environment handles multiple invocations simultaneously
- **Terraform_Configuration**: Infrastructure as Code files defining AWS resources using HashiCorp Terraform

## Requirements

### Requirement 1: Capacity Provider Creation

**User Story:** As a cloud engineer, I want to create a capacity provider for Lambda Managed Instances, so that Lambda can provision and manage EC2 instances on my behalf.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create a capacity provider resource with a unique name
2. WHEN creating the capacity provider, THE Terraform_Configuration SHALL specify VPC configuration with at least one subnet ID
3. WHEN creating the capacity provider, THE Terraform_Configuration SHALL specify security group IDs for network access control
4. THE Terraform_Configuration SHALL configure the capacity provider to use multiple Availability Zones for high availability
5. WHEN creating the capacity provider, THE Terraform_Configuration SHALL reference an Operator_Role ARN for EC2 resource management permissions
6. THE Terraform_Configuration SHALL set the capacity provider scaling mode to automatic
7. THE Terraform_Configuration SHALL use x86_64 architecture for instance requirements
8. THE Terraform_Configuration SHALL allow Lambda to automatically select optimal instance types

### Requirement 2: IAM Operator Role Configuration

**User Story:** As a cloud engineer, I want to configure an IAM operator role with appropriate permissions, so that Lambda service can manage EC2 instances within the capacity provider.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL create an IAM role that Lambda service can assume
2. WHEN defining the operator role, THE Terraform_Configuration SHALL attach a trust policy allowing lambda.amazonaws.com to assume the role
3. THE Terraform_Configuration SHALL attach AWS managed policy AWSLambdaManagedEC2ResourceOperator to the operator role
4. THE Operator_Role SHALL have permissions to launch, terminate, and manage EC2 instances
5. THE Operator_Role SHALL have permissions to create and manage network interfaces in the specified VPC
6. THE Operator_Role SHALL have permissions to describe EC2 resources for monitoring and scaling decisions

### Requirement 3: Lambda Function Migration

**User Story:** As a cloud engineer, I want to migrate the existing Lambda function to use Managed Instances, so that it runs on EC2 instances while maintaining the same functionality.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL preserve the existing Lambda function name, handler, and runtime
2. WHEN migrating the function, THE Terraform_Configuration SHALL attach the function to the Capacity_Provider
3. THE Lambda_Function SHALL continue to use the existing IAM execution role for function permissions
4. THE Lambda_Function SHALL maintain the same memory size and timeout configurations
5. THE Lambda_Function SHALL preserve the existing source code without modifications
6. WHEN the function is published, THE Managed_Instances SHALL launch execution environments on EC2 instances
7. THE Lambda_Function SHALL process invocations through the Managed_Instances execution environment

### Requirement 4: Network Configuration

**User Story:** As a cloud engineer, I want to configure VPC networking for Managed Instances using my existing VPC, so that the Lambda function can run securely within my established network infrastructure.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL use existing VPC vpc-0e906eb9a1c35ab3a
2. THE Terraform_Configuration SHALL use data sources to query existing VPC subnets
3. THE Terraform_Configuration SHALL select at least two subnets in different Availability Zones from the existing VPC
4. THE Terraform_Configuration SHALL create a new security group specifically for Managed Instances with appropriate ingress and egress rules
5. THE Terraform_Configuration SHALL configure the security group to allow outbound internet access for Lambda service communication
6. WHEN using private subnets, THE Terraform_Configuration SHALL verify NAT gateway or VPC endpoints exist for AWS service access

### Requirement 5: Minimal Changes Principle

**User Story:** As a cloud engineer, I want to make minimal changes to the existing infrastructure, so that the migration is low-risk and easy to understand.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL preserve all existing Lambda function code without modifications
2. THE Terraform_Configuration SHALL preserve the existing Lambda execution role and its permissions
3. THE Terraform_Configuration SHALL preserve the existing function configuration parameters (memory, timeout, runtime)
4. THE Terraform_Configuration SHALL add only the necessary resources for Managed Instances (capacity provider and operator role)
5. THE Terraform_Configuration SHALL maintain the existing S3 backend configuration
6. THE Terraform_Configuration SHALL preserve the existing variable definitions and outputs
7. WHEN migrating, THE Terraform_Configuration SHALL require changes only to the Lambda function resource and addition of new capacity provider resources

### Requirement 6: Terraform Best Practices

**User Story:** As a cloud engineer, I want the Terraform configuration to follow best practices, so that the infrastructure is maintainable and follows AWS recommendations.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL use the latest AWS provider version (5.x or higher)
2. THE Terraform_Configuration SHALL use data sources to reference existing AWS resources where appropriate
3. THE Terraform_Configuration SHALL define variables for configurable parameters with appropriate defaults
4. THE Terraform_Configuration SHALL use resource dependencies (depends_on) to ensure correct creation order
5. THE Terraform_Configuration SHALL include descriptive comments explaining Managed Instances-specific configurations
6. THE Terraform_Configuration SHALL output relevant resource identifiers (capacity provider ARN, function ARN)
7. THE Terraform_Configuration SHALL use consistent naming conventions for all resources

### Requirement 7: Runtime Compatibility

**User Story:** As a cloud engineer, I want to ensure the Lambda function runtime is compatible with Managed Instances, so that the function executes correctly after migration.

#### Acceptance Criteria

1. WHEN the existing runtime is Python 3.11, THE Terraform_Configuration SHALL upgrade to Python 3.13 or later
2. WHEN the existing runtime is not supported by Managed Instances, THE Terraform_Configuration SHALL specify a compatible runtime version
3. THE Lambda_Function SHALL use a runtime that supports multi-concurrent execution (Python 3.13+, Node.js 22+, Java 21+, or .NET 8+)
4. THE Terraform_Configuration SHALL document any runtime version changes in comments

### Requirement 8: State Management and Deployment

**User Story:** As a cloud engineer, I want to manage the migration through Terraform state, so that I can safely apply changes and rollback if needed.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL maintain state in the existing S3 backend
2. WHEN applying changes, THE Terraform_Configuration SHALL create new resources before modifying the Lambda function
3. THE Terraform_Configuration SHALL use Terraform lifecycle rules to prevent accidental resource deletion
4. THE Terraform_Configuration SHALL allow for gradual rollout by supporting conditional resource creation
5. WHEN deployment fails, THE Terraform_Configuration SHALL allow rollback to the previous state

### Requirement 9: Documentation and Comments

**User Story:** As a cloud engineer, I want comprehensive documentation in the Terraform files, so that I understand the Managed Instances configuration and can maintain it.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL include comments explaining what Lambda Managed Instances are
2. THE Terraform_Configuration SHALL document the purpose of the capacity provider resource
3. THE Terraform_Configuration SHALL document the operator role permissions and why they are needed
4. THE Terraform_Configuration SHALL include comments explaining multi-concurrency implications
5. THE Terraform_Configuration SHALL document any differences from standard Lambda execution model
6. THE Terraform_Configuration SHALL include references to AWS documentation for Managed Instances

### Requirement 10: Cost Optimization Considerations

**User Story:** As a cloud engineer, I want to understand the cost implications of Managed Instances, so that I can make informed decisions about the migration.

#### Acceptance Criteria

1. THE Terraform_Configuration SHALL document that Managed Instances use EC2 pricing plus 15% management fee
2. THE Terraform_Configuration SHALL document that EC2 Savings Plans and Reserved Instances can be applied
3. THE Terraform_Configuration SHALL configure automatic scaling to optimize resource utilization
4. THE Terraform_Configuration SHALL document that multi-concurrency improves cost efficiency for IO-heavy workloads
5. THE Terraform_Configuration SHALL set reasonable maximum vCPU limits to control costs
