# Implementation Plan: Lambda Managed Instances Migration

## Overview

This implementation plan outlines the step-by-step tasks to migrate the existing Fibonacci Lambda function from standard Lambda execution to Lambda Managed Instances using Terraform. The approach prioritizes minimal changes while properly configuring the new infrastructure components.

## Tasks

- [x] 1. Add VPC data sources to query existing infrastructure
  - Add data source for existing VPC (xxxx)
  - Add data source to query all subnets in the VPC
  - Add data source to get subnet details for AZ distribution
  - Select up to 3 subnets across different Availability Zones
  - _Requirements: 4.1, 4.2, 4.3_

- [x] 2. Create security group for Lambda Managed Instances
  - Create security group resource in the existing VPC
  - Configure egress rule to allow all outbound traffic
  - Add descriptive tags and comments
  - _Requirements: 4.4, 4.5, 9.1_

- [x] 3. Create IAM operator role for capacity provider
  - Create IAM role with trust policy for lambda.amazonaws.com
  - Attach AWS managed policy AWSLambdaManagedInstancesOperatorRole
  - Add descriptive tags and comments explaining the operator role purpose
  - _Requirements: 2.1, 2.2, 2.3, 9.2_

- [x] 4. Create Lambda capacity provider resource
  - Create aws_lambda_capacity_provider resource
  - Configure VPC settings with selected subnets and security group
  - Configure permissions with operator role ARN
  - Set instance requirements to x86_64 architecture
  - Configure automatic scaling mode
  - Add comprehensive comments explaining Managed Instances
  - Add depends_on for operator role policy attachment
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 9.3_

- [x] 5. Update Lambda function for Managed Instances
  - Change runtime from python3.11 to python3.13
  - Add capacity_provider_config block with capacity provider ARN
  - Set publish = true (required for Managed Instances)
  - Add depends_on for capacity provider
  - Add comment explaining runtime upgrade reason
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 7.1, 7.2, 7.3, 7.4_

- [x] 6. Add new Terraform outputs
  - Add output for capacity provider ARN
  - Add output for capacity provider name
  - Add output for operator role ARN
  - Add output for security group ID
  - _Requirements: 6.6_

- [x] 7. Add optional variables for configuration
  - Add variable for VPC ID with default xxxxxx1c35ab3a0e906eb9a1c35ab3a
  - Add variable for max vCPU count with default 16 (cost-conscious limit)
  - Add descriptions for all variables
  - _Requirements: 6.3_

- [x] 8. Add documentation comments throughout configuration
  - Add comments explaining Lambda Managed Instances concept
  - Document capacity provider purpose and configuration
  - Explain operator role permissions
  - Document multi-concurrency implications
  - Add references to AWS documentation
  - Document cost implications (EC2 pricing + 15% management fee)
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 10.1, 10.2, 10.3, 10.4, 10.5_

- [x] 9. Validate and test Terraform configuration
  - Run terraform fmt to format code
  - Run terraform validate to check syntax
  - Run terraform plan to preview changes
  - Review plan output for expected resource changes
  - Verify no unexpected deletions or modifications
  - _Requirements: 6.1, 6.4, 8.1, 8.2_

- [x] 10. Deploy infrastructure changes
  - Backup current Terraform state
  - Run terraform apply to create new resources
  - Monitor capacity provider state until ACTIVE
  - Verify EC2 instances are launched in account
  - Check instances have aws:lambda:capacity-provider tag
  - _Requirements: 8.1, 8.2_

- [ ] 11. Test Lambda function invocation
  - Test function with valid input using AWS CLI: `{"n": 10}`
  - Verify response contains correct Fibonacci sequence
  - Test error handling with invalid inputs (negative, missing)
  - Verify function behavior matches standard Lambda
  - Monitor CloudWatch logs for any errors
  - _Requirements: 3.6, 3.7_

- [ ] 12. Verify deployment and document results
  - Confirm capacity provider is in ACTIVE state
  - Verify Lambda function is attached to capacity provider
  - Check EC2 instances are running
  - Verify no cold starts occur
  - Document any issues or observations
  - Update project documentation with migration details
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

## Notes

- All tasks build incrementally on previous steps
- Each task includes specific requirements being addressed
- Tasks 1-8 focus on code changes without deployment
- Task 9 validates the configuration before deployment
- Tasks 10-12 handle deployment and verification
- The migration preserves existing function code and execution role
- Runtime upgrade to Python 3.13 is required for Managed Instances compatibility
- Capacity provider will launch 3 EC2 instances by default for AZ resiliency
