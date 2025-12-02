"""
Secure Command Parser for Chat Control
Implements strict command validation with allowlisting and input sanitization.

Security Features:
- Command allowlisting to prevent unauthorized operations
- Input validation and sanitization 
- Argument parsing with type checking
- Length and complexity limits
- Pattern matching for security
- Comprehensive logging of parse attempts
"""

import re
import logging
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Union
import html
import shlex

import structlog

logger = structlog.get_logger()


class CommandValidationError(Exception):
    """Raised when command validation fails."""
    pass


@dataclass
class ParsedCommand:
    """Represents a parsed and validated command."""
    command: str
    args: List[str]
    raw_command: str
    metadata: Dict[str, Any]


class SecureCommandParser:
    """
    Secure command parser with comprehensive validation.
    
    Implements defense-in-depth for command parsing:
    - Allowlist-based command validation
    - Input sanitization and length limits
    - Argument validation with type checking
    - Pattern-based security filtering
    - Comprehensive audit logging
    """
    
    # Command patterns with validation rules
    COMMAND_PATTERNS = {
        'start-agent': {
            'pattern': r'^!start-agent\s+([a-zA-Z0-9-_]+)(?:\s+(.*))?$',
            'min_args': 1,
            'max_args': 2,
            'arg_patterns': [
                r'^[a-zA-Z0-9-_]{1,50}$',  # Agent type: alphanumeric, hyphens, underscores
                r'^[a-zA-Z0-9=,\s-_]{0,200}$'  # Optional config: limited chars
            ],
            'description': 'Start an agent service'
        },
        'stop-agent': {
            'pattern': r'^!stop-agent\s+([a-zA-Z0-9-_]+)$',
            'min_args': 1,
            'max_args': 1,
            'arg_patterns': [
                r'^[a-zA-Z0-9-_]{1,50}$'  # Agent type
            ],
            'description': 'Stop an agent service'
        },
        'status-agent': {
            'pattern': r'^!status-agent\s+([a-zA-Z0-9-_]+)$',
            'min_args': 1,
            'max_args': 1,
            'arg_patterns': [
                r'^[a-zA-Z0-9-_]{1,50}$'  # Agent type
            ],
            'description': 'Get agent service status'
        },
        'list-agents': {
            'pattern': r'^!list-agents(?:\s+([a-zA-Z0-9-_]+))?$',
            'min_args': 0,
            'max_args': 1,
            'arg_patterns': [
                r'^[a-zA-Z0-9-_]{1,20}$'  # Optional filter
            ],
            'description': 'List available agents'
        },
        'help': {
            'pattern': r'^!help(?:\s+([a-zA-Z0-9-_]+))?$',
            'min_args': 0,
            'max_args': 1,
            'arg_patterns': [
                r'^[a-zA-Z0-9-_]{1,20}$'  # Optional command name
            ],
            'description': 'Show help information'
        }
    }
    
    # Security patterns to reject
    DANGEROUS_PATTERNS = [
        r'[;&|`$(){}[\]\\]',  # Shell metacharacters
        r'\.\.',              # Directory traversal (basic)
        r'\.\..*\/',          # Path traversal with forward slash
        r'\.\..*\\',          # Path traversal with backslash
        r'/[a-zA-Z]',         # Absolute paths
        r'<[^>]*>',           # HTML/XML tags
        r'javascript:',       # JavaScript URLs
        r'<script.*?>',       # Script tags for XSS
        r'data:',             # Data URLs
        r'file://',           # File URLs
        r'\\x[0-9a-fA-F]{2}', # Hex escape sequences
        r'%[0-9a-fA-F]{2}',   # URL encoding
        r'\r|\n',             # Line breaks
        r'[\x00-\x1f\x7f-\x9f]',  # Control characters
    ]
    
    def __init__(self, allowed_commands: Optional[List[str]] = None):
        """
        Initialize the secure command parser.
        
        Args:
            allowed_commands: List of allowed command names. If None, all defined commands are allowed.
        """
        self.log = logger.bind(component="command_parser")
        
        # Set allowed commands (default to all if not specified)
        if allowed_commands is None:
            self.allowed_commands = set(self.COMMAND_PATTERNS.keys())
        else:
            self.allowed_commands = set(allowed_commands)
            
            # Validate that allowed commands exist in patterns
            unknown_commands = self.allowed_commands - set(self.COMMAND_PATTERNS.keys())
            if unknown_commands:
                raise CommandValidationError(f"Unknown commands in allowed list: {unknown_commands}")
        
        self.log.info("Command parser initialized", 
                     allowed_commands=list(self.allowed_commands))
        
        # Compile dangerous patterns for performance
        self.compiled_dangerous_patterns = [
            re.compile(pattern, re.IGNORECASE | re.MULTILINE)
            for pattern in self.DANGEROUS_PATTERNS
        ]
    
    def parse_command(self, command_text: str) -> ParsedCommand:
        """
        Parse and validate a command with comprehensive security checks.
        
        Args:
            command_text: Raw command text from Matrix message
            
        Returns:
            ParsedCommand: Validated command object
            
        Raises:
            CommandValidationError: If validation fails
        """
        original_command = command_text
        self.log.debug("Parsing command", command=command_text[:100])
        
        try:
            # 1. Basic validation
            command_text = self._basic_validation(command_text)
            
            # 2. Security pattern checking
            self._check_dangerous_patterns(command_text)
            
            # 3. Parse command structure
            command, args = self._parse_structure(command_text)
            
            # 4. Validate command is allowed
            if command not in self.allowed_commands:
                raise CommandValidationError(f"Command not allowed: {command}")
            
            # 5. Pattern-based validation
            self._validate_command_pattern(command, args, command_text)
            
            # 6. Argument validation
            validated_args = self._validate_arguments(command, args)
            
            # 7. Create parsed command object
            parsed_command = ParsedCommand(
                command=command,
                args=validated_args,
                raw_command=original_command,
                metadata={
                    'parsed_at': self._get_timestamp(),
                    'validation_passed': True,
                    'arg_count': len(validated_args)
                }
            )
            
            self.log.info("Command parsed successfully", 
                         command=command, 
                         arg_count=len(validated_args))
            
            return parsed_command
            
        except CommandValidationError as e:
            self.log.warning("Command validation failed", 
                           error=str(e),
                           command=command_text[:100])
            raise
        
        except Exception as e:
            self.log.error("Unexpected error in command parsing", 
                          error=str(e),
                          command=command_text[:100])
            raise CommandValidationError(f"Command parsing failed: {str(e)}")
    
    def _basic_validation(self, command_text: str) -> str:
        """Perform basic command validation and sanitization."""
        # Check length limits
        if len(command_text) > 1000:
            raise CommandValidationError("Command too long (max 1000 characters)")
        
        if not command_text.strip():
            raise CommandValidationError("Empty command")
        
        # Must start with !
        if not command_text.strip().startswith('!'):
            raise CommandValidationError("Commands must start with !")
        
        # Basic HTML escaping to prevent XSS if command is logged
        command_text = html.escape(command_text.strip())
        
        # Remove excessive whitespace
        command_text = re.sub(r'\s+', ' ', command_text)
        
        return command_text
    
    def _check_dangerous_patterns(self, command_text: str) -> None:
        """Check for dangerous patterns in command text."""
        for pattern in self.compiled_dangerous_patterns:
            if pattern.search(command_text):
                raise CommandValidationError(f"Dangerous pattern detected: {pattern.pattern}")
    
    def _parse_structure(self, command_text: str) -> tuple[str, List[str]]:
        """Parse command structure into command and arguments."""
        try:
            # Use shlex for proper argument parsing
            parts = shlex.split(command_text)
        except ValueError as e:
            raise CommandValidationError(f"Invalid command syntax: {str(e)}")
        
        if not parts:
            raise CommandValidationError("Empty command")
        
        # Extract command (remove ! prefix)
        command = parts[0][1:].lower()  # Remove ! and normalize case
        args = parts[1:]
        
        return command, args
    
    def _validate_command_pattern(self, command: str, args: List[str], full_command: str) -> None:
        """Validate command matches expected pattern."""
        if command not in self.COMMAND_PATTERNS:
            raise CommandValidationError(f"Unknown command: {command}")
        
        pattern_info = self.COMMAND_PATTERNS[command]
        pattern = re.compile(pattern_info['pattern'], re.IGNORECASE)
        
        if not pattern.match(full_command):
            raise CommandValidationError(f"Command syntax error for {command}")
        
        # Validate argument count
        min_args = pattern_info['min_args']
        max_args = pattern_info['max_args']
        
        if len(args) < min_args:
            raise CommandValidationError(f"Too few arguments for {command} (min: {min_args})")
        
        if len(args) > max_args:
            raise CommandValidationError(f"Too many arguments for {command} (max: {max_args})")
    
    def _validate_arguments(self, command: str, args: List[str]) -> List[str]:
        """Validate and sanitize command arguments."""
        pattern_info = self.COMMAND_PATTERNS[command]
        arg_patterns = pattern_info.get('arg_patterns', [])
        validated_args = []
        
        for i, arg in enumerate(args):
            # Check if we have a pattern for this argument
            if i < len(arg_patterns):
                pattern = re.compile(arg_patterns[i])
                if not pattern.match(arg):
                    raise CommandValidationError(
                        f"Invalid argument {i+1} for {command}: {arg}"
                    )
            
            # Additional sanitization
            sanitized_arg = self._sanitize_argument(arg)
            validated_args.append(sanitized_arg)
        
        return validated_args
    
    def _sanitize_argument(self, arg: str) -> str:
        """Sanitize individual argument."""
        # Remove any null bytes
        arg = arg.replace('\x00', '')
        
        # Limit length
        if len(arg) > 200:
            raise CommandValidationError(f"Argument too long: {arg[:50]}...")
        
        # Basic sanitization
        arg = arg.strip()
        
        return arg
    
    def _get_timestamp(self) -> float:
        """Get current timestamp."""
        import time
        return time.time()
    
    def get_allowed_commands(self) -> Dict[str, str]:
        """Get dictionary of allowed commands and their descriptions."""
        return {
            cmd: self.COMMAND_PATTERNS[cmd]['description']
            for cmd in self.allowed_commands
            if cmd in self.COMMAND_PATTERNS
        }
    
    def get_command_help(self, command: str) -> Optional[Dict[str, Any]]:
        """Get help information for a specific command."""
        if command not in self.allowed_commands or command not in self.COMMAND_PATTERNS:
            return None
        
        pattern_info = self.COMMAND_PATTERNS[command]
        
        return {
            'command': command,
            'description': pattern_info['description'],
            'min_args': pattern_info['min_args'],
            'max_args': pattern_info['max_args'],
            'pattern': pattern_info['pattern'],
            'usage': self._generate_usage(command, pattern_info)
        }
    
    def _generate_usage(self, command: str, pattern_info: Dict[str, Any]) -> str:
        """Generate usage string for a command."""
        # Simple usage generation based on min/max args
        base = f"!{command}"
        
        min_args = pattern_info['min_args']
        max_args = pattern_info['max_args']
        
        if command == 'start-agent':
            return f"{base} <agent-type> [config]"
        elif command == 'stop-agent':
            return f"{base} <agent-type>"
        elif command == 'status-agent':
            return f"{base} <agent-type>"
        elif command == 'list-agents':
            return f"{base} [filter]"
        elif command == 'help':
            return f"{base} [command]"
        else:
            # Generic usage based on arg count
            if min_args == 0 and max_args == 0:
                return base
            elif min_args == max_args:
                args_str = ' '.join([f"<arg{i+1}>" for i in range(min_args)])
                return f"{base} {args_str}"
            else:
                required_args = ' '.join([f"<arg{i+1}>" for i in range(min_args)])
                optional_args = ' '.join([f"[arg{i+1}]" for i in range(min_args, max_args)])
                return f"{base} {required_args} {optional_args}".strip()
    
    def validate_agent_name(self, agent_name: str) -> bool:
        """Validate agent name format."""
        if not agent_name:
            return False
        
        # Must be alphanumeric with hyphens/underscores only
        pattern = re.compile(r'^[a-zA-Z0-9-_]{1,50}$')
        return bool(pattern.match(agent_name))


# Security testing utilities
class CommandParserSecurityTester:
    """Utility class for security testing the command parser."""
    
    @staticmethod
    def generate_malicious_inputs() -> List[str]:
        """Generate list of malicious inputs for testing."""
        return [
            "!start-agent; rm -rf /",
            "!start-agent `whoami`",
            "!start-agent $(cat /etc/passwd)",
            "!start-agent agent & sleep 10",
            "!start-agent ../../../etc/passwd",
            "!start-agent <script>alert('xss')</script>",
            "!start-agent javascript:alert('xss')",
            "!start-agent data:text/html,<script>alert('xss')</script>",
            "!start-agent file:///etc/passwd",
            "!start-agent agent\\x2E\\x2E/passwd",
            "!start-agent agent%2E%2E/passwd",
            "!start-agent agent\r\ncat /etc/passwd",
            "!start-agent agent\x00cat /etc/passwd",
            "!" + "A" * 2000,  # Very long command
            "!start-agent " + "A" * 1000,  # Very long argument
            "!nonexistent-command arg",
            "start-agent no-exclamation",  # Missing !
            "!start-agent",  # Missing required arg
            "!stop-agent arg1 arg2 arg3",  # Too many args
        ]
    
    @staticmethod
    def test_parser_security(parser: SecureCommandParser) -> Dict[str, Any]:
        """Test parser against malicious inputs."""
        malicious_inputs = CommandParserSecurityTester.generate_malicious_inputs()
        results = {
            'total_tests': len(malicious_inputs),
            'blocked': 0,
            'passed': 0,
            'failed_to_block': []
        }
        
        for malicious_input in malicious_inputs:
            try:
                parser.parse_command(malicious_input)
                # If we get here, the parser didn't block the malicious input
                results['passed'] += 1
                results['failed_to_block'].append(malicious_input)
            except CommandValidationError:
                # Good - the parser blocked the malicious input
                results['blocked'] += 1
            except Exception as e:
                # Unexpected error - might indicate a bug
                results['failed_to_block'].append(f"{malicious_input} -> {str(e)}")
        
        return results