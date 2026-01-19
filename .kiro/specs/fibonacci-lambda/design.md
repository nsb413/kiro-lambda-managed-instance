# Design Document: Fibonacci Lambda Function

## Overview

This design specifies a Python-based AWS Lambda function that generates Fibonacci sequences. The function will be deployed using Terraform as infrastructure as code, providing a repeatable and version-controlled deployment process. The Lambda function accepts a number as input via direct invocation and returns the Fibonacci sequence up to that position, with comprehensive input validation and error handling.

## Architecture

The solution consists of two main components:

1. **Lambda Function**: Python 3.11 runtime executing the Fibonacci generation logic
2. **Infrastructure as Code**: Terraform configuration for deploying all AWS resources

### Deployment Architecture

```
┌─────────────────┐
│   Terraform     │
│  Configuration  │
└────────┬────────┘
         │ deploys
         ▼
┌─────────────────────────────────────┐
│         AWS Account                 │
│                                     │
│  ┌──────────────┐                  │
│  │   Lambda     │                  │
│  │  Function    │                  │
│  │  (Python)    │                  │
│  └──────┬───────┘                  │
│         │                           │
│  ┌──────▼───────┐                  │
│  │  IAM Role    │                  │
│  │ & Policies   │                  │
│  └──────────────┘                  │
└─────────────────────────────────────┘
```

## Components and Interfaces

### 1. Lambda Handler Function

**File**: `lambda_function.py`

**Handler**: `lambda_handler(event, context)`

The handler function follows AWS Lambda conventions by accepting two parameters:
- `event`: Dictionary containing the invocation event data
- `context`: Runtime information provided by AWS Lambda

This design decision ensures seamless integration with AWS Lambda service and compatibility with standard Lambda invocation patterns.

**Input Event Structure**:
```python
{
    "n": 10  # Direct invocation
}
```

**Output Structure** (Success):
```python
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json"
    },
    "body": "{\"n\": 10, \"sequence\": [0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55]}"
}
```

**Output Structure** (Error):
```python
{
    "statusCode": 400,  # or 500 for server errors
    "headers": {
        "Content-Type": "application/json"
    },
    "body": "{\"error\": \"Input must be a non-negative integer\"}"
}
```

### 2. Core Functions

#### `generate_fibonacci(n: int) -> list[int]`
Generates the Fibonacci sequence up to position n.

**Parameters**:
- `n`: Non-negative integer representing the position in the sequence

**Returns**: List of integers representing the Fibonacci sequence

**Algorithm**:
- For n = 0: return [0]
- For n = 1: return [0, 1]
- For n > 1: iteratively calculate each number as the sum of the previous two

#### `validate_input(n: any) -> tuple[bool, str]`
Validates the input parameter.

**Parameters**:
- `n`: The input value to validate

**Returns**: Tuple of (is_valid: bool, error_message: str)

**Validation Rules**:
- Must not be None
- Must be an integer (or convertible to integer)
- Must be non-negative
- Must not exceed 1000 (to prevent excessive computation)

#### `parse_event(event: dict) -> any`
Extracts the input number from the Lambda event object.

**Parameters**:
- `event`: The Lambda event dictionary

**Returns**: The extracted input value (may be None if not found)

**Logic**:
- Extract value from `event.get('n')`
- Return None if not found

### 3. Infrastructure Components (Terraform)

**File**: `main.tf`

**Backend Configuration**:
Terraform state will be stored remotely in S3 for team collaboration and state locking:
- **S3 Bucket**: `xxxxxx`
- **Region**: `us-east-1`
- **Key**: `fibonacci-lambda/terraform.tfstate`
- **Design Rationale**: Remote state storage enables team collaboration, provides state history, and prevents concurrent modifications. Using S3 in us-east-1 ensures low latency and high availability.

**Resources**:

1. **IAM Role** (`aws_iam_role.lambda_role`)
   - Assume role policy for Lambda service
   - Attached policy: `AWSLambdaBasicExecutionRole` for CloudWatch Logs
   - **Design Rationale**: Follows AWS best practices by granting minimal permissions needed for Lambda execution and CloudWatch logging

2. **Lambda Function** (`aws_lambda_function.fibonacci`)
   - Runtime: `python3.11`
   - Handler: `lambda_function.lambda_handler`
   - Memory: 128 MB (configurable via variable)
   - Timeout: 10 seconds (configurable via variable)
   - Source code: ZIP archive of Python file
   - **Design Rationale**: Python 3.11 provides modern language features and performance improvements; configurable memory and timeout allow optimization based on actual usage patterns

**Variables**:
- `function_name`: Name of the Lambda function (default: "fibonacci-generator")
- `memory_size`: Memory allocation in MB (default: 128)
- `timeout`: Function timeout in seconds (default: 10)

**Outputs**:
- `lambda_function_arn`: ARN of the deployed Lambda function
- `lambda_function_name`: Name of the Lambda function

**Deployment Process**:
The infrastructure supports standard Terraform workflow commands:
- `terraform init`: Initialize the working directory and configure S3 backend
- `terraform plan`: Preview changes before applying
- `terraform apply`: Deploy or update the Lambda function and associated resources
- `terraform destroy`: Remove all deployed resources

**Design Rationale**: Using Terraform as the IaC tool provides version control, repeatability, and declarative infrastructure management. The configuration is designed to be idempotent, allowing safe re-application for updates.

## Data Models

### Input Model
```python
{
    "n": int  # Position in Fibonacci sequence (0 to 1000)
}
```

### Success Response Model
```python
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json"
    },
    "body": str  # JSON string containing:
                 # {"n": int, "sequence": list[int]}
}
```

### Error Response Model
```python
{
    "statusCode": int,  # 400 for client errors
    "headers": {
        "Content-Type": "application/json"
    },
    "body": str  # JSON string containing:
                 # {"error": str}
}
```


## Correctness Properties

A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.

### Property 1: Fibonacci Mathematical Property

*For any* valid input number n (where 0 ≤ n ≤ 1000), the generated sequence should satisfy the Fibonacci recurrence relation: for all positions i > 1 in the sequence, sequence[i] = sequence[i-1] + sequence[i-2], and the sequence should have exactly n+1 elements starting with [0, 1, ...].

**Validates: Requirements 1.1, 1.4**

### Property 2: Valid Response Structure

*For any* valid input number n, the Lambda function response should have statusCode 200, contain headers with "Content-Type": "application/json", and the parsed body should contain both the original input n and a sequence array. The response must be a properly formatted dictionary compatible with AWS Lambda's response format.

**Validates: Requirements 3.1, 4.3**

### Property 3: Invalid Input Rejection

*For any* invalid input (non-integer, negative integer, integer > 1000, or missing input), the Lambda function should return a response with statusCode 400, appropriate headers, and a body containing an error message.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 3.2**

### Property 4: Event Format Compatibility

*For any* valid input number n, when provided in the direct invocation event format {"n": n}, the Lambda function should successfully extract the input and produce the correct Fibonacci sequence.

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 5: Response Headers Presence

*For any* input (valid or invalid), the Lambda function response should always include a headers dictionary containing at minimum the "Content-Type" key.

**Validates: Requirements 3.3**

## Error Handling

### Input Validation Errors

The function implements comprehensive input validation with specific error messages:

1. **Missing Input**: "Input parameter 'n' is required"
2. **Non-Integer Input**: "Input must be an integer"
3. **Negative Input**: "Input must be a non-negative integer"
4. **Exceeds Limit**: "Input must not exceed 1000"

All validation errors return HTTP status code 400 with a JSON body containing the error message.

### Lambda Execution Errors

Unexpected errors during execution are caught and returned with:
- Status code: 500
- Error message: Generic internal error message (specific details logged to CloudWatch)

### Infrastructure Errors

Terraform deployment errors are handled through:
- Validation of required variables
- Proper error messages for missing dependencies
- State management for rollback capability

## Testing Strategy

The testing strategy employs both unit tests and property-based tests to ensure comprehensive coverage.

### Property-Based Testing

We will use **Hypothesis** (Python's property-based testing library) to validate the correctness properties defined above. Each property test will run a minimum of 100 iterations with randomly generated inputs.

**Property Test Configuration**:
- Library: Hypothesis
- Minimum iterations: 100 per test
- Test file: `test_lambda_function.py`

**Property Tests**:

1. **Test Fibonacci Mathematical Property**
   - Tag: **Feature: fibonacci-lambda, Property 1: Fibonacci Mathematical Property**
   - Generate random integers n (0 ≤ n ≤ 1000)
   - Verify sequence length is n+1
   - Verify first two elements are [0] or [0, 1]
   - Verify recurrence relation for all i > 1

2. **Test Valid Response Structure**
   - Tag: **Feature: fibonacci-lambda, Property 2: Valid Response Structure**
   - Generate random valid integers n
   - Verify response has correct structure and status code

3. **Test Invalid Input Rejection**
   - Tag: **Feature: fibonacci-lambda, Property 3: Invalid Input Rejection**
   - Generate random invalid inputs (strings, floats, negative numbers, numbers > 1000, None)
   - Verify all return status code 400 with error messages

4. **Test Event Format Compatibility**
   - Tag: **Feature: fibonacci-lambda, Property 4: Event Format Compatibility**
   - Generate random valid integers n
   - Test direct invocation event format
   - Verify correct sequence results

5. **Test Response Headers Presence**
   - Tag: **Feature: fibonacci-lambda, Property 5: Response Headers Presence**
   - Generate random inputs (valid and invalid)
   - Verify headers dictionary exists and contains Content-Type

### Unit Testing

Unit tests complement property tests by verifying specific examples and edge cases:

**Edge Cases**:
- n = 0 returns [0] (Requirements 1.2)
- n = 1 returns [0, 1] (Requirements 1.3)
- Missing input parameter (Requirements 2.1)

**Integration Tests**:
- Full Lambda handler invocation with various event formats
- Response serialization and deserialization

**Infrastructure Tests**:
- Terraform validation (`terraform validate`)
- Terraform plan verification
- Post-deployment smoke tests (optional)

### Test Execution

Unit tests and property tests should be run together:
```bash
pytest test_lambda_function.py -v
```

Infrastructure validation:
```bash
terraform validate
terraform plan
```
