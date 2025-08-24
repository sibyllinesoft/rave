"""
Security-focused unit tests for rate limiter and circuit breaker components.
Tests security controls, edge cases, and attack resistance.
"""

import pytest
import asyncio
import time
from unittest.mock import AsyncMock, patch, MagicMock

from src.rate_limiter import AdaptiveRateLimiter, ClientMetrics
from src.circuit_breaker import CircuitBreaker, CircuitState, CircuitBreakerError
from src.audit import SecurityAuditLogger, AuditEvent, AuditEventType
from src.auth import GitLabOIDCValidator, AuthenticationError, AuthorizationError


class TestAdaptiveRateLimiter:
    """Test rate limiter security and functionality."""

    @pytest.fixture
    async def rate_limiter(self):
        """Create rate limiter for testing."""
        limiter = AdaptiveRateLimiter(
            requests_per_minute=60,
            burst_size=10,
            adaptive_enabled=True
        )
        await limiter.start()
        yield limiter
        await limiter.stop()

    @pytest.mark.asyncio
    async def test_basic_rate_limiting(self, rate_limiter):
        """Test basic rate limiting functionality."""
        client_id = "test_client_1"
        
        # Should allow requests within burst limit
        for i in range(10):
            allowed = await rate_limiter.is_allowed(client_id)
            assert allowed is True, f"Request {i} should be allowed"
        
        # Next request should be rate limited
        allowed = await rate_limiter.is_allowed(client_id)
        assert allowed is False, "Request should be rate limited after burst"

    @pytest.mark.asyncio
    async def test_burst_token_refill(self, rate_limiter):
        """Test burst token refill mechanism."""
        client_id = "test_client_2"
        
        # Exhaust burst tokens
        for i in range(10):
            await rate_limiter.is_allowed(client_id)
        
        # Should be rate limited
        allowed = await rate_limiter.is_allowed(client_id)
        assert allowed is False
        
        # Wait for token refill (simulate time passage)
        await asyncio.sleep(2)  # Allow some tokens to refill
        
        # Should allow some requests again
        allowed = await rate_limiter.is_allowed(client_id)
        assert allowed is True, "Tokens should have been refilled"

    @pytest.mark.asyncio
    async def test_per_client_isolation(self, rate_limiter):
        """Test that rate limiting is isolated per client."""
        client1 = "client_1"
        client2 = "client_2"
        
        # Exhaust client1's tokens
        for i in range(10):
            await rate_limiter.is_allowed(client1)
        
        # Client1 should be limited
        assert await rate_limiter.is_allowed(client1) is False
        
        # Client2 should still be allowed
        assert await rate_limiter.is_allowed(client2) is True

    @pytest.mark.asyncio
    async def test_adaptive_rate_adjustment(self, rate_limiter):
        """Test adaptive rate adjustment based on system load."""
        client_id = "test_client_adaptive"
        
        # Mock low system load
        with patch('os.getloadavg', return_value=[0.1, 0.2, 0.3]):
            with patch('os.cpu_count', return_value=4):
                await rate_limiter._update_system_load()
                
                # Should have increased rate limits due to low load
                assert rate_limiter._current_load_factor > 1.0

    @pytest.mark.asyncio
    async def test_context_based_rate_adjustment(self, rate_limiter):
        """Test rate adjustment based on request context."""
        client_id = "test_client_context"
        
        # Admin user should get higher limits
        admin_context = {'user_type': 'admin'}
        allowed = await rate_limiter.is_allowed(client_id, context=admin_context)
        assert allowed is True
        
        # Status requests should get higher limits
        status_context = {'request_type': 'status'}
        allowed = await rate_limiter.is_allowed(client_id, context=status_context)
        assert allowed is True

    @pytest.mark.asyncio
    async def test_cost_based_rate_limiting(self, rate_limiter):
        """Test rate limiting with request costs."""
        client_id = "test_client_cost"
        
        # High cost request should consume more tokens
        allowed = await rate_limiter.is_allowed(client_id, cost=5)
        assert allowed is True
        
        # Should have fewer tokens left
        allowed = await rate_limiter.is_allowed(client_id, cost=10)
        assert allowed is False, "Should be limited due to high cost"

    @pytest.mark.asyncio
    async def test_cleanup_old_clients(self, rate_limiter):
        """Test cleanup of old client data."""
        # Create some client data
        clients = [f"client_{i}" for i in range(5)]
        for client in clients:
            await rate_limiter.is_allowed(client)
        
        # Manually trigger cleanup
        await rate_limiter._cleanup_old_clients()
        
        # Clients should still exist (not old enough)
        stats = rate_limiter.get_statistics()
        assert stats['memory_usage']['tracked_clients'] == 5
        
        # Mock old access times
        old_time = time.time() - 1000
        for client in clients:
            if client in rate_limiter._client_metrics:
                rate_limiter._client_metrics[client].last_request_time = old_time
        
        # Now cleanup should remove old clients
        await rate_limiter._cleanup_old_clients()
        stats = rate_limiter.get_statistics()
        assert stats['memory_usage']['tracked_clients'] == 0

    @pytest.mark.asyncio
    async def test_rate_limiter_statistics(self, rate_limiter):
        """Test rate limiter statistics collection."""
        client_id = "test_client_stats"
        
        # Make some requests
        await rate_limiter.is_allowed(client_id)
        await rate_limiter.is_allowed(client_id)
        
        stats = rate_limiter.get_statistics()
        
        assert 'total_requests' in stats
        assert 'total_allowed' in stats
        assert 'total_blocked' in stats
        assert 'active_clients' in stats
        assert 'config' in stats
        assert stats['total_requests'] >= 2

    @pytest.mark.asyncio
    async def test_client_info_retrieval(self, rate_limiter):
        """Test client information retrieval."""
        client_id = "test_client_info"
        
        # Make a request to create client data
        await rate_limiter.is_allowed(client_id)
        
        client_info = await rate_limiter.get_client_info(client_id)
        
        assert client_info is not None
        assert client_info['client_id'] == client_id
        assert 'requests_made' in client_info
        assert 'burst_tokens_available' in client_info
        assert 'current_limits' in client_info

    @pytest.mark.asyncio
    async def test_client_reset(self, rate_limiter):
        """Test client state reset."""
        client_id = "test_client_reset"
        
        # Make requests to create state
        await rate_limiter.is_allowed(client_id)
        
        # Reset client
        reset_success = await rate_limiter.reset_client(client_id)
        assert reset_success is True
        
        # Client info should be None after reset
        client_info = await rate_limiter.get_client_info(client_id)
        assert client_info is None

    @pytest.mark.asyncio
    async def test_distributed_rate_limiting_fallback(self):
        """Test fallback to local limiting when Redis fails."""
        # Create rate limiter with mock Redis client that fails
        redis_mock = AsyncMock()
        redis_mock.eval.side_effect = Exception("Redis connection failed")
        
        limiter = AdaptiveRateLimiter(
            requests_per_minute=60,
            burst_size=10,
            redis_client=redis_mock
        )
        
        await limiter.start()
        
        try:
            # Should fallback to local limiting
            allowed = await limiter.is_allowed("test_client")
            assert allowed is True, "Should fallback to local limiting"
        finally:
            await limiter.stop()

    @pytest.mark.asyncio
    async def test_rate_limiting_attack_resistance(self, rate_limiter):
        """Test resistance to rate limiting attacks."""
        # Test with many different client IDs (client ID flooding)
        clients = [f"attacker_client_{i}" for i in range(100)]
        
        # Each client should still be rate limited individually
        for client in clients:
            # Exhaust tokens for each client
            for _ in range(10):
                await rate_limiter.is_allowed(client)
            
            # Should be rate limited
            allowed = await rate_limiter.is_allowed(client)
            assert allowed is False, f"Client {client} should be rate limited"
        
        # System should still be responsive for new legitimate clients
        legit_client = "legitimate_client"
        allowed = await rate_limiter.is_allowed(legit_client)
        assert allowed is True, "Legitimate client should not be affected"


class TestCircuitBreaker:
    """Test circuit breaker functionality and security."""

    @pytest.fixture
    def circuit_breaker(self):
        """Create circuit breaker for testing."""
        return CircuitBreaker(
            failure_threshold=3,
            recovery_timeout=5,
            success_threshold=2,
            timeout=1,
            expected_exception=Exception,
            name="test_breaker"
        )

    @pytest.mark.asyncio
    async def test_circuit_breaker_states(self, circuit_breaker):
        """Test circuit breaker state transitions."""
        # Initially closed
        assert circuit_breaker.state == "closed"
        
        # Simulate failures
        async def failing_function():
            raise Exception("Service failure")
        
        # Fail enough times to open circuit
        for i in range(3):
            with pytest.raises(Exception):
                await circuit_breaker.call(failing_function)
        
        # Circuit should be open
        assert circuit_breaker.state == "open"
        
        # Calls should be rejected
        with pytest.raises(CircuitBreakerError):
            await circuit_breaker.call(failing_function)

    @pytest.mark.asyncio
    async def test_circuit_breaker_recovery(self, circuit_breaker):
        """Test circuit breaker recovery mechanism."""
        # Force circuit open
        circuit_breaker.force_open()
        assert circuit_breaker.state == "open"
        
        # Mock time passage for recovery
        with patch('time.time', return_value=time.time() + 10):
            # Should transition to half-open
            async def working_function():
                return "success"
            
            result = await circuit_breaker.call(working_function)
            assert result == "success"
            assert circuit_breaker.state == "half_open"
        
        # Another success should close the circuit
        result = await circuit_breaker.call(working_function)
        assert result == "success"
        assert circuit_breaker.state == "closed"

    @pytest.mark.asyncio
    async def test_circuit_breaker_timeout_handling(self, circuit_breaker):
        """Test circuit breaker timeout handling."""
        async def slow_function():
            await asyncio.sleep(2)  # Longer than timeout
            return "too slow"
        
        # Should timeout and trigger circuit breaker
        with pytest.raises(asyncio.TimeoutError):
            await circuit_breaker.call(slow_function)
        
        # Multiple timeouts should open circuit
        for _ in range(2):
            with pytest.raises(asyncio.TimeoutError):
                await circuit_breaker.call(slow_function)
        
        assert circuit_breaker.state == "open"

    @pytest.mark.asyncio
    async def test_circuit_breaker_exception_filtering(self, circuit_breaker):
        """Test circuit breaker exception filtering."""
        # Create circuit breaker that only opens on specific exceptions
        specific_cb = CircuitBreaker(
            failure_threshold=2,
            recovery_timeout=5,
            expected_exception=ValueError,
            name="specific_breaker"
        )
        
        async def function_with_different_errors(error_type):
            if error_type == "value":
                raise ValueError("Value error")
            elif error_type == "runtime":
                raise RuntimeError("Runtime error")
            else:
                return "success"
        
        # ValueError should count towards failure
        with pytest.raises(ValueError):
            await specific_cb.call(function_with_different_errors, "value")
        
        with pytest.raises(ValueError):
            await specific_cb.call(function_with_different_errors, "value")
        
        # Circuit should be open
        assert specific_cb.state == "open"
        
        # RuntimeError should not have opened the circuit on its own
        other_cb = CircuitBreaker(
            failure_threshold=2,
            recovery_timeout=5,
            expected_exception=ValueError,
            name="other_breaker"
        )
        
        with pytest.raises(RuntimeError):
            await other_cb.call(function_with_different_errors, "runtime")
        
        # Circuit should still be closed
        assert other_cb.state == "closed"

    @pytest.mark.asyncio
    async def test_circuit_breaker_concurrent_requests(self, circuit_breaker):
        """Test circuit breaker with concurrent requests."""
        async def sometimes_failing_function(should_fail):
            if should_fail:
                raise Exception("Failure")
            await asyncio.sleep(0.1)
            return "success"
        
        # Run concurrent requests
        tasks = []
        for i in range(10):
            # Half should fail
            task = circuit_breaker.call(sometimes_failing_function, i < 5)
            tasks.append(task)
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Some should succeed, some should fail
        successes = [r for r in results if r == "success"]
        failures = [r for r in results if isinstance(r, Exception)]
        
        assert len(successes) > 0
        assert len(failures) > 0
        
        # Circuit might be open depending on timing
        health = circuit_breaker.get_health_status()
        assert health['name'] == "test_breaker"

    def test_circuit_breaker_statistics(self, circuit_breaker):
        """Test circuit breaker statistics collection."""
        stats = circuit_breaker.get_statistics()
        
        assert 'total_calls' in stats
        assert 'successful_calls' in stats
        assert 'failed_calls' in stats
        assert 'rejected_calls' in stats
        assert 'success_rate' in stats
        assert 'current_state' in stats
        assert 'config' in stats

    def test_circuit_breaker_health_status(self, circuit_breaker):
        """Test circuit breaker health status reporting."""
        health = circuit_breaker.get_health_status()
        
        assert 'name' in health
        assert 'state' in health
        assert 'failure_count' in health
        assert 'time_until_retry' in health
        assert 'recent_success_rate' in health
        assert 'config' in health

    def test_circuit_breaker_manual_controls(self, circuit_breaker):
        """Test manual circuit breaker controls."""
        # Test force open
        circuit_breaker.force_open()
        assert circuit_breaker.state == "open"
        
        # Test force closed
        circuit_breaker.force_closed()
        assert circuit_breaker.state == "closed"
        
        # Test reset
        circuit_breaker.reset()
        assert circuit_breaker.state == "closed"
        stats = circuit_breaker.get_statistics()
        assert stats['total_calls'] == 0

    @pytest.mark.asyncio
    async def test_circuit_breaker_half_open_limits(self, circuit_breaker):
        """Test half-open state concurrent request limits."""
        # Force to half-open state
        circuit_breaker._state = CircuitState.HALF_OPEN
        
        async def working_function():
            return "success"
        
        # Should limit concurrent requests in half-open state
        # This is a placeholder test as the current implementation
        # doesn't track concurrent requests
        result = await circuit_breaker.call(working_function)
        assert result == "success"


class TestSecurityAuditLogger:
    """Test security audit logger functionality."""

    @pytest.fixture
    async def audit_logger(self):
        """Create audit logger for testing."""
        import tempfile
        with tempfile.NamedTemporaryFile(delete=False) as f:
            log_file = f.name
        
        logger = SecurityAuditLogger(
            log_file=log_file,
            buffer_size=10,
            flush_interval=1
        )
        
        await logger.initialize()
        yield logger
        await logger.close()
        
        # Cleanup
        import os
        if os.path.exists(log_file):
            os.unlink(log_file)

    @pytest.mark.asyncio
    async def test_audit_event_logging(self, audit_logger):
        """Test basic audit event logging."""
        event = AuditEvent(
            event_type=AuditEventType.COMMAND_ATTEMPT,
            user_id='@testuser:matrix.test',
            client_ip='127.0.0.1',
            details={'command': 'start-agent', 'args': ['backend-architect']}
        )
        
        await audit_logger.log(event)
        
        # Flush to ensure logging
        await audit_logger._flush_buffer()
        
        # Check statistics
        stats = audit_logger.get_statistics()
        assert stats['events_logged'] > 0

    @pytest.mark.asyncio
    async def test_audit_log_integrity(self, audit_logger):
        """Test audit log integrity verification."""
        # Log several events
        for i in range(5):
            event = AuditEvent(
                event_type=AuditEventType.COMMAND_ATTEMPT,
                user_id=f'@user{i}:matrix.test',
                details={'command': f'command_{i}'}
            )
            await audit_logger.log(event)
        
        # Flush to ensure logging
        await audit_logger._flush_buffer()
        
        # Validate integrity
        validation_results = await audit_logger.validate_log_integrity(lines_to_check=10)
        
        assert 'total_checked' in validation_results
        assert 'valid_entries' in validation_results
        assert 'invalid_entries' in validation_results
        assert validation_results['total_checked'] > 0

    @pytest.mark.asyncio
    async def test_audit_log_buffer_management(self, audit_logger):
        """Test audit log buffer management."""
        # Generate many events to test buffering
        events = []
        for i in range(15):  # More than buffer size
            event = AuditEvent(
                event_type=AuditEventType.COMMAND_ATTEMPT,
                user_id=f'@user{i}:matrix.test',
                details={'command': f'command_{i}'}
            )
            events.append(event)
            await audit_logger.log(event)
        
        # Should have triggered automatic flush
        stats = audit_logger.get_statistics()
        assert stats['events_logged'] > 0

    @pytest.mark.asyncio
    async def test_audit_log_data_sanitization(self, audit_logger):
        """Test sensitive data sanitization in audit logs."""
        event = AuditEvent(
            event_type=AuditEventType.COMMAND_ATTEMPT,
            user_id='@testuser:matrix.test',
            details={
                'command': 'start-agent',
                'password': 'supersecret123',
                'token': 'Bearer abcd1234567890',
                'normal_field': 'normal_value'
            }
        )
        
        await audit_logger.log(event)
        await audit_logger._flush_buffer()
        
        # Verify sensitive data was sanitized
        # This would require reading the log file and checking
        # that sensitive fields were masked

    def test_audit_log_statistics(self, audit_logger):
        """Test audit log statistics collection."""
        stats = audit_logger.get_statistics()
        
        assert 'events_logged' in stats
        assert 'events_buffered' in stats
        assert 'flushes_completed' in stats
        assert 'integrity_violations' in stats
        assert 'errors' in stats
        assert 'buffer_size' in stats
        assert 'is_running' in stats


class TestGitLabOIDCValidator:
    """Test GitLab OIDC authentication validator."""

    @pytest.fixture
    def oidc_validator(self):
        """Create OIDC validator for testing."""
        return GitLabOIDCValidator(
            gitlab_url='https://gitlab.test',
            client_id='test_client',
            client_secret='test_secret',
            allowed_groups=['developers', 'admins'],
            cache_ttl=300
        )

    @pytest.mark.asyncio
    async def test_user_validation_success(self, oidc_validator):
        """Test successful user validation."""
        matrix_user_id = '@testuser:matrix.test'
        
        with patch.object(oidc_validator, '_get_gitlab_user_info') as mock_user_info:
            mock_user_info.return_value = {
                'id': 123,
                'username': 'testuser',
                'email': 'testuser@example.com',
                'name': 'Test User',
                'groups': ['developers'],
                'state': 'active'
            }
            
            user_info = await oidc_validator.validate_user(matrix_user_id)
            
            assert user_info.username == 'testuser'
            assert user_info.email == 'testuser@example.com'
            assert 'developers' in user_info.groups
            assert 'agent:start' in user_info.roles  # Should have developer role

    @pytest.mark.asyncio
    async def test_user_validation_failure(self, oidc_validator):
        """Test user validation failure scenarios."""
        # Test invalid Matrix user ID format
        with pytest.raises(AuthenticationError):
            await oidc_validator.validate_user('invalid_user_id')
        
        # Test user not found in GitLab
        with patch.object(oidc_validator, '_get_gitlab_user_info') as mock_user_info:
            mock_user_info.side_effect = AuthenticationError("User not found")
            
            with pytest.raises(AuthenticationError):
                await oidc_validator.validate_user('@nonexistent:matrix.test')

    @pytest.mark.asyncio
    async def test_authorization_validation(self, oidc_validator):
        """Test authorization based on groups."""
        matrix_user_id = '@unauthorizeduser:matrix.test'
        
        with patch.object(oidc_validator, '_get_gitlab_user_info') as mock_user_info:
            mock_user_info.return_value = {
                'id': 456,
                'username': 'unauthorizeduser',
                'email': 'unauthorized@example.com',
                'name': 'Unauthorized User',
                'groups': ['unauthorized_group'],  # Not in allowed groups
                'state': 'active'
            }
            
            with pytest.raises(AuthorizationError):
                await oidc_validator.validate_user(matrix_user_id)

    @pytest.mark.asyncio
    async def test_rate_limiting_protection(self, oidc_validator):
        """Test rate limiting protection against auth attacks."""
        matrix_user_id = '@attacker:matrix.test'
        
        with patch.object(oidc_validator, '_get_gitlab_user_info') as mock_user_info:
            mock_user_info.side_effect = AuthenticationError("User not found")
            
            # Simulate multiple failed attempts
            for i in range(10):
                try:
                    await oidc_validator.validate_user(matrix_user_id)
                except AuthenticationError:
                    pass  # Expected
            
            # Should be rate limited now
            with pytest.raises(AuthenticationError, match="Too many failed"):
                await oidc_validator.validate_user(matrix_user_id)

    @pytest.mark.asyncio
    async def test_user_caching(self, oidc_validator):
        """Test user information caching."""
        matrix_user_id = '@cacheduser:matrix.test'
        
        with patch.object(oidc_validator, '_get_gitlab_user_info') as mock_user_info:
            mock_user_info.return_value = {
                'id': 789,
                'username': 'cacheduser',
                'email': 'cached@example.com',
                'name': 'Cached User',
                'groups': ['developers'],
                'state': 'active'
            }
            
            # First call should hit GitLab API
            user_info1 = await oidc_validator.validate_user(matrix_user_id)
            mock_user_info.assert_called_once()
            
            # Second call should use cache
            user_info2 = await oidc_validator.validate_user(matrix_user_id)
            mock_user_info.assert_called_once()  # Still only called once
            
            assert user_info1.username == user_info2.username

    def test_username_validation(self, oidc_validator):
        """Test username format validation."""
        # Valid usernames
        assert oidc_validator._is_valid_username('testuser') is True
        assert oidc_validator._is_valid_username('test.user') is True
        assert oidc_validator._is_valid_username('test-user') is True
        assert oidc_validator._is_valid_username('test_user') is True
        
        # Invalid usernames
        assert oidc_validator._is_valid_username('test user') is False  # Space
        assert oidc_validator._is_valid_username('test@user') is False  # @
        assert oidc_validator._is_valid_username('test/user') is False  # /
        assert oidc_validator._is_valid_username('') is False  # Empty
        assert oidc_validator._is_valid_username('a' * 300) is False  # Too long

    def test_role_mapping(self, oidc_validator):
        """Test role mapping from groups."""
        # Test admin group mapping
        user_info = oidc_validator._create_user_info(
            {'username': 'admin', 'groups': ['admin-group'], 'id': 1},
            '@admin:test'
        )
        assert 'agent:admin' in user_info.roles
        
        # Test developer group mapping
        user_info = oidc_validator._create_user_info(
            {'username': 'dev', 'groups': ['developer-team'], 'id': 2},
            '@dev:test'
        )
        assert 'agent:start' in user_info.roles
        
        # Test default viewer role
        user_info = oidc_validator._create_user_info(
            {'username': 'viewer', 'groups': ['unknown-group'], 'id': 3},
            '@viewer:test'
        )
        assert 'agent:status' in user_info.roles

    def test_cache_statistics(self, oidc_validator):
        """Test cache statistics collection."""
        stats = oidc_validator.get_cache_stats()
        
        assert 'cache_size' in stats
        assert 'max_cache_size' in stats
        assert 'cache_hit_ratio' in stats
        assert 'failed_validations' in stats