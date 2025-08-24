#!/usr/bin/env python3
"""
Matrix Appservice Bridge for RAVE Autonomous Dev Agency
Phase P5 Implementation - Critical Security Component

This bridge translates Matrix commands into systemd actions for agent control.
Implements defense-in-depth security with comprehensive validation.

Security Features:
- GitLab OIDC authentication validation
- Command allowlisting with strict parsing
- Rate limiting and request throttling  
- Comprehensive audit logging
- Input validation and sanitization
- Multiple authorization layers
- Circuit breaker pattern for systemd calls
"""

import asyncio
import json
import logging
import signal
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Dict, Any, Optional, List
import os

import structlog
from aiohttp import web, ClientSession
from aiohttp.web_middlewares import middleware
from aiolimiter import AsyncLimiter
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import yaml

from command_parser import SecureCommandParser, CommandValidationError
from agent_controller import SystemdAgentController, AgentControlError
from auth import GitLabOIDCValidator, AuthenticationError, AuthorizationError
from audit import SecurityAuditLogger, AuditEvent, AuditEventType
from rate_limiter import AdaptiveRateLimiter
from circuit_breaker import CircuitBreaker, CircuitBreakerError

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Prometheus metrics
REQUEST_COUNT = Counter('matrix_bridge_requests_total', 
                       'Total Matrix bridge requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('matrix_bridge_request_duration_seconds',
                           'Matrix bridge request duration')
COMMAND_COUNT = Counter('matrix_bridge_commands_total',
                       'Total commands processed', ['command', 'status', 'user'])
AUTH_FAILURES = Counter('matrix_bridge_auth_failures_total',
                       'Total authentication failures', ['reason'])
SYSTEMD_OPERATIONS = Counter('matrix_bridge_systemd_operations_total',
                           'Total systemd operations', ['operation', 'agent', 'status'])


class MatrixBridgeError(Exception):
    """Base exception for Matrix bridge errors."""
    pass


class SecurityValidationError(MatrixBridgeError):
    """Raised when security validation fails."""
    pass


class MatrixAppserviceBridge:
    """
    Secure Matrix Appservice Bridge for RAVE Agent Control
    
    Implements comprehensive security controls:
    - Multi-layer authentication and authorization
    - Command allowlisting and validation
    - Rate limiting and request throttling
    - Audit logging and monitoring
    - Circuit breaker pattern for reliability
    """
    
    def __init__(self, config_path: str = "bridge_config.yaml"):
        self.config = self._load_config(config_path)
        self.log = logger.bind(component="matrix_bridge")
        
        # Security components
        self.command_parser = SecureCommandParser(
            allowed_commands=self.config.get('allowed_commands', [
                'start-agent', 'stop-agent', 'status-agent', 'list-agents'
            ])
        )
        
        self.oidc_validator = GitLabOIDCValidator(
            gitlab_url=self.config['gitlab_url'],
            client_id=self.config['oidc_client_id'],
            client_secret=self.config['oidc_client_secret'],
            allowed_groups=self.config.get('allowed_groups', [])
        )
        
        self.agent_controller = SystemdAgentController(
            allowed_services=self.config.get('allowed_agent_services', []),
            service_prefix=self.config.get('agent_service_prefix', 'rave-agent-')
        )
        
        self.audit_logger = SecurityAuditLogger(
            log_file=self.config.get('audit_log_file', '/var/log/matrix-bridge/audit.log')
        )
        
        # Rate limiting with adaptive thresholds
        self.rate_limiter = AdaptiveRateLimiter(
            requests_per_minute=self.config.get('rate_limit_rpm', 30),
            burst_size=self.config.get('rate_limit_burst', 5)
        )
        
        # Circuit breakers for external dependencies
        self.systemd_circuit_breaker = CircuitBreaker(
            failure_threshold=5,
            recovery_timeout=60,
            expected_exception=AgentControlError
        )
        
        self.oidc_circuit_breaker = CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=300,
            expected_exception=AuthenticationError
        )
        
        self.app = None
        self.session = None
        
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load and validate configuration with security defaults."""
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
        except FileNotFoundError:
            self.log.warning("Config file not found, using defaults", path=config_path)
            config = {}
        
        # Apply security defaults
        defaults = {
            'host': '127.0.0.1',  # Local binding only
            'port': 9000,
            'registration_file': 'registration.yaml',
            'max_request_size': 1024 * 1024,  # 1MB limit
            'request_timeout': 30,
            'enable_metrics': True,
            'metrics_port': 9001,
            'log_level': 'INFO',
            'rate_limit_rpm': 30,
            'rate_limit_burst': 5,
            'allowed_commands': [
                'start-agent', 'stop-agent', 'status-agent', 'list-agents'
            ],
            'allowed_agent_services': [
                'backend-architect', 'frontend-developer', 'test-writer-fixer',
                'ui-designer', 'devops-automator', 'api-tester'
            ],
            'agent_service_prefix': 'rave-agent-',
            'command_timeout': 10,
            'audit_log_file': '/var/log/matrix-bridge/audit.log'
        }
        
        # Merge with defaults
        for key, value in defaults.items():
            config.setdefault(key, value)
            
        # Validate required security settings
        required_keys = ['gitlab_url', 'oidc_client_id', 'oidc_client_secret', 
                        'homeserver_url', 'as_token', 'hs_token']
        missing_keys = [key for key in required_keys if key not in config]
        if missing_keys:
            raise MatrixBridgeError(f"Missing required config keys: {missing_keys}")
            
        return config
    
    @middleware
    async def security_middleware(self, request: web.Request, handler):
        """Comprehensive security middleware with multiple validation layers."""
        start_time = asyncio.get_event_loop().time()
        client_ip = request.remote
        user_agent = request.headers.get('User-Agent', 'Unknown')
        
        try:
            # 1. Basic request validation
            content_length = int(request.headers.get('Content-Length', 0))
            if content_length > self.config['max_request_size']:
                raise SecurityValidationError("Request too large")
            
            # 2. Rate limiting check
            if not await self.rate_limiter.is_allowed(client_ip):
                AUTH_FAILURES.labels(reason='rate_limit').inc()
                await self.audit_logger.log(AuditEvent(
                    event_type='rate_limit_exceeded',
                    client_ip=client_ip,
                    user_agent=user_agent,
                    details={'endpoint': request.path}
                ))
                raise web.HTTPTooManyRequests(text="Rate limit exceeded")
            
            # 3. Matrix Appservice token validation (skip for public endpoints)
            public_endpoints = ['/health', '/metrics']
            if request.path not in public_endpoints:
                auth_header = request.headers.get('Authorization', '')
                if not auth_header.startswith('Bearer '):
                    raise SecurityValidationError("Missing or invalid authorization header")
                    
                token = auth_header[7:]  # Remove 'Bearer ' prefix
                if token != self.config['as_token']:
                    AUTH_FAILURES.labels(reason='invalid_token').inc()
                    await self.audit_logger.log(AuditEvent(
                        event_type=AuditEventType.INVALID_AUTH,
                        client_ip=client_ip,
                        user_agent=user_agent,
                        # SECURITY NOTE: Using "..." for token truncation display only, not path traversal
                        details={'token_prefix': token[:8] + '...' if len(token) > 8 else token}
                    ))
                    raise web.HTTPUnauthorized(text="Invalid appservice token")
            
            # 4. Content-Type validation for POST requests
            if request.method == 'POST':
                content_type = request.headers.get('Content-Type', '')
                if not content_type.startswith('application/json'):
                    raise SecurityValidationError("Invalid content type")
            
            # Process request
            response = await handler(request)
            
            # Log successful request
            duration = asyncio.get_event_loop().time() - start_time
            REQUEST_COUNT.labels(
                method=request.method,
                endpoint=request.path,
                status=response.status
            ).inc()
            REQUEST_DURATION.observe(duration)
            
            return response
            
        except SecurityValidationError as e:
            AUTH_FAILURES.labels(reason='validation_error').inc()
            await self.audit_logger.log(AuditEvent(
                event_type='security_validation_failed',
                client_ip=client_ip,
                user_agent=user_agent,
                details={'error': str(e), 'endpoint': request.path}
            ))
            raise web.HTTPBadRequest(text=str(e))
            
        except (web.HTTPUnauthorized, web.HTTPBadRequest, web.HTTPNotFound, 
                web.HTTPInternalServerError) as e:
            # HTTP exceptions should pass through unchanged
            raise e
            
        except Exception as e:
            # Log unexpected errors without exposing internal details
            self.log.error("Unexpected error in security middleware", 
                          error=str(e), client_ip=client_ip, endpoint=request.path)
            await self.audit_logger.log(AuditEvent(
                event_type='internal_error',
                client_ip=client_ip,
                user_agent=user_agent,
                details={'endpoint': request.path}
            ))
            raise web.HTTPInternalServerError(text="Internal server error")
    
    async def handle_transactions(self, request: web.Request) -> web.Response:
        """
        Handle Matrix transactions containing room events.
        
        This is the main entry point for Matrix events. Implements:
        - Transaction validation and deduplication
        - Event filtering and security checks
        - Command parsing and execution
        - Response formatting
        """
        try:
            # Parse transaction data
            transaction_data = await request.json()
            
            # Validate transaction structure
            if 'events' not in transaction_data:
                raise MatrixBridgeError("Missing events in transaction")
            
            txn_id = request.match_info.get('txnId', 'unknown')
            self.log.info("Processing Matrix transaction", 
                         txn_id=txn_id, 
                         event_count=len(transaction_data['events']))
            
            # Process each event in the transaction
            for event in transaction_data['events']:
                try:
                    await self._process_event(event, txn_id)
                except Exception as e:
                    self.log.error("Failed to process event", 
                                  error=str(e), event_id=event.get('event_id'))
                    # Continue processing other events
                    continue
            
            return web.json_response({})
            
        except json.JSONDecodeError:
            raise web.HTTPBadRequest(text="Invalid JSON")
        except Exception as e:
            self.log.error("Transaction processing failed", error=str(e))
            raise web.HTTPInternalServerError(text="Transaction processing failed")
    
    async def _process_event(self, event: Dict[str, Any], txn_id: str) -> None:
        """
        Process individual Matrix events with security validation.
        
        Filters for relevant events and executes commands with full security checks.
        """
        # Only process text messages in rooms  
        if event.get('type') != 'm.room.message':
            return
            
        content = event.get('content', {})
        if content.get('msgtype') != 'm.text':
            return
            
        body = content.get('body', '').strip()
        if not body.startswith('!'):  # Commands must start with !
            return
            
        # Extract event metadata
        sender = event.get('sender', '')
        room_id = event.get('room_id', '')
        event_id = event.get('event_id', '')
        
        self.log.info("Processing command", 
                     sender=sender, room_id=room_id, 
                     command=body[:50], event_id=event_id)
        
        try:
            # 1. Authenticate and authorize user
            user_info = await self.oidc_circuit_breaker.call(
                self.oidc_validator.validate_user, sender
            )
            
            # 2. Parse and validate command
            command_info = self.command_parser.parse_command(body)
            
            # 3. Log command attempt
            await self.audit_logger.log(AuditEvent(
                event_type='command_attempt',
                user_id=sender,
                room_id=room_id,
                details={
                    'command': command_info.command,
                    'args': command_info.args,
                    'user_groups': user_info.get('groups', [])
                }
            ))
            
            # 4. Execute command with circuit breaker
            result = await self.systemd_circuit_breaker.call(
                self._execute_command, command_info, user_info
            )
            
            # 5. Send response to Matrix room
            await self._send_response(room_id, result)
            
            # 6. Log successful command
            COMMAND_COUNT.labels(
                command=command_info.command,
                status='success',
                user=sender
            ).inc()
            
            await self.audit_logger.log(AuditEvent(
                event_type='command_success',
                user_id=sender,
                room_id=room_id,
                details={
                    'command': command_info.command,
                    'result': result.get('status', 'unknown')
                }
            ))
            
        except (AuthenticationError, AuthorizationError) as e:
            error_msg = f"Authentication failed: {str(e)}"
            self.log.warning("Command auth failed", sender=sender, error=str(e))
            
            COMMAND_COUNT.labels(
                command=body.split()[0] if body.split() else 'unknown',
                status='auth_failed',
                user=sender
            ).inc()
            
            await self.audit_logger.log(AuditEvent(
                event_type='command_auth_failed',
                user_id=sender,
                room_id=room_id,
                details={'error': str(e), 'command': body[:100]}
            ))
            
            await self._send_error(room_id, error_msg)
            
        except CommandValidationError as e:
            error_msg = f"Invalid command: {str(e)}"
            self.log.warning("Command validation failed", error=str(e))
            
            COMMAND_COUNT.labels(
                command=body.split()[0] if body.split() else 'unknown',
                status='validation_failed',
                user=sender
            ).inc()
            
            await self._send_error(room_id, error_msg)
            
        except CircuitBreakerError as e:
            error_msg = "Service temporarily unavailable"
            self.log.error("Circuit breaker open", error=str(e))
            await self._send_error(room_id, error_msg)
            
        except Exception as e:
            self.log.error("Command execution failed", error=str(e), sender=sender)
            
            COMMAND_COUNT.labels(
                command=body.split()[0] if body.split() else 'unknown',
                status='failed',
                user=sender
            ).inc()
            
            await self.audit_logger.log(AuditEvent(
                event_type='command_failed',
                user_id=sender,
                room_id=room_id,
                details={'error': str(e), 'command': body[:100]}
            ))
            
            # Provide more specific error messages for common failure types
            error_str = str(e).lower()
            if 'invalid token' in error_str or 'authentication' in error_str:
                await self._send_error(room_id, "Authentication failed")
            else:
                await self._send_error(room_id, "Command execution failed")
    
    async def _execute_command(self, command_info, user_info: Dict[str, Any]) -> Dict[str, Any]:
        """Execute validated command with systemd integration."""
        command = command_info.command
        args = command_info.args
        
        self.log.info("Executing command", command=command, args=args)
        
        if command == 'start-agent':
            if not args:
                raise CommandValidationError("Agent type required for start-agent")
            agent_type = args[0]
            result = await self.agent_controller.start_agent(agent_type)
            
            SYSTEMD_OPERATIONS.labels(
                operation='start',
                agent=agent_type,
                status='success' if result.get('success') else 'failed'
            ).inc()
            
        elif command == 'stop-agent':
            if not args:
                raise CommandValidationError("Agent type required for stop-agent")
            agent_type = args[0]
            result = await self.agent_controller.stop_agent(agent_type)
            
            SYSTEMD_OPERATIONS.labels(
                operation='stop',
                agent=agent_type,
                status='success' if result.get('success') else 'failed'
            ).inc()
            
        elif command == 'status-agent':
            if not args:
                raise CommandValidationError("Agent type required for status-agent")
            agent_type = args[0]
            result = await self.agent_controller.get_status(agent_type)
            
        elif command == 'list-agents':
            result = await self.agent_controller.list_agents()
            
        else:
            raise CommandValidationError(f"Unknown command: {command}")
        
        return result
    
    async def _send_response(self, room_id: str, result: Dict[str, Any]) -> None:
        """Send command result to Matrix room."""
        # Format result as user-friendly message
        if result.get('success'):
            message = f"✅ {result.get('message', 'Command completed successfully')}"
        else:
            message = f"❌ {result.get('error', 'Command failed')}"
        
        # Add details if available
        if 'details' in result:
            details = result['details']
            if isinstance(details, dict):
                detail_lines = []
                for k, v in details.items():
                    # Format memory usage from bytes to MB
                    if k == 'memory_usage' and v is not None and isinstance(v, (int, float)):
                        v = f"{v / (1024 * 1024):.0f}MB"
                    # Format summary data nicely
                    elif k == 'summary' and isinstance(v, dict):
                        summary_parts = [f"{sk}: {sv}" for sk, sv in v.items()]
                        v = ", ".join(summary_parts)
                    detail_lines.append(f"{k}: {v}")
                message += f"\n\n📊 Details:\n" + "\n".join(detail_lines)
        
        await self._send_matrix_message(room_id, message)
    
    async def _send_error(self, room_id: str, error_message: str) -> None:
        """Send error message to Matrix room."""
        message = f"⚠️ {error_message}"
        await self._send_matrix_message(room_id, message)
    
    async def _send_matrix_message(self, room_id: str, message: str) -> None:
        """Send message to Matrix room using Client-Server API."""
        try:
            url = f"{self.config['homeserver_url']}/_matrix/client/r0/rooms/{room_id}/send/m.room.message"
            
            # Use server-to-server authentication  
            headers = {
                'Authorization': f"Bearer {self.config['as_token']}",
                'Content-Type': 'application/json'
            }
            
            data = {
                'msgtype': 'm.text',
                'body': message
            }
            
            async with self.session.put(
                f"{url}/{asyncio.get_event_loop().time()}", 
                headers=headers, 
                json=data,
                timeout=self.config['request_timeout']
            ) as response:
                if response.status != 200:
                    self.log.error("Failed to send Matrix message", 
                                  status=response.status, 
                                  response=await response.text())
                    
        except Exception as e:
            self.log.error("Error sending Matrix message", error=str(e))
    
    async def handle_users(self, request: web.Request) -> web.Response:
        """Handle user queries - return 404 for all users (we don't manage users)."""
        return web.json_response({'errcode': 'M_NOT_FOUND', 'error': 'User not found'}, status=404)
    
    async def handle_rooms(self, request: web.Request) -> web.Response:
        """Handle room queries - return 404 for all rooms (we don't manage rooms)."""
        return web.json_response({'errcode': 'M_NOT_FOUND', 'error': 'Room not found'}, status=404)
    
    async def health_check(self, request: web.Request) -> web.Response:
        """Health check endpoint."""
        health_status = {
            'status': 'healthy',
            'version': '1.0.0',
            'timestamp': asyncio.get_event_loop().time(),
            'components': {
                'oidc_validator': self.oidc_circuit_breaker.state,
                'systemd_controller': self.systemd_circuit_breaker.state,
                'rate_limiter': 'healthy'
            }
        }
        
        # Check component health
        overall_healthy = all(
            status != 'open' for status in [
                self.oidc_circuit_breaker.state,
                self.systemd_circuit_breaker.state
            ]
        )
        
        if not overall_healthy:
            health_status['status'] = 'degraded'
            return web.json_response(health_status, status=503)
            
        return web.json_response(health_status)
    
    async def metrics_handler(self, request: web.Request) -> web.Response:
        """Prometheus metrics endpoint."""
        return web.Response(
            text=generate_latest().decode('utf-8'),
            headers={'Content-Type': CONTENT_TYPE_LATEST}
        )
    
    def create_app(self) -> web.Application:
        """Create and configure the aiohttp application."""
        app = web.Application(middlewares=[self.security_middleware])
        
        # Matrix Appservice API endpoints
        app.router.add_put(
            '/_matrix/app/v1/transactions/{txnId}',
            self.handle_transactions
        )
        app.router.add_get(
            '/_matrix/app/v1/users/{userId}',
            self.handle_users
        )
        app.router.add_get(
            '/_matrix/app/v1/rooms/{roomAlias}',
            self.handle_rooms
        )
        
        # Health and metrics endpoints
        app.router.add_get('/health', self.health_check)
        app.router.add_get('/metrics', self.metrics_handler)
        
        return app
    
    async def start(self) -> None:
        """Start the Matrix bridge service."""
        self.log.info("Starting Matrix Appservice Bridge", 
                     host=self.config['host'], 
                     port=self.config['port'])
        
        # Initialize HTTP session
        self.session = ClientSession()
        
        # Initialize components
        await self.audit_logger.initialize()
        await self.agent_controller.initialize()
        await self.rate_limiter.start()
        
        # Create application
        self.app = self.create_app()
        
        # Start web server
        runner = web.AppRunner(self.app)
        await runner.setup()
        
        site = web.TCPSite(
            runner,
            self.config['host'],
            self.config['port']
        )
        await site.start()
        
        self.log.info("Matrix bridge started successfully")
    
    async def stop(self) -> None:
        """Stop the Matrix bridge service."""
        self.log.info("Stopping Matrix bridge")
        
        if self.session:
            await self.session.close()
        
        await self.rate_limiter.stop()
        await self.audit_logger.close()
        
        self.log.info("Matrix bridge stopped")


async def main():
    """Main entry point for the Matrix bridge."""
    # Handle shutdown signals
    bridge = None
    
    async def shutdown_handler():
        if bridge:
            await bridge.stop()
        sys.exit(0)
    
    # Register signal handlers
    loop = asyncio.get_event_loop()
    for sig in [signal.SIGINT, signal.SIGTERM]:
        loop.add_signal_handler(sig, lambda: asyncio.create_task(shutdown_handler()))
    
    try:
        # Start bridge
        bridge = MatrixAppserviceBridge()
        await bridge.start()
        
        # Keep running
        while True:
            await asyncio.sleep(1)
            
    except Exception as e:
        logger.error("Bridge startup failed", error=str(e))
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())