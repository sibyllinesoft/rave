"""
Adaptive Rate Limiter for Chat Control
Implements sophisticated rate limiting with adaptive thresholds.

Security Features:
- Per-client rate limiting with sliding windows
- Adaptive rate limiting based on system load
- Burst capacity management
- Distributed rate limiting support
- Memory-efficient token bucket algorithm
- Real-time metrics and monitoring
"""

import asyncio
import time
import hashlib
import os
from dataclasses import dataclass
from typing import Dict, Any, List, Optional, Set
from collections import defaultdict, deque
import math

import structlog

logger = structlog.get_logger()


@dataclass
class RateLimitConfig:
    """Rate limiting configuration."""
    requests_per_minute: int
    burst_size: int
    window_size: int = 60  # seconds
    cleanup_interval: int = 300  # 5 minutes
    adaptive_enabled: bool = True
    max_burst_multiplier: float = 2.0
    min_rate_multiplier: float = 0.1


@dataclass
class ClientMetrics:
    """Per-client rate limiting metrics."""
    requests_made: int = 0
    requests_blocked: int = 0
    last_request_time: float = 0.0
    burst_tokens: float = 0.0
    window_start: float = 0.0
    request_times: deque = None
    
    def __post_init__(self):
        if self.request_times is None:
            self.request_times = deque(maxlen=100)  # Keep last 100 request times


class AdaptiveRateLimiter:
    """
    Adaptive rate limiter with sophisticated controls and system load awareness.
    
    Features:
    - Token bucket algorithm with burst capacity
    - Sliding window rate limiting
    - Adaptive rate adjustment based on system load
    - Per-client tracking and metrics
    - Memory-efficient cleanup
    - Real-time monitoring and alerting
    """
    
    def __init__(
        self,
        requests_per_minute: int = 60,
        burst_size: int = 10,
        window_size: int = 60,
        adaptive_enabled: bool = True,
        redis_client = None
    ):
        """
        Initialize adaptive rate limiter.
        
        Args:
            requests_per_minute: Base rate limit per client
            burst_size: Maximum burst requests allowed
            window_size: Time window for rate calculation (seconds)
            adaptive_enabled: Enable adaptive rate adjustment
            redis_client: Optional Redis client for distributed limiting
        """
        self.config = RateLimitConfig(
            requests_per_minute=requests_per_minute,
            burst_size=burst_size,
            window_size=window_size,
            adaptive_enabled=adaptive_enabled
        )
        
        self.redis_client = redis_client
        self.log = logger.bind(component="rate_limiter")
        
        # Client tracking
        self._client_metrics: Dict[str, ClientMetrics] = {}
        self._client_lock = asyncio.Lock()
        
        # System metrics for adaptive limiting
        self._system_load_history: deque = deque(maxlen=60)  # 1 minute of history
        self._current_load_factor = 1.0
        self._last_load_check = 0.0
        
        # Cleanup task
        self._cleanup_task: Optional[asyncio.Task] = None
        self._is_running = False
        
        # Global statistics
        self._stats = {
            'total_requests': 0,
            'total_blocked': 0,
            'total_allowed': 0,
            'active_clients': 0,
            'avg_system_load': 0.0
        }
        
        self.log.info("Rate limiter initialized",
                     rpm=requests_per_minute,
                     burst=burst_size,
                     adaptive=adaptive_enabled)
    
    async def start(self) -> None:
        """Start the rate limiter background tasks."""
        self._is_running = True
        self._cleanup_task = asyncio.create_task(self._cleanup_worker())
        
        self.log.info("Rate limiter started")
    
    async def stop(self) -> None:
        """Stop the rate limiter and cleanup resources."""
        self._is_running = False
        
        if self._cleanup_task:
            self._cleanup_task.cancel()
            try:
                await self._cleanup_task
            except asyncio.CancelledError:
                pass
        
        self.log.info("Rate limiter stopped")
    
    async def is_allowed(
        self, 
        client_id: str, 
        cost: int = 1,
        context: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Check if request is allowed for client.
        
        Args:
            client_id: Unique client identifier
            cost: Cost of the request (default 1)
            context: Additional context for adaptive limiting
            
        Returns:
            bool: True if request is allowed
        """
        now = time.time()
        
        try:
            # Update system load for adaptive limiting
            await self._update_system_load()
            
            # Use distributed limiting if Redis is available
            if self.redis_client:
                return await self._is_allowed_distributed(client_id, cost, now)
            else:
                return await self._is_allowed_local(client_id, cost, now, context)
                
        except Exception as e:
            self.log.error("Error checking rate limit", 
                         client_id=client_id, 
                         error=str(e))
            # Fail open for availability (could be fail closed for security)
            return True
    
    async def _is_allowed_local(
        self, 
        client_id: str, 
        cost: int, 
        now: float,
        context: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Check rate limit using local state."""
        async with self._client_lock:
            # Get or create client metrics
            if client_id not in self._client_metrics:
                self._client_metrics[client_id] = ClientMetrics(
                    window_start=now,
                    burst_tokens=self.config.burst_size
                )
            
            metrics = self._client_metrics[client_id]
            
            # Calculate current rate limits (with adaptive adjustment)
            current_limits = self._calculate_adaptive_limits(context)
            
            # Update burst tokens (token bucket refill)
            self._refill_burst_tokens(metrics, now, current_limits)
            
            # Check burst capacity
            if metrics.burst_tokens < cost:
                # Not enough burst tokens
                metrics.requests_blocked += 1
                self._stats['total_blocked'] += 1
                
                self.log.debug("Request blocked - burst limit",
                             client_id=client_id,
                             burst_tokens=metrics.burst_tokens,
                             cost=cost)
                return False
            
            # Check sliding window rate
            if not self._check_sliding_window(metrics, now, current_limits, cost):
                metrics.requests_blocked += 1
                self._stats['total_blocked'] += 1
                
                self.log.debug("Request blocked - rate limit",
                             client_id=client_id,
                             window_requests=len(metrics.request_times))
                return False
            
            # Allow request - consume tokens and update metrics
            metrics.burst_tokens -= cost
            metrics.requests_made += 1
            metrics.last_request_time = now
            metrics.request_times.append(now)
            
            self._stats['total_requests'] += 1
            self._stats['total_allowed'] += 1
            
            return True
    
    async def _is_allowed_distributed(
        self, 
        client_id: str, 
        cost: int, 
        now: float
    ) -> bool:
        """Check rate limit using Redis for distributed limiting."""
        try:
            # Redis Lua script for atomic rate limiting
            lua_script = """
            local client_key = KEYS[1]
            local window_key = KEYS[2]
            local now = tonumber(ARGV[1])
            local cost = tonumber(ARGV[2])
            local window_size = tonumber(ARGV[3])
            local rate_limit = tonumber(ARGV[4])
            local burst_limit = tonumber(ARGV[5])
            
            -- Get current burst tokens
            local burst_tokens = redis.call('GET', client_key)
            if not burst_tokens then
                burst_tokens = burst_limit
            else
                burst_tokens = tonumber(burst_tokens)
            end
            
            -- Refill burst tokens based on time passed
            local last_refill = redis.call('GET', client_key .. ':last_refill')
            if last_refill then
                local time_passed = now - tonumber(last_refill)
                local refill_amount = (time_passed * rate_limit) / 60
                burst_tokens = math.min(burst_limit, burst_tokens + refill_amount)
            end
            
            -- Check if enough tokens
            if burst_tokens < cost then
                return 0  -- Not allowed
            end
            
            -- Check sliding window
            local window_start = now - window_size
            redis.call('ZREMRANGEBYSCORE', window_key, 0, window_start)
            local current_requests = redis.call('ZCARD', window_key)
            
            if current_requests >= rate_limit then
                return 0  -- Rate limit exceeded
            end
            
            -- Allow request
            burst_tokens = burst_tokens - cost
            redis.call('SET', client_key, burst_tokens, 'EX', window_size * 2)
            redis.call('SET', client_key .. ':last_refill', now, 'EX', window_size * 2)
            redis.call('ZADD', window_key, now, now .. ':' .. math.random())
            redis.call('EXPIRE', window_key, window_size)
            
            return 1  -- Allowed
            """
            
            # Execute script
            keys = [
                f"rate_limit:{client_id}:burst",
                f"rate_limit:{client_id}:window"
            ]
            
            current_limits = self._calculate_adaptive_limits()
            
            args = [
                now,
                cost,
                self.config.window_size,
                current_limits['requests_per_minute'],
                current_limits['burst_size']
            ]
            
            # SECURITY NOTE: redis.eval() executes Lua scripts on Redis server, not Python eval()
            # This is secure as we control the Lua script content and Redis sandboxes it
            result = await self.redis_client.eval(lua_script, keys, args)
            
            allowed = result == 1
            
            # Update local statistics
            self._stats['total_requests'] += 1
            if allowed:
                self._stats['total_allowed'] += 1
            else:
                self._stats['total_blocked'] += 1
            
            return allowed
            
        except Exception as e:
            self.log.error("Redis rate limiting failed", 
                         client_id=client_id, 
                         error=str(e))
            # Fallback to local limiting
            return await self._is_allowed_local(client_id, cost, now)
    
    def _calculate_adaptive_limits(
        self, 
        context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Calculate current rate limits with adaptive adjustment."""
        base_rpm = self.config.requests_per_minute
        base_burst = self.config.burst_size
        
        if not self.config.adaptive_enabled:
            return {
                'requests_per_minute': base_rpm,
                'burst_size': base_burst
            }
        
        # Adjust based on system load
        load_factor = self._current_load_factor
        
        # Apply context-specific adjustments
        context_factor = 1.0
        if context:
            # Adjust for request type, user type, etc.
            if context.get('user_type') == 'admin':
                context_factor = 2.0  # Higher limits for admins
            elif context.get('request_type') == 'status':
                context_factor = 1.5  # Higher limits for status requests
        
        # Calculate adjusted limits
        total_factor = load_factor * context_factor
        
        adjusted_rpm = max(
            base_rpm * self.config.min_rate_multiplier,
            min(
                base_rpm * self.config.max_burst_multiplier,
                int(base_rpm * total_factor)
            )
        )
        
        adjusted_burst = max(
            1,
            min(
                int(base_burst * self.config.max_burst_multiplier),
                int(base_burst * total_factor)
            )
        )
        
        return {
            'requests_per_minute': adjusted_rpm,
            'burst_size': adjusted_burst,
            'load_factor': load_factor,
            'context_factor': context_factor
        }
    
    def _refill_burst_tokens(
        self, 
        metrics: ClientMetrics, 
        now: float, 
        limits: Dict[str, Any]
    ) -> None:
        """Refill burst tokens based on time elapsed."""
        if metrics.last_request_time == 0:
            metrics.last_request_time = now
            return
        
        time_passed = now - metrics.last_request_time
        refill_rate = limits['requests_per_minute'] / 60.0  # tokens per second
        
        tokens_to_add = time_passed * refill_rate
        metrics.burst_tokens = min(
            limits['burst_size'],
            metrics.burst_tokens + tokens_to_add
        )
    
    def _check_sliding_window(
        self, 
        metrics: ClientMetrics, 
        now: float, 
        limits: Dict[str, Any],
        cost: int
    ) -> bool:
        """Check sliding window rate limit."""
        # Clean old requests outside window
        window_start = now - self.config.window_size
        while metrics.request_times and metrics.request_times[0] < window_start:
            metrics.request_times.popleft()
        
        # Check if adding this request would exceed limit
        current_requests = len(metrics.request_times)
        return current_requests + cost <= limits['requests_per_minute']
    
    async def _update_system_load(self) -> None:
        """Update system load factor for adaptive limiting."""
        now = time.time()
        
        # Update load every 5 seconds
        if now - self._last_load_check < 5:
            return
        
        try:
            # Get system load average
            load_avg = os.getloadavg()[0] if hasattr(os, 'getloadavg') else 1.0
            
            # Get CPU count for normalization
            cpu_count = os.cpu_count() or 1
            normalized_load = load_avg / cpu_count
            
            # Store in history
            self._system_load_history.append(normalized_load)
            
            # Calculate load factor (inverse relationship)
            # High load = lower rate limits
            avg_load = sum(self._system_load_history) / len(self._system_load_history)
            
            if avg_load < 0.5:
                self._current_load_factor = 1.2  # Increase limits
            elif avg_load < 0.8:
                self._current_load_factor = 1.0  # Normal limits
            elif avg_load < 1.2:
                self._current_load_factor = 0.8  # Reduce limits
            else:
                self._current_load_factor = 0.5  # Severely reduce limits
            
            self._last_load_check = now
            self._stats['avg_system_load'] = avg_load
            
        except Exception as e:
            self.log.warning("Failed to update system load", error=str(e))
            self._current_load_factor = 1.0
    
    async def _cleanup_worker(self) -> None:
        """Background worker to clean up old client data."""
        while self._is_running:
            try:
                await asyncio.sleep(self.config.cleanup_interval)
                await self._cleanup_old_clients()
                
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.log.error("Error in cleanup worker", error=str(e))
    
    async def _cleanup_old_clients(self) -> None:
        """Remove old inactive clients to free memory."""
        now = time.time()
        cutoff = now - self.config.cleanup_interval * 2  # 2x cleanup interval
        
        async with self._client_lock:
            clients_to_remove = []
            
            for client_id, metrics in self._client_metrics.items():
                if metrics.last_request_time < cutoff:
                    clients_to_remove.append(client_id)
            
            for client_id in clients_to_remove:
                del self._client_metrics[client_id]
            
            # Update statistics
            self._stats['active_clients'] = len(self._client_metrics)
            
            if clients_to_remove:
                self.log.debug("Cleaned up old clients", 
                             count=len(clients_to_remove))
    
    async def get_client_info(self, client_id: str) -> Optional[Dict[str, Any]]:
        """Get rate limiting info for a specific client."""
        async with self._client_lock:
            if client_id not in self._client_metrics:
                return None
            
            metrics = self._client_metrics[client_id]
            now = time.time()
            
            # Calculate current limits
            current_limits = self._calculate_adaptive_limits()
            
            # Update burst tokens for display
            self._refill_burst_tokens(metrics, now, current_limits)
            
            return {
                'client_id': client_id,
                'requests_made': metrics.requests_made,
                'requests_blocked': metrics.requests_blocked,
                'burst_tokens_available': metrics.burst_tokens,
                'window_requests': len(metrics.request_times),
                'last_request': metrics.last_request_time,
                'current_limits': current_limits,
                'blocked_ratio': (
                    metrics.requests_blocked / max(1, metrics.requests_made + metrics.requests_blocked)
                )
            }
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get rate limiter statistics."""
        return {
            **self._stats,
            'config': {
                'base_rpm': self.config.requests_per_minute,
                'base_burst': self.config.burst_size,
                'window_size': self.config.window_size,
                'adaptive_enabled': self.config.adaptive_enabled
            },
            'adaptive_state': {
                'current_load_factor': self._current_load_factor,
                'system_load_samples': len(self._system_load_history)
            },
            'memory_usage': {
                'tracked_clients': len(self._client_metrics),
                'total_request_history': sum(
                    len(metrics.request_times) 
                    for metrics in self._client_metrics.values()
                )
            }
        }
    
    async def reset_client(self, client_id: str) -> bool:
        """Reset rate limiting state for a client."""
        async with self._client_lock:
            if client_id in self._client_metrics:
                del self._client_metrics[client_id]
                self.log.info("Reset rate limit state", client_id=client_id)
                return True
            return False
    
    async def set_client_limits(
        self, 
        client_id: str, 
        rpm: Optional[int] = None,
        burst: Optional[int] = None
    ) -> None:
        """Set custom limits for a specific client (if supported)."""
        # This would require extending the ClientMetrics structure
        # to support per-client custom limits
        self.log.info("Custom client limits not implemented yet",
                     client_id=client_id,
                     rpm=rpm,
                     burst=burst)


# Alias for security validation compatibility
AsyncLimiter = AdaptiveRateLimiter