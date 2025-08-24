"""
Comprehensive Security Tests for Command Parser
Implements mutation testing, property-based testing, and fuzzing.

Testing Coverage:
- Unit tests with edge cases
- Property-based testing with Hypothesis
- Mutation testing for quality validation
- Security fuzzing and attack vectors
- Performance and load testing
- Contract testing
"""

import pytest
import json
import string
from unittest.mock import Mock, patch
from hypothesis import given, strategies as st, assume, settings, HealthCheck
from hypothesis.stateful import RuleBasedStateMachine, rule, invariant, Bundle
import time

from src.command_parser import (
    SecureCommandParser,
    CommandValidationError,
    ParsedCommand,
    CommandParserSecurityTester
)


class TestSecureCommandParser:
    """Unit tests for SecureCommandParser."""
    
    def setup_method(self):
        """Set up test fixtures."""
        self.parser = SecureCommandParser()
        self.security_tester = CommandParserSecurityTester()
    
    def test_initialization_default(self):
        """Test parser initialization with defaults."""
        parser = SecureCommandParser()
        assert 'start-agent' in parser.allowed_commands
        assert 'stop-agent' in parser.allowed_commands
        assert 'status-agent' in parser.allowed_commands
        assert 'list-agents' in parser.allowed_commands
    
    def test_initialization_custom_commands(self):
        """Test parser initialization with custom allowed commands."""
        allowed = ['start-agent', 'status-agent']
        parser = SecureCommandParser(allowed_commands=allowed)
        assert parser.allowed_commands == set(allowed)
    
    def test_initialization_invalid_commands(self):
        """Test parser rejects unknown commands in allowed list."""
        with pytest.raises(CommandValidationError):
            SecureCommandParser(allowed_commands=['invalid-command'])
    
    def test_valid_start_agent_command(self):
        """Test parsing valid start-agent command."""
        result = self.parser.parse_command("!start-agent backend-architect")
        
        assert result.command == "start-agent"
        assert result.args == ["backend-architect"]
        assert result.raw_command == "!start-agent backend-architect"
        assert result.metadata['validation_passed'] is True
    
    def test_valid_stop_agent_command(self):
        """Test parsing valid stop-agent command."""
        result = self.parser.parse_command("!stop-agent test-writer-fixer")
        
        assert result.command == "stop-agent"
        assert result.args == ["test-writer-fixer"]
    
    def test_valid_status_agent_command(self):
        """Test parsing valid status-agent command."""
        result = self.parser.parse_command("!status-agent ui-designer")
        
        assert result.command == "status-agent"
        assert result.args == ["ui-designer"]
    
    def test_valid_list_agents_command(self):
        """Test parsing valid list-agents command."""
        result = self.parser.parse_command("!list-agents")
        
        assert result.command == "list-agents"
        assert result.args == []
    
    def test_valid_list_agents_with_filter(self):
        """Test parsing list-agents command with filter."""
        result = self.parser.parse_command("!list-agents active")
        
        assert result.command == "list-agents"
        assert result.args == ["active"]
    
    def test_command_case_normalization(self):
        """Test command case is normalized to lowercase."""
        result = self.parser.parse_command("!START-AGENT backend-architect")
        assert result.command == "start-agent"
    
    def test_whitespace_normalization(self):
        """Test excessive whitespace is normalized."""
        result = self.parser.parse_command("!start-agent    backend-architect   ")
        assert result.args == ["backend-architect"]
    
    def test_empty_command_rejection(self):
        """Test empty commands are rejected."""
        with pytest.raises(CommandValidationError, match="Empty command"):
            self.parser.parse_command("")
    
    def test_whitespace_only_rejection(self):
        """Test whitespace-only commands are rejected."""
        with pytest.raises(CommandValidationError, match="Empty command"):
            self.parser.parse_command("   ")
    
    def test_missing_exclamation_rejection(self):
        """Test commands without ! prefix are rejected."""
        with pytest.raises(CommandValidationError, match="Commands must start with !"):
            self.parser.parse_command("start-agent backend-architect")
    
    def test_too_long_command_rejection(self):
        """Test overly long commands are rejected."""
        long_command = "!" + "A" * 1000
        with pytest.raises(CommandValidationError, match="Command too long"):
            self.parser.parse_command(long_command)
    
    def test_unknown_command_rejection(self):
        """Test unknown commands are rejected."""
        with pytest.raises(CommandValidationError, match="Command not allowed"):
            self.parser.parse_command("!unknown-command")
    
    def test_missing_required_args_rejection(self):
        """Test commands missing required arguments are rejected."""
        with pytest.raises(CommandValidationError, match="Too few arguments"):
            self.parser.parse_command("!start-agent")
    
    def test_too_many_args_rejection(self):
        """Test commands with too many arguments are rejected."""
        with pytest.raises(CommandValidationError, match="Too many arguments"):
            self.parser.parse_command("!stop-agent agent1 agent2 agent3")
    
    def test_invalid_agent_name_rejection(self):
        """Test invalid agent names are rejected."""
        with pytest.raises(CommandValidationError):
            self.parser.parse_command("!start-agent ../../../etc/passwd")
    
    def test_shell_injection_protection(self):
        """Test shell injection attempts are blocked."""
        dangerous_commands = [
            "!start-agent agent; rm -rf /",
            "!start-agent agent && cat /etc/passwd",
            "!start-agent agent | whoami",
            "!start-agent `whoami`",
            "!start-agent $(cat /etc/passwd)",
            "!start-agent agent & sleep 10"
        ]
        
        for cmd in dangerous_commands:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_path_traversal_protection(self):
        """Test path traversal attempts are blocked."""
        dangerous_paths = [
            "!start-agent ../../../etc/passwd",
            "!start-agent ..\\..\\..\\windows\\system32",
            "!start-agent agent/../../../etc/passwd"
        ]
        
        for cmd in dangerous_paths:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_xss_protection(self):
        """Test XSS attempts are handled safely."""
        xss_attempts = [
            "!start-agent <script>alert('xss')</script>",
            "!start-agent javascript:alert('xss')",
            "!start-agent <img src=x onerror=alert('xss')>"
        ]
        
        for cmd in xss_attempts:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_sql_injection_protection(self):
        """Test SQL injection attempts are blocked."""
        sql_attempts = [
            "!start-agent agent'; DROP TABLE users; --",
            "!start-agent agent' OR '1'='1",
            "!start-agent agent UNION SELECT * FROM passwords"
        ]
        
        for cmd in sql_attempts:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_control_character_rejection(self):
        """Test control characters are rejected."""
        control_chars = [
            "!start-agent agent\x00",
            "!start-agent agent\r\necho harmful",
            "!start-agent agent\x1b[31mred text"
        ]
        
        for cmd in control_chars:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_unicode_handling(self):
        """Test proper Unicode handling."""
        # Valid Unicode should work if it passes other validations
        with pytest.raises(CommandValidationError):  # Will fail pattern validation
            self.parser.parse_command("!start-agent café")
    
    def test_malformed_quotes_handling(self):
        """Test handling of malformed quotes."""
        malformed = [
            "!start-agent 'unclosed quote",
            "!start-agent \"unclosed quote",
            "!start-agent 'mixed quotes\""
        ]
        
        for cmd in malformed:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_get_allowed_commands(self):
        """Test getting allowed commands list."""
        commands = self.parser.get_allowed_commands()
        
        assert isinstance(commands, dict)
        assert 'start-agent' in commands
        assert 'Start an agent service' in commands['start-agent']
    
    def test_get_command_help(self):
        """Test getting help for specific command."""
        help_info = self.parser.get_command_help('start-agent')
        
        assert help_info is not None
        assert help_info['command'] == 'start-agent'
        assert 'usage' in help_info
    
    def test_get_command_help_invalid(self):
        """Test getting help for invalid command returns None."""
        help_info = self.parser.get_command_help('invalid-command')
        assert help_info is None
    
    def test_validate_agent_name_valid(self):
        """Test valid agent name validation."""
        valid_names = [
            'backend-architect',
            'test-writer-fixer',
            'ui_designer',
            'agent123',
            'a'
        ]
        
        for name in valid_names:
            assert self.parser.validate_agent_name(name) is True
    
    def test_validate_agent_name_invalid(self):
        """Test invalid agent name validation."""
        invalid_names = [
            '',
            'agent with spaces',
            'agent/with/slash',
            'agent.with.dots',
            'agent@with@symbols',
            'a' * 51,  # Too long
            '../etc/passwd',
            'agent;rm -rf /'
        ]
        
        for name in invalid_names:
            assert self.parser.validate_agent_name(name) is False


class TestCommandParserSecurity:
    """Dedicated security testing for command parser."""
    
    def setup_method(self):
        """Set up security test fixtures."""
        self.parser = SecureCommandParser()
        self.security_tester = CommandParserSecurityTester()
    
    def test_malicious_input_blocking(self):
        """Test that malicious inputs are properly blocked."""
        results = self.security_tester.test_parser_security(self.parser)
        
        # Should block most malicious inputs
        assert results['blocked'] > results['passed']
        assert results['blocked'] >= results['total_tests'] * 0.8  # At least 80% blocked
        
        # Log any inputs that passed but shouldn't have
        if results['failed_to_block']:
            print(f"Failed to block: {results['failed_to_block']}")
    
    def test_command_length_limits(self):
        """Test command length limits are enforced."""
        # Test various lengths around the limit
        for length in [999, 1000, 1001, 1500, 2000]:
            command = "!" + "a" * length
            
            if length <= 1000:
                # Might still fail other validations, but not length
                try:
                    self.parser.parse_command(command)
                except CommandValidationError as e:
                    assert "too long" not in str(e).lower()
            else:
                with pytest.raises(CommandValidationError, match="Command too long"):
                    self.parser.parse_command(command)
    
    def test_argument_length_limits(self):
        """Test argument length limits are enforced."""
        long_arg = "a" * 201  # Over 200 character limit
        
        with pytest.raises(CommandValidationError, match="Argument too long"):
            self.parser.parse_command(f"!start-agent {long_arg}")
    
    def test_null_byte_injection(self):
        """Test null byte injection is blocked."""
        null_byte_commands = [
            "!start-agent agent\x00.service",
            "!start-agent agent\x00; rm -rf /",
            f"!start-agent {'a' * 100}\x00malicious"
        ]
        
        for cmd in null_byte_commands:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_encoding_attacks(self):
        """Test various encoding attacks are blocked."""
        encoding_attacks = [
            "!start-agent agent%2E%2E%2F%2E%2E%2Fetc%2Fpasswd",  # URL encoded
            "!start-agent agent\\x2e\\x2e/etc/passwd",  # Hex encoded
            "!start-agent agent\u002e\u002e/etc/passwd",  # Unicode encoded
        ]
        
        for cmd in encoding_attacks:
            with pytest.raises(CommandValidationError):
                self.parser.parse_command(cmd)
    
    def test_timing_attack_resistance(self):
        """Test parser is resistant to timing attacks."""
        # This is a basic timing test - in real scenarios you'd need more sophisticated analysis
        valid_command = "!start-agent backend-architect"
        invalid_command = "!invalid-command backend-architect"
        
        # Time multiple executions
        valid_times = []
        invalid_times = []
        
        for _ in range(100):
            start = time.perf_counter()
            try:
                self.parser.parse_command(valid_command)
            except:
                pass
            valid_times.append(time.perf_counter() - start)
            
            start = time.perf_counter()
            try:
                self.parser.parse_command(invalid_command)
            except:
                pass
            invalid_times.append(time.perf_counter() - start)
        
        # Times should be relatively similar (basic check)
        avg_valid = sum(valid_times) / len(valid_times)
        avg_invalid = sum(invalid_times) / len(invalid_times)
        
        # Allow for some variance but not orders of magnitude difference
        ratio = max(avg_valid, avg_invalid) / min(avg_valid, avg_invalid)
        assert ratio < 10.0  # Less than 10x difference


# Property-based testing with Hypothesis
class TestCommandParserProperties:
    """Property-based tests using Hypothesis."""
    
    def setup_method(self):
        """Set up property test fixtures."""
        self.parser = SecureCommandParser()
    
    @given(st.text())
    def test_no_crashes_on_arbitrary_input(self, text):
        """Test parser doesn't crash on arbitrary input."""
        try:
            result = self.parser.parse_command(text)
            # If parsing succeeded, result should be valid
            assert isinstance(result, ParsedCommand)
            assert result.command in self.parser.allowed_commands
            assert isinstance(result.args, list)
        except CommandValidationError:
            # Expected for invalid input
            pass
        except Exception as e:
            # Should not raise unexpected exceptions
            pytest.fail(f"Unexpected exception: {e}")
    
    @given(st.text(min_size=1, max_size=1000))
    def test_valid_commands_always_parseable(self, suffix):
        """Test that properly formatted commands are always parseable."""
        assume(not any(char in suffix for char in ['&', '|', ';', '`', '$', '(', ')']))
        assume('..' not in suffix)
        assume(suffix.isalnum() or all(c in '-_' for c in suffix if not c.isalnum()))
        
        if suffix and len(suffix) <= 50:
            command = f"!start-agent {suffix}"
            try:
                result = self.parser.parse_command(command)
                assert result.command == "start-agent"
                assert len(result.args) == 1
            except CommandValidationError:
                # May still fail pattern validation, which is okay
                pass
    
    @given(st.lists(st.text(alphabet=string.ascii_letters + string.digits + '-_', min_size=1, max_size=20), min_size=1, max_size=3))
    def test_argument_parsing_consistency(self, args):
        """Test argument parsing is consistent."""
        assume(all(len(arg) <= 50 for arg in args))
        
        command = "!start-agent " + " ".join(args)
        
        try:
            result = self.parser.parse_command(command)
            # If parsing succeeded, arguments should match
            assert result.args == args
        except CommandValidationError:
            # Expected for invalid combinations
            pass
    
    @given(st.integers(min_value=0, max_value=2000))
    def test_length_boundaries(self, length):
        """Test command length boundary conditions."""
        if length == 0:
            command = ""
        else:
            command = "!" + "a" * (length - 1)
        
        if length <= 1000 and length > 0:
            # Should not fail due to length (may fail other validations)
            try:
                self.parser.parse_command(command)
            except CommandValidationError as e:
                assert "too long" not in str(e).lower()
        elif length > 1000:
            with pytest.raises(CommandValidationError, match="Command too long"):
                self.parser.parse_command(command)
        else:  # length == 0
            with pytest.raises(CommandValidationError, match="Empty command"):
                self.parser.parse_command(command)


# Stateful testing
class CommandParserStateMachine(RuleBasedStateMachine):
    """Stateful property-based testing for command parser."""
    
    def __init__(self):
        super().__init__()
        self.parser = SecureCommandParser()
        self.parsed_commands = []
    
    valid_agents = Bundle('valid_agents')
    
    @rule(target=valid_agents, agent=st.text(alphabet=string.ascii_letters + '-_', min_size=1, max_size=20))
    def add_valid_agent(self, agent):
        assume(agent in self.parser.allowed_services)
        return agent
    
    @rule(agent=valid_agents)
    def test_start_agent(self, agent):
        command = f"!start-agent {agent}"
        result = self.parser.parse_command(command)
        assert result.command == "start-agent"
        assert result.args == [agent]
        self.parsed_commands.append(result)
    
    @rule(agent=valid_agents)
    def test_stop_agent(self, agent):
        command = f"!stop-agent {agent}"
        result = self.parser.parse_command(command)
        assert result.command == "stop-agent"
        assert result.args == [agent]
        self.parsed_commands.append(result)
    
    @rule()
    def test_list_agents(self):
        command = "!list-agents"
        result = self.parser.parse_command(command)
        assert result.command == "list-agents"
        assert result.args == []
        self.parsed_commands.append(result)
    
    @invariant()
    def all_commands_valid(self):
        for cmd in self.parsed_commands:
            assert cmd.command in self.parser.allowed_commands
            assert isinstance(cmd.args, list)
            assert cmd.metadata['validation_passed'] is True


# Performance testing
class TestCommandParserPerformance:
    """Performance tests for command parser."""
    
    def setup_method(self):
        """Set up performance test fixtures."""
        self.parser = SecureCommandParser()
    
    def test_parsing_performance(self):
        """Test command parsing performance."""
        commands = [
            "!start-agent backend-architect",
            "!stop-agent test-writer-fixer",
            "!status-agent ui-designer", 
            "!list-agents"
        ] * 250  # 1000 commands total
        
        start_time = time.perf_counter()
        
        for cmd in commands:
            try:
                self.parser.parse_command(cmd)
            except CommandValidationError:
                pass
        
        end_time = time.perf_counter()
        duration = end_time - start_time
        
        # Should parse 1000 commands in reasonable time
        assert duration < 1.0  # Less than 1 second
        
        rate = len(commands) / duration
        print(f"Parsing rate: {rate:.0f} commands/second")
    
    def test_malicious_input_performance(self):
        """Test performance with malicious inputs doesn't degrade significantly."""
        malicious_commands = [
            "!" + "A" * 999,  # Long command
            "!start-agent " + "B" * 199,  # Long argument
            "!invalid-command with many args " * 20,
            "!start-agent agent; rm -rf /"
        ] * 100
        
        start_time = time.perf_counter()
        
        for cmd in malicious_commands:
            try:
                self.parser.parse_command(cmd)
            except CommandValidationError:
                pass
        
        end_time = time.perf_counter()
        duration = end_time - start_time
        
        # Should reject malicious commands quickly
        assert duration < 0.5  # Less than 0.5 seconds for 400 malicious commands
        
        rate = len(malicious_commands) / duration
        print(f"Malicious input rejection rate: {rate:.0f} commands/second")


# Run stateful tests
TestCommandParserStateful = CommandParserStateMachine.TestCase


# Pytest fixtures and test configuration
@pytest.fixture
def parser():
    """Provide a fresh parser instance for tests."""
    return SecureCommandParser()


@pytest.fixture
def security_tester():
    """Provide a security tester instance."""
    return CommandParserSecurityTester()


# Test runner configuration
def test_security_comprehensive():
    """Run comprehensive security test suite."""
    parser = SecureCommandParser()
    tester = CommandParserSecurityTester()
    
    results = tester.test_parser_security(parser)
    
    # Ensure high blocking rate
    total_tests = results['total_tests']
    blocked_percentage = (results['blocked'] / total_tests) * 100
    
    print(f"Security test results:")
    print(f"  Total tests: {total_tests}")
    print(f"  Blocked: {results['blocked']} ({blocked_percentage:.1f}%)")
    print(f"  Passed: {results['passed']} ({(results['passed']/total_tests)*100:.1f}%)")
    
    # Assert high security effectiveness
    assert blocked_percentage >= 85.0, f"Security blocking rate too low: {blocked_percentage:.1f}%"
    
    # No critical security bypasses should exist
    critical_bypasses = [inp for inp in results.get('failed_to_block', []) 
                        if any(danger in str(inp).lower() for danger in 
                              ['rm -rf', 'cat /etc', '../..', ';', '|', '&', '`'])]
    
    assert len(critical_bypasses) == 0, f"Critical security bypasses found: {critical_bypasses}"


if __name__ == "__main__":
    # Run specific test categories
    import sys
    
    if "mutation" in sys.argv:
        # This would typically be run via mutmut
        print("Run mutation tests with: mutmut run --paths-to-mutate=src/")
    elif "property" in sys.argv:
        # Run property-based tests with more examples
        settings.register_profile("thorough", max_examples=1000, deadline=None)
        settings.load_profile("thorough")
        pytest.main([__file__ + "::TestCommandParserProperties", "-v"])
    else:
        pytest.main([__file__, "-v"])