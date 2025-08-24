"""
Systemd Agent Controller for RAVE Matrix Bridge
Implements secure systemd service control for autonomous agents.

Security Features:
- Service allowlisting with strict validation
- D-Bus integration with privilege separation
- Command execution with timeout controls
- Comprehensive audit logging of all operations
- State validation and consistency checks
- Resource monitoring and limits enforcement
"""

import asyncio
import json
import time
from dataclasses import dataclass, asdict
from typing import Dict, Any, List, Optional, Set, Union
from enum import Enum
import subprocess
import os
import signal

import structlog

logger = structlog.get_logger()


class AgentControlError(Exception):
    """Base exception for agent control errors."""
    pass


class ServiceNotFoundError(AgentControlError):
    """Raised when requested service is not found."""
    pass


class ServiceOperationError(AgentControlError):
    """Raised when service operation fails."""
    pass


class SecurityViolationError(AgentControlError):
    """Raised when security validation fails."""
    pass


class ServiceState(Enum):
    """Possible service states."""
    ACTIVE = "active"
    INACTIVE = "inactive"  
    FAILED = "failed"
    ACTIVATING = "activating"
    DEACTIVATING = "deactivating"
    UNKNOWN = "unknown"


@dataclass
class AgentStatus:
    """Represents agent service status."""
    name: str
    state: ServiceState
    sub_state: str
    active_since: Optional[str]
    memory_usage: Optional[int]
    cpu_percent: Optional[float]
    pid: Optional[int]
    last_logs: List[str]
    error_message: Optional[str]


@dataclass
class OperationResult:
    """Represents the result of an agent operation."""
    success: bool
    message: str
    details: Dict[str, Any]
    timestamp: float
    duration: Optional[float] = None


class SystemdAgentController:
    """
    Secure controller for RAVE agent systemd services.
    
    Implements comprehensive security controls:
    - Service allowlisting and validation
    - Secure systemd D-Bus integration
    - Command execution with timeouts
    - Resource monitoring and limits
    - Comprehensive audit logging
    - State consistency validation
    """
    
    def __init__(
        self,
        allowed_services: Optional[List[str]] = None,
        service_prefix: str = "rave-agent-",
        operation_timeout: int = 30,
        max_log_lines: int = 50
    ):
        """
        Initialize the systemd agent controller.
        
        Args:
            allowed_services: List of allowed service names
            service_prefix: Prefix for agent services
            operation_timeout: Timeout for systemd operations
            max_log_lines: Maximum log lines to retrieve
        """
        self.service_prefix = service_prefix
        self.operation_timeout = operation_timeout
        self.max_log_lines = max_log_lines
        
        self.log = logger.bind(component="agent_controller")
        
        # Set allowed services with defaults
        if allowed_services is None:
            self.allowed_services = {
                'backend-architect',
                'frontend-developer', 
                'test-writer-fixer',
                'ui-designer',
                'devops-automator',
                'api-tester',
                'performance-benchmarker',
                'rapid-prototyper',
                'refactoring-specialist'
            }
        else:
            self.allowed_services = set(allowed_services)
        
        # Validate service names
        self._validate_allowed_services()
        
        # Operation tracking
        self._operation_history: List[Dict[str, Any]] = []
        self._max_history = 1000
        
        # Security settings
        self.max_concurrent_operations = 5
        self._active_operations: Set[str] = set()
        
        self.log.info("Agent controller initialized",
                     allowed_services=list(self.allowed_services),
                     service_prefix=self.service_prefix,
                     timeout=self.operation_timeout)
    
    async def initialize(self) -> None:
        """Initialize the controller and validate systemd availability."""
        try:
            # Test systemd availability
            result = await self._run_systemctl_command(['--version'])
            if not result.success:
                raise AgentControlError("systemd not available")
            
            # Verify we can access systemd D-Bus
            await self._verify_dbus_access()
            
            # Discover existing agent services
            await self._discover_agent_services()
            
            self.log.info("Agent controller initialized successfully")
            
        except Exception as e:
            self.log.error("Failed to initialize agent controller", error=str(e))
            raise AgentControlError(f"Controller initialization failed: {str(e)}")
    
    async def start_agent(self, agent_type: str, config: Optional[str] = None) -> Dict[str, Any]:
        """
        Start an agent service.
        
        Args:
            agent_type: Type of agent to start
            config: Optional configuration string
            
        Returns:
            Dict: Operation result with status and details
        """
        start_time = time.time()
        operation_id = f"start-{agent_type}-{int(start_time)}"
        
        self.log.info("Starting agent", agent_type=agent_type, operation_id=operation_id)
        
        try:
            # 1. Validate request
            self._validate_agent_request(agent_type, operation_id)
            
            # 2. Get service name
            service_name = self._get_service_name(agent_type)
            
            # 3. Check current status
            current_status = await self._get_service_status(service_name)
            if current_status.state == ServiceState.ACTIVE:
                return self._create_result(
                    success=False,
                    message=f"Agent {agent_type} is already active",
                    details={'current_state': current_status.state.value},
                    start_time=start_time
                )
            
            # 4. Start the service
            systemctl_result = await self._run_systemctl_command([
                'start', service_name
            ])
            
            if not systemctl_result.success:
                raise ServiceOperationError(
                    f"Failed to start service: {systemctl_result.message}"
                )
            
            # 5. Verify service started successfully
            await asyncio.sleep(2)  # Allow time for startup
            new_status = await self._get_service_status(service_name)
            
            success = new_status.state in [ServiceState.ACTIVE, ServiceState.ACTIVATING]
            
            # 6. Create result
            result = self._create_result(
                success=success,
                message=f"Agent {agent_type} {'started successfully' if success else 'failed to start'}",
                details={
                    'agent_type': agent_type,
                    'service_name': service_name,
                    'state': new_status.state.value,
                    'sub_state': new_status.sub_state,
                    'pid': new_status.pid
                },
                start_time=start_time
            )
            
            # 7. Log operation
            self._record_operation(operation_id, 'start', agent_type, result)
            
            return result
            
        except Exception as e:
            error_result = self._create_error_result(
                f"Failed to start agent {agent_type}: {str(e)}",
                start_time
            )
            self._record_operation(operation_id, 'start', agent_type, error_result)
            return error_result
            
        finally:
            self._active_operations.discard(operation_id)
    
    async def stop_agent(self, agent_type: str) -> Dict[str, Any]:
        """
        Stop an agent service.
        
        Args:
            agent_type: Type of agent to stop
            
        Returns:
            Dict: Operation result with status and details
        """
        start_time = time.time()
        operation_id = f"stop-{agent_type}-{int(start_time)}"
        
        self.log.info("Stopping agent", agent_type=agent_type, operation_id=operation_id)
        
        try:
            # 1. Validate request
            self._validate_agent_request(agent_type, operation_id)
            
            # 2. Get service name
            service_name = self._get_service_name(agent_type)
            
            # 3. Check current status
            current_status = await self._get_service_status(service_name)
            if current_status.state == ServiceState.INACTIVE:
                return self._create_result(
                    success=True,
                    message=f"Agent {agent_type} is already inactive",
                    details={'current_state': current_status.state.value},
                    start_time=start_time
                )
            
            # 4. Stop the service
            systemctl_result = await self._run_systemctl_command([
                'stop', service_name
            ])
            
            if not systemctl_result.success:
                raise ServiceOperationError(
                    f"Failed to stop service: {systemctl_result.message}"
                )
            
            # 5. Verify service stopped successfully
            await asyncio.sleep(2)  # Allow time for shutdown
            new_status = await self._get_service_status(service_name)
            
            success = new_status.state in [ServiceState.INACTIVE, ServiceState.DEACTIVATING]
            
            # 6. Create result
            result = self._create_result(
                success=success,
                message=f"Agent {agent_type} {'stopped successfully' if success else 'failed to stop'}",
                details={
                    'agent_type': agent_type,
                    'service_name': service_name,
                    'state': new_status.state.value,
                    'sub_state': new_status.sub_state
                },
                start_time=start_time
            )
            
            # 7. Log operation
            self._record_operation(operation_id, 'stop', agent_type, result)
            
            return result
            
        except Exception as e:
            error_result = self._create_error_result(
                f"Failed to stop agent {agent_type}: {str(e)}",
                start_time
            )
            self._record_operation(operation_id, 'stop', agent_type, error_result)
            return error_result
            
        finally:
            self._active_operations.discard(operation_id)
    
    async def get_status(self, agent_type: str) -> Dict[str, Any]:
        """
        Get agent service status.
        
        Args:
            agent_type: Type of agent to check
            
        Returns:
            Dict: Agent status information
        """
        start_time = time.time()
        
        self.log.debug("Getting agent status", agent_type=agent_type)
        
        try:
            # 1. Validate agent type
            if not self._is_valid_agent_type(agent_type):
                raise SecurityViolationError(f"Invalid agent type: {agent_type}")
            
            # 2. Get service status
            service_name = self._get_service_name(agent_type)
            status = await self._get_service_status(service_name)
            
            # 3. Get additional metrics if service is active
            metrics = {}
            if status.state == ServiceState.ACTIVE and status.pid:
                metrics = await self._get_service_metrics(status.pid)
            
            # 4. Create result
            result = self._create_result(
                success=True,
                message=f"Status retrieved for agent {agent_type}",
                details={
                    'agent_type': agent_type,
                    'service_name': service_name,
                    'state': status.state.value,
                    'sub_state': status.sub_state,
                    'active_since': status.active_since,
                    'pid': status.pid,
                    'memory_usage': status.memory_usage,
                    'cpu_percent': status.cpu_percent,
                    'recent_logs': status.last_logs,
                    'error_message': status.error_message,
                    **metrics
                },
                start_time=start_time
            )
            
            return result
            
        except Exception as e:
            return self._create_error_result(
                f"Failed to get status for agent {agent_type}: {str(e)}",
                start_time
            )
    
    async def list_agents(self, filter_state: Optional[str] = None) -> Dict[str, Any]:
        """
        List all available agents and their status.
        
        Args:
            filter_state: Optional state filter (active, inactive, failed)
            
        Returns:
            Dict: List of agents and their status
        """
        start_time = time.time()
        
        self.log.debug("Listing agents", filter_state=filter_state)
        
        try:
            agents = []
            
            for agent_type in sorted(self.allowed_services):
                try:
                    service_name = self._get_service_name(agent_type)
                    status = await self._get_service_status(service_name)
                    
                    # Apply filter if specified
                    if filter_state and status.state.value != filter_state:
                        continue
                    
                    agent_info = {
                        'agent_type': agent_type,
                        'service_name': service_name,
                        'state': status.state.value,
                        'sub_state': status.sub_state,
                        'active_since': status.active_since,
                        'pid': status.pid,
                        'memory_usage': status.memory_usage,
                        'cpu_percent': status.cpu_percent
                    }
                    
                    agents.append(agent_info)
                    
                except Exception as e:
                    self.log.warning("Failed to get status for agent",
                                   agent_type=agent_type,
                                   error=str(e))
                    # Include agent with error status
                    agents.append({
                        'agent_type': agent_type,
                        'service_name': self._get_service_name(agent_type),
                        'state': 'error',
                        'error': str(e)
                    })
            
            # Get summary statistics
            summary = self._calculate_agent_summary(agents)
            
            result = self._create_result(
                success=True,
                message=f"Found {len(agents)} agents",
                details={
                    'agents': agents,
                    'summary': summary,
                    'filter_applied': filter_state,
                    'total_allowed': len(self.allowed_services)
                },
                start_time=start_time
            )
            
            return result
            
        except Exception as e:
            return self._create_error_result(
                f"Failed to list agents: {str(e)}",
                start_time
            )
    
    def _validate_allowed_services(self) -> None:
        """Validate that all allowed service names are secure."""
        for service in self.allowed_services:
            if not self._is_valid_agent_type(service):
                raise SecurityViolationError(f"Invalid service name: {service}")
    
    def _is_valid_agent_type(self, agent_type: str) -> bool:
        """Validate agent type format for security."""
        import re
        
        # Must be in allowed services
        if agent_type not in self.allowed_services:
            return False
        
        # Must match safe pattern
        pattern = r'^[a-zA-Z0-9-_]{1,50}$'
        return bool(re.match(pattern, agent_type))
    
    def _validate_agent_request(self, agent_type: str, operation_id: str) -> None:
        """Validate agent operation request."""
        # Check agent type
        if not self._is_valid_agent_type(agent_type):
            raise SecurityViolationError(f"Invalid agent type: {agent_type}")
        
        # Check concurrent operations limit
        if len(self._active_operations) >= self.max_concurrent_operations:
            raise AgentControlError("Too many concurrent operations")
        
        # Add to active operations
        self._active_operations.add(operation_id)
    
    def _get_service_name(self, agent_type: str) -> str:
        """Get systemd service name for agent type."""
        return f"{self.service_prefix}{agent_type}.service"
    
    async def _get_service_status(self, service_name: str) -> AgentStatus:
        """Get comprehensive service status."""
        try:
            # Get basic status
            status_result = await self._run_systemctl_command([
                'show', service_name,
                '--property=ActiveState,SubState,ActiveEnterTimestamp,MainPID'
            ])
            
            if not status_result.success:
                return AgentStatus(
                    name=service_name,
                    state=ServiceState.UNKNOWN,
                    sub_state="unknown",
                    active_since=None,
                    memory_usage=None,
                    cpu_percent=None,
                    pid=None,
                    last_logs=[],
                    error_message=status_result.message
                )
            
            # Parse status output
            status_props = {}
            for line in status_result.message.split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    status_props[key] = value
            
            # Map systemd state to our enum
            active_state = status_props.get('ActiveState', 'unknown')
            state = self._map_systemd_state(active_state)
            
            sub_state = status_props.get('SubState', 'unknown')
            active_since = status_props.get('ActiveEnterTimestamp', None)
            pid_str = status_props.get('MainPID', '0')
            pid = int(pid_str) if pid_str.isdigit() and pid_str != '0' else None
            
            # Get resource usage if service is active
            memory_usage = None
            cpu_percent = None
            if pid:
                try:
                    metrics = await self._get_service_metrics(pid)
                    memory_usage = metrics.get('memory_usage')
                    cpu_percent = metrics.get('cpu_percent')
                except Exception:
                    pass  # Metrics are optional
            
            # Get recent logs
            logs = await self._get_service_logs(service_name)
            
            return AgentStatus(
                name=service_name,
                state=state,
                sub_state=sub_state,
                active_since=active_since if active_since != 'n/a' else None,
                memory_usage=memory_usage,
                cpu_percent=cpu_percent,
                pid=pid,
                last_logs=logs,
                error_message=None
            )
            
        except Exception as e:
            self.log.error("Failed to get service status",
                          service=service_name,
                          error=str(e))
            return AgentStatus(
                name=service_name,
                state=ServiceState.UNKNOWN,
                sub_state="error",
                active_since=None,
                memory_usage=None,
                cpu_percent=None,
                pid=None,
                last_logs=[],
                error_message=str(e)
            )
    
    def _map_systemd_state(self, systemd_state: str) -> ServiceState:
        """Map systemd ActiveState to our ServiceState enum."""
        state_map = {
            'active': ServiceState.ACTIVE,
            'inactive': ServiceState.INACTIVE,
            'failed': ServiceState.FAILED,
            'activating': ServiceState.ACTIVATING,
            'deactivating': ServiceState.DEACTIVATING
        }
        
        return state_map.get(systemd_state, ServiceState.UNKNOWN)
    
    async def _get_service_metrics(self, pid: int) -> Dict[str, Any]:
        """Get resource usage metrics for a service."""
        try:
            # Use ps to get basic metrics
            ps_result = await self._run_command([
                'ps', '-p', str(pid), '-o', 'pid,pcpu,pmem,rss', '--no-headers'
            ])
            
            if not ps_result.success:
                return {}
            
            parts = ps_result.message.strip().split()
            if len(parts) >= 4:
                return {
                    'cpu_percent': float(parts[1]),
                    'memory_percent': float(parts[2]),
                    'memory_usage': int(parts[3]) * 1024  # RSS in bytes
                }
            
            return {}
            
        except Exception as e:
            self.log.debug("Failed to get service metrics", pid=pid, error=str(e))
            return {}
    
    async def _get_service_logs(self, service_name: str) -> List[str]:
        """Get recent service logs."""
        try:
            log_result = await self._run_command([
                'journalctl', '-u', service_name, '-n', str(self.max_log_lines),
                '--no-pager', '--output=short-iso'
            ])
            
            if log_result.success:
                logs = log_result.message.strip().split('\n')
                # Filter out empty lines and return last N lines
                return [log for log in logs if log.strip()][-self.max_log_lines:]
            
            return []
            
        except Exception as e:
            self.log.debug("Failed to get service logs",
                          service=service_name,
                          error=str(e))
            return []
    
    async def _run_systemctl_command(self, args: List[str]) -> OperationResult:
        """Run systemctl command with security controls."""
        full_args = ['systemctl'] + args
        return await self._run_command(full_args, timeout=self.operation_timeout)
    
    async def _run_command(self, args: List[str], timeout: Optional[int] = None) -> OperationResult:
        """
        Run system command with comprehensive security controls.
        
        Args:
            args: Command and arguments
            timeout: Command timeout in seconds
            
        Returns:
            OperationResult: Command execution result
        """
        start_time = time.time()
        
        if timeout is None:
            timeout = self.operation_timeout
        
        self.log.debug("Running command", command=args[0], args=args[1:])
        
        try:
            # Security: Validate command is allowed
            if args[0] not in ['systemctl', 'ps', 'journalctl']:
                raise SecurityViolationError(f"Command not allowed: {args[0]}")
            
            # Run command with timeout - SECURITY NOTE: create_subprocess_exec() is secure
            # as it doesn't use shell interpretation, preventing command injection
            process = await asyncio.create_subprocess_exec(
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=self._get_secure_environment()
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=timeout
                )
                
                success = process.returncode == 0
                message = stdout.decode('utf-8') if success else stderr.decode('utf-8')
                
                return OperationResult(
                    success=success,
                    message=message.strip(),
                    details={'returncode': process.returncode, 'command': ' '.join(args)},
                    timestamp=start_time,
                    duration=time.time() - start_time
                )
                
            except asyncio.TimeoutError:
                # Kill process if timeout
                try:
                    process.kill()
                    await process.wait()
                except Exception:
                    pass
                
                raise AgentControlError(f"Command timed out after {timeout} seconds")
            
        except Exception as e:
            return OperationResult(
                success=False,
                message=str(e),
                details={'error': str(e), 'command': ' '.join(args)},
                timestamp=start_time,
                duration=time.time() - start_time
            )
    
    def _get_secure_environment(self) -> Dict[str, str]:
        """Get secure environment variables for command execution."""
        # Minimal environment to reduce attack surface
        return {
            'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
            'LANG': 'C.UTF-8',
            'LC_ALL': 'C.UTF-8'
        }
    
    async def _verify_dbus_access(self) -> None:
        """Verify D-Bus access to systemd."""
        try:
            # Simple test - check if we can list units
            result = await self._run_systemctl_command(['list-units', '--type=service', '--limit=1'])
            if not result.success:
                raise AgentControlError("Cannot access systemd via D-Bus")
        except Exception as e:
            raise AgentControlError(f"D-Bus verification failed: {str(e)}")
    
    async def _discover_agent_services(self) -> None:
        """Discover existing agent services in systemd."""
        try:
            # List all services with our prefix
            result = await self._run_systemctl_command([
                'list-units', '--type=service', f'{self.service_prefix}*', '--all'
            ])
            
            if result.success:
                discovered_services = []
                for line in result.message.split('\n'):
                    if self.service_prefix in line and '.service' in line:
                        parts = line.split()
                        if parts:
                            service_name = parts[0]
                            # Extract agent type from service name
                            agent_type = service_name.replace(self.service_prefix, '').replace('.service', '')
                            if agent_type in self.allowed_services:
                                discovered_services.append(agent_type)
                
                self.log.info("Discovered agent services", services=discovered_services)
            
        except Exception as e:
            self.log.warning("Failed to discover agent services", error=str(e))
    
    def _create_result(
        self, 
        success: bool, 
        message: str, 
        details: Dict[str, Any],
        start_time: float
    ) -> Dict[str, Any]:
        """Create standardized operation result."""
        return {
            'success': success,
            'message': message,
            'details': details,
            'timestamp': start_time,
            'duration': time.time() - start_time
        }
    
    def _create_error_result(self, error_message: str, start_time: float) -> Dict[str, Any]:
        """Create standardized error result."""
        return {
            'success': False,
            'message': error_message,
            'details': {'error': True},
            'timestamp': start_time,
            'duration': time.time() - start_time
        }
    
    def _record_operation(
        self, 
        operation_id: str, 
        operation: str, 
        agent_type: str, 
        result: Dict[str, Any]
    ) -> None:
        """Record operation in history for audit purposes."""
        entry = {
            'operation_id': operation_id,
            'operation': operation,
            'agent_type': agent_type,
            'timestamp': time.time(),
            'success': result['success'],
            'duration': result.get('duration'),
            'details': result.get('details', {})
        }
        
        self._operation_history.append(entry)
        
        # Trim history if too large
        if len(self._operation_history) > self._max_history:
            self._operation_history = self._operation_history[-self._max_history//2:]
        
        self.log.info("Operation recorded", 
                     operation_id=operation_id,
                     operation=operation,
                     agent_type=agent_type,
                     success=result['success'])
    
    def _calculate_agent_summary(self, agents: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate summary statistics for agents."""
        summary = {
            'total': len(agents),
            'active': 0,
            'inactive': 0,
            'failed': 0,
            'other': 0
        }
        
        for agent in agents:
            state = agent.get('state', 'unknown')
            if state == 'active':
                summary['active'] += 1
            elif state == 'inactive':
                summary['inactive'] += 1
            elif state == 'failed':
                summary['failed'] += 1
            else:
                summary['other'] += 1
        
        return summary
    
    def get_operation_history(self, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """Get operation history for audit purposes."""
        history = self._operation_history
        
        if limit:
            history = history[-limit:]
        
        return history
    
    def get_controller_stats(self) -> Dict[str, Any]:
        """Get controller statistics for monitoring."""
        return {
            'allowed_services': list(self.allowed_services),
            'service_prefix': self.service_prefix,
            'operation_timeout': self.operation_timeout,
            'active_operations': len(self._active_operations),
            'max_concurrent_operations': self.max_concurrent_operations,
            'operation_history_size': len(self._operation_history),
            'uptime': time.time() - getattr(self, '_start_time', time.time())
        }