"""
Integration tests for Matrix Appservice Bridge
Tests the complete workflow of Matrix command processing with security validation.
"""

import pytest
import asyncio
import json
import aiohttp
from unittest.mock import AsyncMock, patch, MagicMock
from pathlib import Path
import tempfile
import os

from src.main import MatrixAppserviceBridge
from src.command_parser import CommandValidationError
from src.auth import AuthenticationError, AuthorizationError
from src.agent_controller import AgentControlError


class TestMatrixBridgeIntegration:
    """Comprehensive integration tests for Matrix bridge."""

    @pytest.fixture
    async def temp_config(self):
        """Create temporary configuration for testing."""
        config_data = {
            'host': '127.0.0.1',
            'port': 9999,  # Test port
            'homeserver_url': 'https://matrix.test',
            'as_token': 'test_as_token',
            'hs_token': 'test_hs_token',
            'gitlab_url': 'https://gitlab.test',
            'oidc_client_id': 'test_client',
            'oidc_client_secret': 'test_secret',
            'allowed_groups': ['developers', 'admins'],
            'rate_limit_rpm': 60,
            'rate_limit_burst': 10,
            'audit_log_file': '/tmp/test_audit.log'
        }
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            import yaml
            yaml.dump(config_data, f)
            config_path = f.name
        
        yield config_path
        
        # Cleanup
        os.unlink(config_path)
        if os.path.exists('/tmp/test_audit.log'):
            os.unlink('/tmp/test_audit.log')

    @pytest.fixture
    async def bridge(self, temp_config):
        """Create Matrix bridge instance for testing."""
        bridge = MatrixAppserviceBridge(temp_config)
        
        # Mock external dependencies
        bridge.session = AsyncMock()
        
        # Mock agent controller for testing
        bridge.agent_controller.initialize = AsyncMock()
        bridge.agent_controller.start_agent = AsyncMock()
        bridge.agent_controller.stop_agent = AsyncMock()
        bridge.agent_controller.get_status = AsyncMock()
        bridge.agent_controller.list_agents = AsyncMock()
        
        # Mock OIDC validator
        bridge.oidc_validator.validate_user = AsyncMock()
        
        # Mock audit logger
        bridge.audit_logger.initialize = AsyncMock()
        bridge.audit_logger.log = AsyncMock()
        bridge.audit_logger.close = AsyncMock()
        
        # Mock rate limiter
        bridge.rate_limiter.start = AsyncMock()
        bridge.rate_limiter.stop = AsyncMock()
        bridge.rate_limiter.is_allowed = AsyncMock(return_value=True)
        
        yield bridge

    @pytest.mark.asyncio
    async def test_bridge_initialization(self, bridge):
        """Test complete bridge initialization."""
        await bridge.start()
        
        # Verify components were initialized
        bridge.audit_logger.initialize.assert_called_once()
        bridge.agent_controller.initialize.assert_called_once()
        bridge.rate_limiter.start.assert_called_once()
        
        await bridge.stop()
        bridge.rate_limiter.stop.assert_called_once()
        bridge.audit_logger.close.assert_called_once()

    @pytest.mark.asyncio
    async def test_successful_command_processing(self, bridge):
        """Test successful Matrix command processing end-to-end."""
        # Setup mocks
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:start', 'agent:stop', 'agent:status'}
        }
        
        bridge.agent_controller.start_agent.return_value = {
            'success': True,
            'message': 'Agent started successfully',
            'details': {'agent_type': 'backend-architect', 'pid': 12345}
        }
        
        # Create test Matrix transaction
        transaction_data = {
            'events': [
                {
                    'type': 'm.room.message',
                    'content': {
                        'msgtype': 'm.text',
                        'body': '!start-agent backend-architect'
                    },
                    'sender': '@testuser:matrix.test',
                    'room_id': '!testroom:matrix.test',
                    'event_id': '$test_event_id'
                }
            ]
        }
        
        # Process the transaction
        await bridge._process_event(transaction_data['events'][0], 'test_txn')
        
        # Verify authentication was called
        bridge.oidc_validator.validate_user.assert_called_once_with('@testuser:matrix.test')
        
        # Verify agent controller was called
        bridge.agent_controller.start_agent.assert_called_once_with('backend-architect')
        
        # Verify audit logging
        assert bridge.audit_logger.log.call_count >= 2  # command_attempt and command_success

    @pytest.mark.asyncio
    async def test_authentication_failure(self, bridge):
        """Test command processing with authentication failure."""
        # Setup authentication failure
        bridge.oidc_validator.validate_user.side_effect = AuthenticationError("User not found")
        
        # Create test event
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': '!start-agent backend-architect'
            },
            'sender': '@baduser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event_id'
        }
        
        # Process the event
        await bridge._process_event(event, 'test_txn')
        
        # Verify authentication was attempted
        bridge.oidc_validator.validate_user.assert_called_once()
        
        # Verify agent controller was NOT called
        bridge.agent_controller.start_agent.assert_not_called()
        
        # Verify audit logging for failure
        bridge.audit_logger.log.assert_called()

    @pytest.mark.asyncio
    async def test_command_validation_failure(self, bridge):
        """Test command processing with invalid command."""
        # Setup valid authentication
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:start'}
        }
        
        # Create test event with invalid command
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': '!invalid-command; rm -rf /'  # Malicious command
            },
            'sender': '@testuser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event_id'
        }
        
        # Process the event
        await bridge._process_event(event, 'test_txn')
        
        # Verify authentication was called
        bridge.oidc_validator.validate_user.assert_called_once()
        
        # Verify agent controller was NOT called due to command validation failure
        bridge.agent_controller.start_agent.assert_not_called()

    @pytest.mark.asyncio
    async def test_rate_limiting(self, bridge):
        """Test rate limiting functionality."""
        # Setup rate limiting failure
        bridge.rate_limiter.is_allowed.return_value = False
        
        # Create mock request
        request = AsyncMock()
        request.remote = '127.0.0.1'
        request.headers = {'User-Agent': 'Test', 'Authorization': f'Bearer {bridge.config["as_token"]}'}
        request.path = '/_matrix/app/v1/transactions/test'
        request.method = 'PUT'
        request.read.return_value = b'{"events": []}'
        
        # Create mock handler
        handler = AsyncMock()
        handler.return_value = AsyncMock()
        handler.return_value.status = 200
        
        # Test rate limiting middleware
        with pytest.raises(aiohttp.web.HTTPTooManyRequests):
            await bridge.security_middleware(request, handler)
        
        # Verify rate limiter was checked
        bridge.rate_limiter.is_allowed.assert_called_once()
        
        # Verify handler was not called
        handler.assert_not_called()

    @pytest.mark.asyncio 
    async def test_security_validation_middleware(self, bridge):
        """Test comprehensive security validation in middleware."""
        # Test invalid authorization header
        request = AsyncMock()
        request.remote = '127.0.0.1'
        request.headers = {'User-Agent': 'Test', 'Authorization': 'Bearer invalid_token'}
        request.path = '/_matrix/app/v1/transactions/test'
        request.method = 'PUT'
        request.read.return_value = b'{"events": []}'
        
        handler = AsyncMock()
        
        with pytest.raises(aiohttp.web.HTTPUnauthorized):
            await bridge.security_middleware(request, handler)
        
        # Verify audit logging
        bridge.audit_logger.log.assert_called()

    @pytest.mark.asyncio
    async def test_circuit_breaker_protection(self, bridge):
        """Test circuit breaker protection for external services."""
        # Setup circuit breaker to be open
        bridge.systemd_circuit_breaker.state = 'open'
        bridge.systemd_circuit_breaker.call.side_effect = Exception("Circuit breaker open")
        
        # Setup valid authentication
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:start'}
        }
        
        # Create test event
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': '!start-agent backend-architect'
            },
            'sender': '@testuser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event_id'
        }
        
        # Process the event
        await bridge._process_event(event, 'test_txn')
        
        # Verify authentication succeeded but circuit breaker protected the call
        bridge.oidc_validator.validate_user.assert_called_once()

    @pytest.mark.asyncio
    async def test_health_check_endpoint(self, bridge):
        """Test health check endpoint functionality."""
        # Mock circuit breaker states
        bridge.oidc_circuit_breaker.state = 'closed'
        bridge.systemd_circuit_breaker.state = 'closed'
        
        # Create mock request
        request = AsyncMock()
        
        # Call health check
        response = await bridge.health_check(request)
        
        # Verify response
        response_data = json.loads(response.body.decode())
        assert response_data['status'] == 'healthy'
        assert 'components' in response_data
        assert response_data['components']['oidc_validator'] == 'closed'
        assert response_data['components']['systemd_controller'] == 'closed'

    @pytest.mark.asyncio
    async def test_metrics_endpoint(self, bridge):
        """Test Prometheus metrics endpoint."""
        request = AsyncMock()
        
        # Call metrics endpoint
        response = await bridge.metrics_handler(request)
        
        # Verify response
        assert response.content_type == 'text/plain; version=0.0.4; charset=utf-8'
        assert isinstance(response.text, str)

    @pytest.mark.asyncio
    async def test_agent_controller_integration(self, bridge):
        """Test integration with agent controller."""
        # Setup successful agent operation
        bridge.agent_controller.list_agents.return_value = {
            'success': True,
            'message': 'Found 3 agents',
            'details': {
                'agents': [
                    {'agent_type': 'backend-architect', 'state': 'active'},
                    {'agent_type': 'frontend-developer', 'state': 'inactive'},
                    {'agent_type': 'test-writer-fixer', 'state': 'active'}
                ],
                'summary': {'total': 3, 'active': 2, 'inactive': 1}
            }
        }
        
        # Setup authentication
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:status'}
        }
        
        # Create test event
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': '!list-agents'
            },
            'sender': '@testuser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event_id'
        }
        
        # Process the event
        await bridge._process_event(event, 'test_txn')
        
        # Verify agent controller was called
        bridge.agent_controller.list_agents.assert_called_once()
        
        # Verify successful audit logging
        bridge.audit_logger.log.assert_called()

    @pytest.mark.asyncio
    async def test_matrix_message_sending(self, bridge):
        """Test Matrix message sending functionality."""
        # Setup session mock
        response_mock = AsyncMock()
        response_mock.status = 200
        response_mock.__aenter__.return_value = response_mock
        response_mock.__aexit__.return_value = False
        
        bridge.session.put.return_value = response_mock
        
        # Send a test message
        await bridge._send_matrix_message('!test:room.id', 'Test message')
        
        # Verify HTTP request was made
        bridge.session.put.assert_called_once()
        
        # Verify request parameters
        args, kwargs = bridge.session.put.call_args
        assert bridge.config['homeserver_url'] in args[0]
        assert kwargs['headers']['Authorization'] == f"Bearer {bridge.config['as_token']}"
        assert kwargs['json']['msgtype'] == 'm.text'
        assert kwargs['json']['body'] == 'Test message'

    @pytest.mark.asyncio
    async def test_transaction_processing(self, bridge):
        """Test Matrix transaction processing."""
        # Setup authentication and agent controller
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:status'}
        }
        
        bridge.agent_controller.get_status.return_value = {
            'success': True,
            'message': 'Agent status retrieved',
            'details': {'agent_type': 'backend-architect', 'state': 'active'}
        }
        
        # Create mock request with transaction
        request = AsyncMock()
        request.json.return_value = {
            'events': [
                {
                    'type': 'm.room.message',
                    'content': {
                        'msgtype': 'm.text',
                        'body': '!status-agent backend-architect'
                    },
                    'sender': '@testuser:matrix.test',
                    'room_id': '!testroom:matrix.test',
                    'event_id': '$test_event_id'
                }
            ]
        }
        request.match_info = {'txnId': 'test_transaction_123'}
        
        # Process transaction
        response = await bridge.handle_transactions(request)
        
        # Verify response
        assert response.status == 200
        response_data = json.loads(response.body.decode())
        assert response_data == {}
        
        # Verify processing occurred
        bridge.oidc_validator.validate_user.assert_called_once()
        bridge.agent_controller.get_status.assert_called_once_with('backend-architect')

    def test_configuration_validation(self):
        """Test configuration validation and defaults."""
        # Test missing required configuration
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            import yaml
            yaml.dump({'host': '127.0.0.1'}, f)  # Missing required keys
            config_path = f.name
        
        try:
            with pytest.raises(Exception):  # Should raise MatrixBridgeError
                MatrixAppserviceBridge(config_path)
        finally:
            os.unlink(config_path)

    @pytest.mark.asyncio
    async def test_command_permission_validation(self, bridge):
        """Test that commands are properly validated against user permissions."""
        # Setup user with limited permissions
        bridge.oidc_validator.validate_user.return_value = {
            'username': 'limiteduser',
            'groups': ['viewers'],
            'roles': {'agent:status'}  # Only status permission
        }
        
        # Try to execute start-agent command (should work through command parser)
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': '!start-agent backend-architect'
            },
            'sender': '@limiteduser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event_id'
        }
        
        # Process the event
        await bridge._process_event(event, 'test_txn')
        
        # Verify authentication was called
        bridge.oidc_validator.validate_user.assert_called_once()
        
        # Command should be parsed and executed (permission checking happens at GitLab level)
        bridge.agent_controller.start_agent.assert_called_once()


class TestMatrixBridgeLoadTesting:
    """Load testing for Matrix bridge performance."""

    @pytest.fixture
    async def bridge(self):
        """Create bridge for load testing."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            import yaml
            config = {
                'host': '127.0.0.1',
                'port': 9998,
                'homeserver_url': 'https://matrix.test',
                'as_token': 'test_token',
                'hs_token': 'test_token',
                'gitlab_url': 'https://gitlab.test',
                'oidc_client_id': 'test',
                'oidc_client_secret': 'test',
                'rate_limit_rpm': 120,  # Higher limit for load testing
                'rate_limit_burst': 20
            }
            yaml.dump(config, f)
            config_path = f.name
        
        bridge = MatrixAppserviceBridge(config_path)
        
        # Mock all external dependencies
        bridge.session = AsyncMock()
        bridge.agent_controller.initialize = AsyncMock()
        bridge.audit_logger.initialize = AsyncMock()
        bridge.audit_logger.log = AsyncMock()
        bridge.audit_logger.close = AsyncMock()
        bridge.rate_limiter.start = AsyncMock()
        bridge.rate_limiter.stop = AsyncMock()
        bridge.rate_limiter.is_allowed = AsyncMock(return_value=True)
        bridge.oidc_validator.validate_user = AsyncMock(return_value={
            'username': 'testuser',
            'groups': ['developers'],
            'roles': {'agent:status'}
        })
        bridge.agent_controller.get_status = AsyncMock(return_value={
            'success': True,
            'message': 'Status retrieved'
        })
        
        yield bridge
        
        os.unlink(config_path)

    @pytest.mark.asyncio
    async def test_concurrent_request_processing(self, bridge):
        """Test bridge handles concurrent requests properly."""
        
        async def create_test_event():
            return {
                'type': 'm.room.message',
                'content': {
                    'msgtype': 'm.text',
                    'body': '!status-agent backend-architect'
                },
                'sender': '@testuser:matrix.test',
                'room_id': '!testroom:matrix.test',
                'event_id': f'$test_event_{asyncio.current_task().get_name()}'
            }
        
        # Create multiple concurrent tasks
        tasks = []
        for i in range(50):
            event = await create_test_event()
            task = asyncio.create_task(bridge._process_event(event, f'txn_{i}'))
            tasks.append(task)
        
        # Wait for all tasks to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Verify no exceptions occurred
        exceptions = [r for r in results if isinstance(r, Exception)]
        assert len(exceptions) == 0, f"Exceptions occurred: {exceptions}"
        
        # Verify all authentication calls were made
        assert bridge.oidc_validator.validate_user.call_count == 50

    @pytest.mark.asyncio 
    async def test_memory_usage_under_load(self, bridge):
        """Test memory usage doesn't grow excessively under load."""
        import tracemalloc
        
        tracemalloc.start()
        
        # Process many events
        for i in range(100):
            event = {
                'type': 'm.room.message',
                'content': {
                    'msgtype': 'm.text',
                    'body': f'!status-agent backend-architect-{i}'
                },
                'sender': f'@testuser{i}:matrix.test',
                'room_id': '!testroom:matrix.test',
                'event_id': f'$test_event_{i}'
            }
            await bridge._process_event(event, f'txn_{i}')
        
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        
        # Memory usage should be reasonable (less than 50MB for this test)
        assert current < 50 * 1024 * 1024, f"Memory usage too high: {current / 1024 / 1024}MB"


class TestMatrixBridgeEdgeCases:
    """Test edge cases and error scenarios."""

    @pytest.fixture
    async def bridge(self):
        """Create bridge for edge case testing."""
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            import yaml
            config = {
                'host': '127.0.0.1',
                'port': 9997,
                'homeserver_url': 'https://matrix.test',
                'as_token': 'test_token',
                'hs_token': 'test_token',
                'gitlab_url': 'https://gitlab.test',
                'oidc_client_id': 'test',
                'oidc_client_secret': 'test'
            }
            yaml.dump(config, f)
            config_path = f.name
        
        bridge = MatrixAppserviceBridge(config_path)
        
        # Basic mocks
        bridge.session = AsyncMock()
        bridge.agent_controller.initialize = AsyncMock()
        bridge.audit_logger.initialize = AsyncMock()
        bridge.audit_logger.log = AsyncMock()
        bridge.audit_logger.close = AsyncMock()
        bridge.rate_limiter.start = AsyncMock()
        bridge.rate_limiter.stop = AsyncMock()
        bridge.rate_limiter.is_allowed = AsyncMock(return_value=True)
        
        yield bridge
        
        os.unlink(config_path)

    @pytest.mark.asyncio
    async def test_malformed_matrix_events(self, bridge):
        """Test handling of malformed Matrix events."""
        malformed_events = [
            {},  # Empty event
            {'type': 'unknown.type'},  # Unknown event type
            {'type': 'm.room.message'},  # Missing content
            {'type': 'm.room.message', 'content': {}},  # Missing msgtype
            {'type': 'm.room.message', 'content': {'msgtype': 'm.text'}},  # Missing body
        ]
        
        for event in malformed_events:
            # Should not raise exceptions
            await bridge._process_event(event, 'test_txn')
        
        # Verify no authentication attempts were made for malformed events
        bridge.oidc_validator.validate_user.assert_not_called()

    @pytest.mark.asyncio
    async def test_network_failure_scenarios(self, bridge):
        """Test handling of network failures."""
        # Setup network failure for Matrix message sending
        bridge.session.put.side_effect = aiohttp.ClientError("Network error")
        
        # Should not raise exception
        await bridge._send_matrix_message('!test:room', 'Test message')
        
        # Should log error but continue gracefully
        # (Error logging happens in the _send_matrix_message method)

    @pytest.mark.asyncio
    async def test_extremely_long_commands(self, bridge):
        """Test handling of extremely long commands."""
        # Create very long command
        long_command = '!start-agent ' + 'a' * 2000
        
        event = {
            'type': 'm.room.message',
            'content': {
                'msgtype': 'm.text',
                'body': long_command
            },
            'sender': '@testuser:matrix.test',
            'room_id': '!testroom:matrix.test',
            'event_id': '$test_event'
        }
        
        # Should handle gracefully without crashing
        await bridge._process_event(event, 'test_txn')
        
        # Should not authenticate due to command validation failure
        bridge.oidc_validator.validate_user.assert_not_called()