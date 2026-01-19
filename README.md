# Fibonacci Lambda Function with Managed Instances

A Python-based AWS Lambda function that generates Fibonacci sequences, now running on **Lambda Managed Instances** for improved cost efficiency and performance. The function accepts a number as input and returns the Fibonacci sequence up to that position.

## Overview

This project provides:
- A Python 3.13 Lambda function for generating Fibonacci sequences
- **Lambda Managed Instances** execution on customer-owned EC2 instances
- Terraform infrastructure as code for automated deployment
- Comprehensive input validation and error handling
- Support for sequences up to position 1000
- Multi-concurrent execution for improved resource utilization

## What are Lambda Managed Instances?

Lambda Managed Instances is a capability that runs Lambda functions on customer-owned Amazon EC2 instances while maintaining serverless operational simplicity. AWS Lambda handles all infrastructure management including instance provisioning, patching, scaling, and routing.

**Key Benefits:**
- **Cost Optimization**: Use EC2 pricing with Savings Plans and Reserved Instances (15% management fee)
- **Multi-Concurrency**: One execution environment handles multiple invocations simultaneously
- **No Cold Starts**: Instances are pre-warmed and ready to handle requests
- **Fully Managed**: AWS handles patching, scaling, and routing automatically

**Cost Model:**
- EC2 instance costs (per-second billing)
- 15% management fee on top of EC2 costs
- Can apply EC2 Savings Plans and Reserved Instances
- More cost-effective for high-volume, predictable workloads

**References:**
- [AWS Lambda Managed Instances Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Capacity Providers Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)

## Prerequisites

Before deploying this Lambda function with Managed Instances, ensure you have:

1. **AWS CLI** configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **Terraform** installed (version >= 1.0)
   ```bash
   terraform --version
   ```

3. **AWS Permissions** - Your AWS credentials must have permissions to:
   - Create and manage Lambda functions
   - Create and manage IAM roles and policies
   - Create and manage EC2 instances (for Managed Instances)
   - Create and manage VPC resources (security groups, network interfaces)
   - Access S3 for Terraform state storage

4. **S3 Backend** - The S3 bucket for Terraform state must exist:
   - Bucket: `demo-bucket-448479419844-us-east-1-cds3fac1gkujufq`
   - Region: `us-east-1`

5. **VPC Configuration** - An existing VPC with:
   - VPC ID: `vpc-0e906eb9a1c35ab3a` (or update `vpc_id` variable)
   - Private subnets across multiple Availability Zones
   - NAT Gateway or VPC endpoints for AWS service access
   - Sufficient IP address space for EC2 instances

## Deployment Instructions

### Step 1: Initialize Terraform

Initialize the Terraform working directory and configure the S3 backend:

```bash
terraform init
```

This command will:
- Download required provider plugins (AWS provider)
- Configure the S3 backend for remote state storage
- Prepare the working directory for deployment

### Step 2: Review the Deployment Plan

Preview the changes Terraform will make:

```bash
terraform plan
```

This command shows:
- Resources that will be created (Lambda function, IAM role, etc.)
- Configuration values
- Any potential issues before deployment

### Step 3: Deploy the Lambda Function

Apply the Terraform configuration to deploy the Lambda function:

```bash
terraform apply
```

- Review the planned changes
- Type `yes` when prompted to confirm deployment
- Wait for the deployment to complete

After successful deployment, Terraform will output:
- `lambda_function_arn`: The ARN of the deployed Lambda function
- `lambda_function_name`: The name of the Lambda function
- `capacity_provider_arn`: The ARN of the Lambda Capacity Provider
- `capacity_provider_name`: The name of the Lambda Capacity Provider
- `operator_role_arn`: The ARN of the operator role for EC2 management
- `security_group_id`: The ID of the security group for Managed Instances

### Step 5: Verify Managed Instances Deployment

Verify the Lambda function and capacity provider were created successfully:

```bash
# Check Lambda function
aws lambda get-function --function-name fibonacci-generator

# Check capacity provider status (should be ACTIVE)
aws lambda get-capacity-provider --name fibonacci-generator-capacity-provider

# List EC2 instances managed by Lambda (should see instances with aws:lambda:capacity-provider tag)
aws ec2 describe-instances \
  --filters "Name=tag:aws:lambda:capacity-provider,Values=*" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,Tags[?Key==`aws:lambda:capacity-provider`].Value|[0]]' \
  --output table
```

**Expected Results:**
- Capacity provider status: `ACTIVE`
- EC2 instances: 2-3 instances running in your VPC
- Instances tagged with: `aws:lambda:capacity-provider = fibonacci-generator-capacity-provider`

## Configuration Options

You can customize the Lambda function and Managed Instances configuration by modifying variables in `variables.tf` or passing them during deployment:

```bash
terraform apply \
  -var="function_name=my-fibonacci-function" \
  -var="memory_size=256" \
  -var="timeout=15" \
  -var="capacity_provider_max_vcpu=32"
```

Available variables:

**Lambda Function Configuration:**
- `function_name`: Name of the Lambda function (default: `fibonacci-generator`)
- `memory_size`: Memory allocation in MB (default: `128`)
- `timeout`: Function timeout in seconds (default: `10`)

**Lambda Managed Instances Configuration:**
- `vpc_id`: ID of the existing VPC (default: `vpc-0e906eb9a1c35ab3a`)
- `capacity_provider_max_vcpu`: Maximum vCPUs for capacity provider (default: `16`)
  - Controls maximum compute capacity and cost ceiling
  - 16 vCPUs ≈ 2-3 medium instances or 8 small instances
  - Increase based on traffic patterns and performance requirements

## Testing the Lambda Function

### Using AWS CLI

Test the Lambda function using the AWS CLI:

**Note:** AWS CLI v2 requires the `--cli-binary-format` flag to properly handle JSON payloads.

```bash
aws lambda invoke \
  --function-name fibonacci-generator \
  --cli-binary-format raw-in-base64-out \
  --payload '{"n": 10}' \
  response.json

cat response.json
```

**Alternative method using a payload file:**

```bash
# Create payload file
echo '{"n": 10}' > payload.json

# Invoke Lambda
aws lambda invoke \
  --function-name fibonacci-generator \
  --cli-binary-format raw-in-base64-out \
  --payload file://payload.json \
  response.json

cat response.json
```

### Example Invocation Payloads

#### Valid Inputs

**Generate Fibonacci sequence up to position 10:**
```json
{
  "n": 10
}
```

Expected response:
```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"n\": 10, \"sequence\": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]}"
}
```

**Edge case - position 0:**
```json
{
  "n": 0
}
```

Expected response:
```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"n\": 0, \"sequence\": [0]}"
}
```

**Edge case - position 1:**
```json
{
  "n": 1
}
```

Expected response:
```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"n\": 1, \"sequence\": [0, 1]}"
}
```

**Large sequence - position 20:**
```json
{
  "n": 20
}
```

Expected response:
```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"n\": 20, \"sequence\": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181, 6765]}"
}
```

#### Invalid Inputs

**Missing input parameter:**
```json
{}
```

Expected response:
```json
{
  "statusCode": 400,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"error\": \"Input parameter 'n' is required\"}"
}
```

**Non-integer input:**
```json
{
  "n": "hello"
}
```

Expected response:
```json
{
  "statusCode": 400,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"error\": \"Input must be an integer\"}"
}
```

**Negative input:**
```json
{
  "n": -5
}
```

Expected response:
```json
{
  "statusCode": 400,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"error\": \"Input must be a non-negative integer\"}"
}
```

**Input exceeds limit:**
```json
{
  "n": 1500
}
```

Expected response:
```json
{
  "statusCode": 400,
  "headers": {
    "Content-Type": "application/json"
  },
  "body": "{\"error\": \"Input must not exceed 1000\"}"
}
```

### Using AWS Console

1. Navigate to the AWS Lambda console
2. Find the `fibonacci-generator` function
3. Click on the "Test" tab
4. Create a new test event with one of the example payloads above
5. Click "Test" to invoke the function
6. Review the execution results and logs

### Testing Locally

You can test the Lambda function locally before deployment:

```python
# test_local.py
from lambda_function import lambda_handler

# Test with valid input
event = {"n": 10}
response = lambda_handler(event, None)
print(response)

# Test with invalid input
event = {"n": -5}
response = lambda_handler(event, None)
print(response)
```

Run the local test:
```bash
python test_local.py
```

## Updating the Lambda Function

To update the Lambda function code:

1. Modify `lambda_function.py`
2. Run `terraform apply` to redeploy

Terraform will automatically:
- Create a new ZIP archive with the updated code
- Update the Lambda function with the new code
- Preserve the existing configuration

## Monitoring and Logs

### CloudWatch Logs

View Lambda function logs using CloudWatch:

```bash
aws logs tail /aws/lambda/fibonacci-generator --follow
```

Or view logs in the AWS Console:
1. Navigate to CloudWatch Logs
2. Find the log group `/aws/lambda/fibonacci-generator`
3. View log streams for function invocations

### Monitoring Managed Instances

Monitor capacity provider and EC2 instances:

```bash
# Check capacity provider status
aws lambda get-capacity-provider --name fibonacci-generator-capacity-provider

# Monitor EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:lambda:capacity-provider,Values=*" \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,CpuOptions.CoreCount]' \
  --output table

# View CloudWatch metrics for capacity provider
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=fibonacci-generator \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Key Metrics to Monitor

- **Capacity Provider State**: Should be `ACTIVE`
- **EC2 Instance Count**: Number of instances running (scales based on CPU)
- **Lambda Invocations**: Number of function invocations
- **Lambda Duration**: Execution time per invocation
- **Lambda Errors**: Error rate and types
- **CPU Utilization**: EC2 instance CPU usage (triggers scaling)

## Destroying the Infrastructure

To remove all deployed resources:

```bash
terraform destroy
```

- Review the resources that will be destroyed
- Type `yes` when prompted to confirm
- Wait for the destruction to complete

This will remove:
- The Lambda function
- The Lambda capacity provider
- EC2 instances managed by Lambda
- The IAM operator role and execution role
- The security group
- All associated resources

**Note:** 
- The S3 bucket used for Terraform state storage will NOT be deleted
- EC2 instances are managed by Lambda and will be terminated automatically
- Ensure no active invocations are running before destroying

## Troubleshooting

### AWS CLI v2 JSON Payload Issues

**Issue:** Error "Could not parse request body into json" or "Unexpected character (CTRL-CHAR, code 159)"

**Solution:** AWS CLI v2 requires the `--cli-binary-format` flag for JSON payloads:
```bash
aws lambda invoke \
  --function-name fibonacci-generator \
  --cli-binary-format raw-in-base64-out \
  --payload '{"n": 10}' \
  response.json
```

Alternatively, use a payload file:
```bash
echo '{"n": 10}' > payload.json
aws lambda invoke \
  --function-name fibonacci-generator \
  --cli-binary-format raw-in-base64-out \
  --payload file://payload.json \
  response.json
```

### Expired AWS Credentials

**Issue:** "The security token included in the request is expired"

**Solution:** Refresh your AWS credentials:
```bash
# For standard credentials
aws configure

# For AWS SSO
aws sso login
```

### Terraform Init Fails

**Issue:** S3 bucket for backend doesn't exist

**Solution:** Ensure the S3 bucket `xxxx` exists in the `us-east-1` region, or update the backend configuration in `main.tf`.

### Lambda Function Invocation Fails

**Issue:** Permission denied or function not found

**Solution:** 
- Verify the function was deployed: `aws lambda list-functions`
- Check your AWS credentials have permission to invoke Lambda functions
- Ensure you're using the correct function name
- Verify capacity provider is in ACTIVE state

### Capacity Provider Not Active

**Issue:** Capacity provider stuck in CREATING or FAILED state

**Solution:**
- Check operator role has correct permissions
- Verify VPC and subnet configurations are valid
- Ensure security group allows outbound traffic
- Review CloudWatch logs for detailed error messages
- Check that subnets have available IP addresses

### EC2 Instances Not Launching

**Issue:** No EC2 instances appear after deployment

**Solution:**
- Wait 5-10 minutes for initial instance provisioning
- Check capacity provider status: `aws lambda get-capacity-provider --name fibonacci-generator-capacity-provider`
- Verify operator role has EC2 permissions
- Check VPC subnet capacity and availability
- Review CloudWatch logs for capacity provider events

### High Costs

**Issue:** Unexpected AWS charges from Managed Instances

**Solution:**
- Check number of running EC2 instances
- Reduce `capacity_provider_max_vcpu` to limit maximum capacity
- Monitor CloudWatch metrics for CPU utilization
- Consider using EC2 Savings Plans or Reserved Instances
- Review scaling policies and adjust if needed

### Timeout Errors

**Issue:** Lambda function times out for large inputs

**Solution:** Increase the timeout value:
```bash
terraform apply -var="timeout=30"
```

## Architecture

### Lambda Managed Instances Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Account                              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Capacity Provider                                   │  │
│  │  - VPC: vpc-0e906eb9a1c35ab3a                       │  │
│  │  - Subnets: Multiple AZs                            │  │
│  │  - Security Group                                    │  │
│  │  - Auto scaling (CPU-based)                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  EC2 Instances (Managed by Lambda)                  │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐    │  │
│  │  │ Instance 1 │  │ Instance 2 │  │ Instance 3 │    │  │
│  │  │  (AZ-1)    │  │  (AZ-2)    │  │  (AZ-3)    │    │  │
│  │  └────────────┘  └────────────┘  └────────────┘    │  │
│  │  Tagged: aws:lambda:capacity-provider              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Lambda Function (fibonacci-generator)              │  │
│  │  - Python 3.13                                       │  │
│  │  - Multi-concurrent execution                        │  │
│  │  - Attached to Capacity Provider                    │  │
│  │  - No cold starts                                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  IAM Roles                                          │  │
│  │  - Execution Role (function permissions)            │  │
│  │  - Operator Role (EC2 management permissions)       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         ▲
         │ managed by
         │
┌────────┴────────┐
│   Terraform     │
│  Configuration  │
└─────────────────┘
```

### Key Components

1. **Capacity Provider**: Defines compute infrastructure for Lambda Managed Instances
2. **EC2 Instances**: Customer-owned instances managed by Lambda service
3. **Lambda Function**: Runs on EC2 instances with multi-concurrent execution
4. **Operator Role**: Grants Lambda permissions to manage EC2 resources
5. **Security Group**: Controls network access for EC2 instances

## Project Structure

```
.
├── lambda_function.py      # Lambda function code (Python 3.13)
├── main.tf                 # Terraform main configuration (with Managed Instances)
├── variables.tf            # Terraform variables (including capacity provider config)
├── outputs.tf              # Terraform outputs (including capacity provider outputs)
├── README.md               # This file
├── IMPORT_GUIDE.md         # Guide for importing existing resources
└── .kiro/
    └── specs/
        ├── fibonacci-lambda/
        │   ├── requirements.md  # Original requirements specification
        │   ├── design.md        # Original design document
        │   └── tasks.md         # Original implementation tasks
        └── lambda-managed-instances-migration/
            ├── requirements.md  # Migration requirements specification
            ├── design.md        # Migration design document
            └── tasks.md         # Migration implementation tasks
```

## Requirements

This implementation satisfies the following requirements:

**Original Lambda Function Requirements:**
- **Requirement 1**: Generate Fibonacci sequences with proper edge case handling
- **Requirement 2**: Comprehensive input validation with clear error messages
- **Requirement 3**: Consistent JSON response format
- **Requirement 4**: AWS Lambda handler interface compliance
- **Requirement 5**: Infrastructure as code with Terraform

**Lambda Managed Instances Migration Requirements:**
- **Requirement 1**: Capacity provider creation with VPC configuration
- **Requirement 2**: IAM operator role with EC2 management permissions
- **Requirement 3**: Lambda function migration to Managed Instances
- **Requirement 4**: Network configuration using existing VPC
- **Requirement 5**: Minimal changes to existing infrastructure
- **Requirement 6**: Terraform best practices and documentation
- **Requirement 7**: Runtime compatibility (Python 3.13)
- **Requirement 8**: State management and deployment safety
- **Requirement 9**: Comprehensive documentation and comments
- **Requirement 10**: Cost optimization considerations

For detailed requirements and design documentation, see:
- Original spec: `.kiro/specs/fibonacci-lambda/`
- Migration spec: `.kiro/specs/lambda-managed-instances-migration/`

## Additional Resources

- [AWS Lambda Managed Instances Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Capacity Providers Guide](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-capacity-providers.html)
- [Multi-Concurrency Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-multi-concurrency.html)
- [Monitoring Managed Instances](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-monitoring.html)
- [Terraform AWS Provider - Lambda Capacity Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_capacity_provider)
- [Python 3.13 Runtime for Lambda](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-python-runtime.html)

## License

This project is provided as-is for demonstration purposes.
