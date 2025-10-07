#!/usr/bin/env python3
"""Mattermost bridge for RAVE chat-based agent control."""

import asyncio
import json
import os
import signal
import sys
from typing import Any, Dict, Optional

import aiohttp
from aiohttp import web
from aiohttp.web_middlewares import middleware
import structlog
import yaml
from prometheus_client import (
    Counter,
    Histogram,
    CONTENT_TYPE_LATEST,
    generate_latest,
)

from chat_control import (
    AdaptiveRateLimiter,
    AgentControlError,
    AuthenticationError,
    AuthorizationError,
    CircuitBreaker,
    CircuitBreakerError,
    CommandValidationError,
    GitLabOIDCValidator,
    SecureCommandParser,
    SecurityAuditLogger,
    AuditEvent,
    SystemdAgentController,
)

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
        structlog.processors.JSONRenderer(),
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Prometheus metrics
REQUEST_COUNT = Counter(
    "chat_control_requests_total",
    "Total chat control requests",
    ["endpoint", "status"],
)
REQUEST_DURATION = Histogram(
    "chat_control_request_duration_seconds",
    "Chat control request duration",
)
COMMAND_COUNT = Counter(
    "chat_control_commands_total",
    "Total commands processed",
    ["command", "status", "user"],
)
AUTH_FAILURES = Counter(
    "chat_control_auth_failures_total",
    "Total authentication failures",
    ["reason"],
)
SYSTEMD_OPERATIONS = Counter(
    "chat_control_systemd_operations_total",
    "Total systemd operations",
    ["operation", "agent", "status"],
)


class MattermostBridgeError(Exception):
    """Base exception for Mattermost bridge errors."""


class MattermostBridge:
    """Secure Mattermost bridge providing agent control commands."""

    def __init__(self, config_path: str = "bridge_config.yaml") -> None:
        self.config = self._load_config(config_path)
        self.log = logger.bind(component="mattermost_bridge")

        self.command_parser = SecureCommandParser(
            allowed_commands=self.config.get(
                "allowed_commands",
                ["start-agent", "stop-agent", "status-agent", "list-agents"],
            )
        )

        self.identity_validator = GitLabOIDCValidator(
            gitlab_url=self.config["gitlab_url"],
            client_id=self.config["oidc_client_id"],
            client_secret=self.config["oidc_client_secret"],
            allowed_groups=self.config.get("allowed_groups"),
            api_token=self.config.get("gitlab_api_token"),
        )

        self.agent_controller = SystemdAgentController(
            allowed_services=self.config.get("allowed_agent_services", []),
            service_prefix=self.config.get("agent_service_prefix", "rave-agent-"),
        )

        self.audit_logger = SecurityAuditLogger(
            log_file=self.config.get(
                "audit_log_file", "/var/log/mattermost-bridge/audit.log"
            )
        )

        self.rate_limiter = AdaptiveRateLimiter(
            requests_per_minute=self.config.get("rate_limit_rpm", 30),
            burst_size=self.config.get("rate_limit_burst", 5),
        )

        self.systemd_circuit_breaker = CircuitBreaker(
            failure_threshold=5,
            recovery_timeout=60,
            expected_exception=AgentControlError,
        )

        self.identity_circuit_breaker = CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=300,
            expected_exception=AuthenticationError,
        )

        self.session: Optional[aiohttp.ClientSession] = None
        self.app: Optional[web.Application] = None

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        try:
            with open(config_path, "r", encoding="utf-8") as handle:
                config = yaml.safe_load(handle) or {}
        except FileNotFoundError:
            logger.warning("Config file not found, using defaults", path=config_path)
            config = {}

        defaults = {
            "host": "127.0.0.1",
            "port": 9100,
            "max_request_size": 1024 * 1024,
            "request_timeout": 30,
            "enable_metrics": True,
            "metrics_port": 9101,
            "log_level": "INFO",
            "rate_limit_rpm": 30,
            "rate_limit_burst": 5,
            "allowed_agent_services": [
                "backend-architect",
                "frontend-developer",
                "test-writer-fixer",
                "ui-designer",
                "devops-automator",
                "api-tester",
            ],
            "agent_service_prefix": "rave-agent-",
        }

        for key, value in defaults.items():
            config.setdefault(key, value)

        required_keys = [
            "gitlab_url",
            "oidc_client_id",
            "oidc_client_secret",
            "mattermost_url",
            "outgoing_token",
            "bot_access_token",
        ]
        missing = [key for key in required_keys if key not in config]
        if missing:
            raise MattermostBridgeError(f"Missing required config keys: {missing}")

        config["mattermost_url"] = config["mattermost_url"].rstrip("/")
        config["gitlab_url"] = config["gitlab_url"].rstrip("/")

        return config

    @middleware
    async def security_middleware(self, request: web.Request, handler):
        start_time = asyncio.get_event_loop().time()
        client_ip = request.remote
        path = request.path

        try:
            content_length = int(request.headers.get("Content-Length", 0))
            if content_length > self.config["max_request_size"]:
                raise MattermostBridgeError("Request too large")

            if not await self.rate_limiter.is_allowed(client_ip or "unknown"):
                AUTH_FAILURES.labels(reason="rate_limit").inc()
                await self.audit_logger.log(
                    AuditEvent(
                        event_type="rate_limit_exceeded",
                        client_ip=client_ip,
                        details={"endpoint": path},
                    )
                )
                raise web.HTTPTooManyRequests(text="Rate limit exceeded")

            response = await handler(request)
            duration = asyncio.get_event_loop().time() - start_time
            REQUEST_COUNT.labels(endpoint=path, status=response.status).inc()
            REQUEST_DURATION.observe(duration)
            return response

        except MattermostBridgeError as exc:
            AUTH_FAILURES.labels(reason="validation_error").inc()
            await self.audit_logger.log(
                AuditEvent(
                    event_type="security_validation_failed",
                    client_ip=client_ip,
                    details={"endpoint": path, "error": str(exc)},
                )
            )
            raise web.HTTPBadRequest(text=str(exc))
        except web.HTTPException:
            raise
        except Exception as exc:  # noqa: BLE001
            self.log.error(
                "Unexpected error in security middleware",
                error=str(exc),
                endpoint=path,
                client_ip=client_ip,
            )
            await self.audit_logger.log(
                AuditEvent(
                    event_type="internal_error",
                    client_ip=client_ip,
                    details={"endpoint": path},
                )
            )
            raise web.HTTPInternalServerError(text="Internal server error")

    async def handle_webhook(self, request: web.Request) -> web.Response:
        payload = await self._parse_payload(request)

        try:
            token = payload.get("token") or request.headers.get("X-Mattermost-Token")
            if token != self.config["outgoing_token"]:
                AUTH_FAILURES.labels(reason="invalid_token").inc()
                raise web.HTTPUnauthorized(text="Invalid webhook token")

            text = (payload.get("text") or "").strip()
            if not text:
                return web.json_response({"text": "No command supplied"}, status=200)

            if not text.startswith("!"):
                return web.json_response({"text": "Commands must start with !"}, status=200)

            user_id = payload.get("user_id", "unknown")
            channel_id = payload.get("channel_id")
            username = payload.get("user_name", user_id)

            if not await self.rate_limiter.is_allowed(user_id):
                AUTH_FAILURES.labels(reason="user_rate_limit").inc()
                await self.audit_logger.log(
                    AuditEvent(
                        event_type="rate_limit_exceeded",
                        user_id=user_id,
                        details={"endpoint": "/webhook"},
                    )
                )
                raise web.HTTPTooManyRequests(text="Rate limit exceeded")

            user_info = await self.identity_circuit_breaker.call(
                self.identity_validator.validate_user,
                username,
            )

            command_info = self.command_parser.parse_command(text)

            await self.audit_logger.log(
                AuditEvent(
                    event_type="command_attempt",
                    user_id=username,
                    details={
                        "command": command_info.command,
                        "args": command_info.args,
                        "channel_id": channel_id,
                    },
                )
            )

            result = await self.systemd_circuit_breaker.call(
                self._execute_command,
                command_info,
                user_info,
            )

            await self._send_response(channel_id, result)

            COMMAND_COUNT.labels(
                command=command_info.command,
                status="success",
                user=username,
            ).inc()

            await self.audit_logger.log(
                AuditEvent(
                    event_type="command_success",
                    user_id=username,
                    details={
                        "command": command_info.command,
                        "result": result.get("status", "unknown"),
                    },
                )
            )

            return web.json_response({"text": "Command processed"}, status=200)

        except (AuthenticationError, AuthorizationError) as exc:
            COMMAND_COUNT.labels(
                command=text.split()[0] if text else "unknown",
                status="auth_failed",
                user=payload.get("user_name", "unknown"),
            ).inc()
            await self.audit_logger.log(
                AuditEvent(
                    event_type="command_auth_failed",
                    user_id=payload.get("user_name"),
                    details={"error": str(exc), "command": text[:100]},
                )
            )
            await self._send_error(payload.get("channel_id"), f"Authentication failed: {exc}")
            raise web.HTTPUnauthorized(text="Authentication failed")

        except CommandValidationError as exc:
            COMMAND_COUNT.labels(
                command=text.split()[0] if text else "unknown",
                status="validation_failed",
                user=payload.get("user_name", "unknown"),
            ).inc()
            await self._send_error(payload.get("channel_id"), f"Invalid command: {exc}")
            raise web.HTTPBadRequest(text=str(exc))

        except CircuitBreakerError as exc:
            await self._send_error(payload.get("channel_id"), "Service temporarily unavailable")
            raise web.HTTPServiceUnavailable(text=str(exc))

        except MattermostBridgeError as exc:
            await self._send_error(payload.get("channel_id"), str(exc))
            raise web.HTTPBadRequest(text=str(exc))

        except Exception as exc:  # noqa: BLE001
            COMMAND_COUNT.labels(
                command=text.split()[0] if text else "unknown",
                status="failed",
                user=payload.get("user_name", "unknown"),
            ).inc()
            await self.audit_logger.log(
                AuditEvent(
                    event_type="command_failed",
                    user_id=payload.get("user_name"),
                    details={"error": str(exc), "command": text[:100]},
                )
            )
            await self._send_error(payload.get("channel_id"), "Command execution failed")
            raise web.HTTPInternalServerError(text="Command execution failed")

    async def _parse_payload(self, request: web.Request) -> Dict[str, Any]:
        content_type = request.headers.get("Content-Type", "")
        if "application/json" in content_type:
            return await request.json()
        if "application/x-www-form-urlencoded" in content_type:
            data = await request.post()
            return {key: data.get(key) for key in data}  # type: ignore[return-value]
        # Default to json attempt
        try:
            return await request.json()
        except json.JSONDecodeError as exc:
            raise MattermostBridgeError("Invalid payload format") from exc

    async def _execute_command(self, command_info, user_info: Dict[str, Any]) -> Dict[str, Any]:
        command = command_info.command
        args = command_info.args

        if command == "start-agent":
            if not args:
                raise CommandValidationError("Agent type required for start-agent")
            agent_type = args[0]
            result = await self.agent_controller.start_agent(agent_type)
            SYSTEMD_OPERATIONS.labels(
                operation="start",
                agent=agent_type,
                status="success" if result.get("success") else "failed",
            ).inc()

        elif command == "stop-agent":
            if not args:
                raise CommandValidationError("Agent type required for stop-agent")
            agent_type = args[0]
            result = await self.agent_controller.stop_agent(agent_type)
            SYSTEMD_OPERATIONS.labels(
                operation="stop",
                agent=agent_type,
                status="success" if result.get("success") else "failed",
            ).inc()

        elif command == "status-agent":
            if not args:
                raise CommandValidationError("Agent type required for status-agent")
            agent_type = args[0]
            result = await self.agent_controller.get_status(agent_type)

        elif command == "list-agents":
            result = await self.agent_controller.list_agents()

        else:
            raise CommandValidationError(f"Unknown command: {command}")

        return result

    async def _send_response(self, channel_id: Optional[str], result: Dict[str, Any]) -> None:
        if not channel_id:
            return

        if result.get("success"):
            message = f"✅ {result.get('message', 'Command completed successfully')}"
        else:
            message = f"❌ {result.get('error', 'Command failed')}"

        if "details" in result:
            details = result["details"]
            if isinstance(details, dict):
                detail_lines = []
                for key, value in details.items():
                    if key == "memory_usage" and isinstance(value, (int, float)):
                        value = f"{value / (1024 * 1024):.0f}MB"
                    elif key == "summary" and isinstance(value, dict):
                        value = ", ".join(f"{k}: {v}" for k, v in value.items())
                    detail_lines.append(f"{key}: {value}")
                if detail_lines:
                    message += "\n\n📊 Details:\n" + "\n".join(detail_lines)

        await self._post_message(channel_id, message)

    async def _send_error(self, channel_id: Optional[str], message: str) -> None:
        if not channel_id:
            return
        await self._post_message(channel_id, f"⚠️ {message}")

    async def _post_message(self, channel_id: str, message: str) -> None:
        if not self.session:
            return

        url = f"{self.config['mattermost_url']}/api/v4/posts"
        payload = {"channel_id": channel_id, "message": message}
        headers = {
            "Authorization": f"Bearer {self.config['bot_access_token']}",
            "Content-Type": "application/json",
        }

        try:
            async with self.session.post(
                url,
                json=payload,
                headers=headers,
                timeout=self.config["request_timeout"],
            ) as response:
                if response.status >= 300:
                    self.log.error(
                        "Failed to send Mattermost message",
                        status=response.status,
                        body=await response.text(),
                    )
        except Exception as exc:  # noqa: BLE001
            self.log.error("Error sending Mattermost message", error=str(exc))

    async def health_check(self, request: web.Request) -> web.Response:
        components = {
            "identity_validator": self.identity_circuit_breaker.state,
            "systemd_controller": self.systemd_circuit_breaker.state,
            "rate_limiter": "healthy",
        }
        status = (
            "degraded"
            if any(state == "open" for state in components.values())
            else "healthy"
        )
        payload = {
            "status": status,
            "components": components,
            "timestamp": asyncio.get_event_loop().time(),
        }
        return web.json_response(payload, status=200 if status == "healthy" else 503)

    async def metrics_handler(self, request: web.Request) -> web.Response:
        return web.Response(
            text=generate_latest().decode("utf-8"),
            headers={"Content-Type": CONTENT_TYPE_LATEST},
        )

    def create_app(self) -> web.Application:
        app = web.Application(middlewares=[self.security_middleware])
        app.router.add_post("/webhook", self.handle_webhook)
        app.router.add_get("/health", self.health_check)
        app.router.add_get("/metrics", self.metrics_handler)
        return app

    async def start(self) -> None:
        self.log.info("Starting Mattermost bridge", host=self.config["host"], port=self.config["port"])
        self.session = aiohttp.ClientSession()
        await self.audit_logger.initialize()
        await self.agent_controller.initialize()
        await self.rate_limiter.start()

        self.app = self.create_app()
        runner = web.AppRunner(self.app)
        await runner.setup()
        site = web.TCPSite(runner, self.config["host"], self.config["port"])
        await site.start()
        self.log.info("Mattermost bridge started successfully")

    async def stop(self) -> None:
        self.log.info("Stopping Mattermost bridge")
        if self.session:
            await self.session.close()
        await self.rate_limiter.stop()
        await self.audit_logger.close()
        self.log.info("Mattermost bridge stopped")


async def main() -> None:
    bridge: Optional[MattermostBridge] = None

    async def shutdown_handler() -> None:
        if bridge:
            await bridge.stop()
        sys.exit(0)

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda: asyncio.create_task(shutdown_handler()))

    try:
        config_path = os.environ.get("CHAT_BRIDGE_CONFIG", "bridge_config.yaml")
        bridge = MattermostBridge(config_path=config_path)
        await bridge.start()
        while True:
            await asyncio.sleep(1)
    except Exception as exc:  # noqa: BLE001
        logger.error("Bridge startup failed", error=str(exc))
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
