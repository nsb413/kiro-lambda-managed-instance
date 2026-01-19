# Lambda Managed Instances Migration - Technical Reference

**Quick Reference Guide for Troubleshooting and Commands**

---

## Critical Issues and Solutions

### Issue 1: Wrong IAM Policy Name

**Error:**
```
NoSuchEntity: Policy arn:aws:iam::aws:policy/service-role/AWSLambdaManagedInstancesOperatorRole does not exist
```

**Solution:**
```hcl
# Wrong
policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaManagedInstancesOperatorRole"

# Correct
policy_arn = "arn:aws:iam::aws:policy/AWSLambdaManagedEC2ResourceOperator"
```

---

### Issue 2: Architecture Case Sensitivity

**Error:**
```
ValidationException: Value '[X86_64]' at 'instanceRequirements.architectures' 
failed to satisfy constraint: [Member must satisfy enum value set: [x86_64, arm64]]
```

**Solution:**
```hcl
# Wrong
architectures = ["X86_64"]

# Correct
architectures = ["x86_64"]
```

---

### Issue 3: Scaling Policies with Auto Mode

**Error:**
```
InvalidParameterValueException: A scaling policy can't be specified when 
the scalingMode is set to Auto
```

**Solution:**
```hcl
# Terraform provider requires the field but it must be null
capacity_provider_scaling_config = [{
  scaling_mode     = "Auto"
  max_vcpu_count   = 16
  scaling_policies = null  # Must be null, not [] or omitted
}]
```

---

### Issue 4: Function Cannot Be Updated In-Place

**Error:**
```
InvalidParameterValueException: CapacityProviderConfig isn't supported 
for Lambda Default functions
```

**Solution:**
```bash
# Delete and recreate the function
aws lambda delete-function --function-name fibonacci-generator
terraform apply
```

---

### Issue 5: Minimum Memory Requirement

**Error:**
```
ValidationException: Lambda Managed Instance functions must have memory 
size greater than or equal to 2048
```

**Solution:**
```hcl
memory_size = 2048  # Minimum required (was 128)
```

---

## Command Reference

### Validation Commands
```bash
terraform fmt
terraform validate
terraform plan -out=tfplan
```

### Deployment Commands
```bash
# Apply saved plan
terraform apply "tfplan"

# Force function recreation
terraform apply -replace="aws_lambda_function.fibonacci"

# Manual function deletion
aws lambda delete-function --function-name fibonacci-generator
```

### Verification Commands
```bash
# Check function configuration
aws lambda get-function --function-name fibonacci-generator \
  --query 'Configuration.[Runtime,MemorySize,Version]' \
  --output json

# Check EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:lambda:capacity-provider,Values=fibonacci-generator-capacity-provider" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]' \
  --output table

# Test function
aws lambda invoke \
  --function-name fibonacci-generator \
  --payload '{"n": 10}' \
  --cli-binary-format raw-in-base64-out \
  response.json
```

---

## Configuration Requirements

### Lambda Managed Instances Minimums
- **Memory:** ≥ 2048 MB
- **Runtime:** Python 3.13+, Node.js 22+, Java 21+, or .NET 8+
- **Publish:** Must be `true`
- **VPC:** Private subnets with NAT Gateway or VPC endpoints

### Terraform Configuration
```hcl
# Required provider version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0"
    }
  }
}

# Correct policy
resource "aws_iam_role_policy_attachment" "operator_policy" {
  role       = aws_iam_role.capacity_provider_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaManagedEC2ResourceOperator"
}

# Correct architecture
instance_requirements = [{
  architectures = ["x86_64"]  # lowercase
}]

# Correct scaling config
capacity_provider_scaling_config = [{
  scaling_mode     = "Auto"
  max_vcpu_count   = 16
  scaling_policies = null  # null, not []
}]
```

---

## Deployment Checklist

### Pre-Deployment
- [ ] VPC has private subnets across multiple AZs
- [ ] NAT Gateway or VPC endpoints configured
- [ ] Sufficient subnet IP addresses available
- [ ] Function code tested with Python 3.13

### During Deployment
- [ ] Run `terraform validate`
- [ ] Review `terraform plan` output
- [ ] Verify 4 resources to add, 1 to change, 0 to destroy
- [ ] Apply changes
- [ ] Monitor for errors

### Post-Deployment
- [ ] Verify function runtime is Python 3.13
- [ ] Verify memory is 2048 MB
- [ ] Test function invocation
- [ ] Check EC2 instances launch (after first invocation)
- [ ] Verify multi-AZ distribution

---

## Resources Created

- Security Group: `sg-xxxxxxxxxxxxxxxxx`
- IAM Operator Role: `fibonacci-generator-cp-operator-YYYYMMDDHHMMSS`
- IAM Policy Attachment: `AWSLambdaManagedEC2ResourceOperator`
- Lambda Capacity Provider: `fibonacci-generator-capacity-provider`
- Lambda Function: `fibonacci-generator` (recreated)

---

## Quick Reference Links

- [AWS Lambda Managed Instances Docs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Operator Role Permissions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances-operator-role.html)
- [AWSLambdaManagedEC2ResourceOperator Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSLambdaManagedEC2ResourceOperator.html)
- [Capacity Provider API](https://docs.aws.amazon.com/lambda/latest/api/API_CapacityProviderScalingConfig.html)
