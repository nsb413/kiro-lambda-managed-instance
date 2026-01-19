def validate_input(n: any) -> tuple[bool, str]:
    """
    Validate the input parameter.
    
    Args:
        n: The input value to validate
        
    Returns:
        Tuple of (is_valid: bool, error_message: str)
        If valid, error_message will be an empty string
        
    Validation Rules:
        - Must not be None
        - Must be an integer (or convertible to integer)
        - Must be non-negative
        - Must not exceed 1000
    """
    # Check for None/missing input
    if n is None:
        return (False, "Input parameter 'n' is required")
    
    # Check for non-integer types
    if not isinstance(n, int):
        # Try to convert to int if it's a numeric type
        if isinstance(n, float):
            return (False, "Input must be an integer")
        if isinstance(n, str):
            return (False, "Input must be an integer")
        return (False, "Input must be an integer")
    
    # Check for negative values
    if n < 0:
        return (False, "Input must be a non-negative integer")
    
    # Check for values exceeding 1000
    if n > 1000:
        return (False, "Input must not exceed 1000")
    
    # Input is valid
    return (True, "")


def generate_fibonacci(n: int) -> list[int]:
    """
    Generate Fibonacci sequence up to position n.
    
    Args:
        n: Non-negative integer representing the position in the sequence
        
    Returns:
        List of integers representing the Fibonacci sequence
        
    Examples:
        generate_fibonacci(0) -> [0]
        generate_fibonacci(1) -> [0, 1]
        generate_fibonacci(5) -> [0, 1, 1, 2, 3, 5]
    """
    # Handle edge case: n = 0
    if n == 0:
        return [0]
    
    # Handle edge case: n = 1
    if n == 1:
        return [0, 1]
    
    # For n > 1, iteratively calculate the sequence
    sequence = [0, 1]
    for i in range(2, n + 1):
        next_value = sequence[i - 1] + sequence[i - 2]
        sequence.append(next_value)
    
    return sequence


def parse_event(event: dict) -> any:
    """
    Extract the input number from the Lambda event object.
    
    Args:
        event: The Lambda event dictionary
        
    Returns:
        The extracted input value (may be None if not found)
    """
    return event.get('n')


def lambda_handler(event, context):
    """
    AWS Lambda handler function for Fibonacci sequence generation.
    
    Args:
        event: Dictionary containing the invocation event data
        context: Runtime information provided by AWS Lambda
        
    Returns:
        Dictionary with statusCode, headers, and body (JSON string)
    """
    import json
    
    try:
        # Extract input from event
        n = parse_event(event)
        
        # Validate input
        is_valid, error_message = validate_input(n)
        
        if not is_valid:
            # Return error response with status code 400
            return {
                "statusCode": 400,
                "headers": {
                    "Content-Type": "application/json"
                },
                "body": json.dumps({"error": error_message})
            }
        
        # Generate Fibonacci sequence
        sequence = generate_fibonacci(n)
        
        # Return success response with status code 200
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "n": n,
                "sequence": sequence
            })
        }
        
    except Exception as e:
        # Handle unexpected errors with status code 500
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({"error": "Internal server error"})
        }
