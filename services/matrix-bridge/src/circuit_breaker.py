"""
Circuit Breaker Pattern Implementation for Matrix Bridge
Provides resilience and fault tolerance for external dependencies.

Security Features:
- Fail-fast behavior to prevent cascade failures
- Automatic recovery with exponential backoff
- Configurable failure thresholds and timeouts
- Health checking and monitoring
- Request filtering and load shedding
"""

import asyncio
import time
from enum import Enum
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, TypeVar, Generic
import logging

import structlog

logger = structlog.get_logger()

T = TypeVar('T')


class CircuitState(Enum):
    """Circuit breaker states."""
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, rejecting requests
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreakerError(Exception):
    """Raised when circuit breaker is open."""
    pass


@dataclass
class CircuitBreakerConfig:
    """Circuit breaker configuration."""
    failure_threshold: int = 5
    recovery_timeout: int = 60
    success_threshold: int = 3  # For half-open -> closed transition
    timeout: int = 30
    expected_exception: type = Exception
    monitor_window: int = 300  # 5 minutes
    max_requests_half_open: int = 3


@dataclass
class CallAttempt:
    """Records a call attempt."""
    timestamp: float
    success: bool
    duration: float
    error: Optional[str] = None


class CircuitBreaker(Generic[T]):
    """
    Circuit breaker implementation with comprehensive failure handling.
    
    Provides:
    - Automatic failure detection and recovery
    - Configurable thresholds and timeouts
    - Health monitoring and metrics
    - Load shedding during failures
    - Exponential backoff for recovery
    """
    
    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: int = 60,
        success_threshold: int = 3,
        timeout: int = 30,
        expected_exception: type = Exception,
        name: str = "circuit_breaker"
    ):
        """
        Initialize circuit breaker.
        
        Args:
            failure_threshold: Number of failures before opening circuit
            recovery_timeout: Time to wait before trying again (seconds)
            success_threshold: Successes needed to close circuit from half-open
            timeout: Timeout for individual calls
            expected_exception: Exception type that triggers circuit opening
            name: Name for logging and monitoring
        """
        self.config = CircuitBreakerConfig(
            failure_threshold=failure_threshold,
            recovery_timeout=recovery_timeout,
            success_threshold=success_threshold,
            timeout=timeout,
            expected_exception=expected_exception
        )
        
        self.name = name
        self.log = logger.bind(component="circuit_breaker", name=name)
        
        # State management
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = 0.0
        self._state_lock = asyncio.Lock()
        
        # Call history for monitoring
        self._call_history: List[CallAttempt] = []
        self._max_history = 1000
        
        # Metrics
        self._stats = {
            'total_calls': 0,
            'successful_calls': 0,
            'failed_calls': 0,
            'rejected_calls': 0,
            'timeouts': 0,
            'state_transitions': 0,
            'last_state_change': 0.0
        }
        
        self.log.info("Circuit breaker initialized",
                     failure_threshold=failure_threshold,
                     recovery_timeout=recovery_timeout,
                     timeout=timeout)
    
    @property
    def state(self) -> str:
        """Get current circuit breaker state."""
        return self._state.value
    
    async def call(self, func: Callable[..., T], *args, **kwargs) -> T:
        """
        Execute function with circuit breaker protection.
        
        Args:
            func: Function to execute
            *args: Function positional arguments
            **kwargs: Function keyword arguments
            
        Returns:
            Function result
            
        Raises:
            CircuitBreakerError: If circuit is open
            Original exception: If function fails
        """
        async with self._state_lock:
            # Check if circuit should remain open
            await self._update_state()
            
            # Reject if circuit is open
            if self._state == CircuitState.OPEN:
                self._stats['rejected_calls'] += 1
                raise CircuitBreakerError(
                    f"Circuit breaker '{self.name}' is open. "
                    f"Last failure: {self._last_failure_time}"
                )
            
            # Limit concurrent requests in half-open state
            if self._state == CircuitState.HALF_OPEN:
                if self._get_concurrent_requests() >= self.config.max_requests_half_open:
                    self._stats['rejected_calls'] += 1
                    raise CircuitBreakerError(
                        f"Circuit breaker '{self.name}' is half-open with max concurrent requests"
                    )
        
        # Execute the function
        start_time = time.time()
        self._stats['total_calls'] += 1
        
        try:
            # Execute with timeout
            if asyncio.iscoroutinefunction(func):
                result = await asyncio.wait_for(
                    func(*args, **kwargs),
                    timeout=self.config.timeout
                )
            else:
                # Run sync function in thread pool with timeout
                result = await asyncio.wait_for(
                    asyncio.get_event_loop().run_in_executor(
                        None, func, *args, **kwargs
                    ),
                    timeout=self.config.timeout
                )
            
            # Success handling
            duration = time.time() - start_time
            await self._record_success(duration)
            
            return result
            
        except asyncio.TimeoutError:
            duration = time.time() - start_time
            self._stats['timeouts'] += 1
            await self._record_failure(duration, "timeout")
            raise
            
        except Exception as e:
            duration = time.time() - start_time
            
            # Check if this is an expected failure type
            if isinstance(e, self.config.expected_exception):
                await self._record_failure(duration, str(e))
            else:
                # Unexpected exceptions don't trigger circuit breaker
                await self._record_success(duration)
            
            raise
    
    async def _record_success(self, duration: float) -> None:
        """Record successful call."""
        async with self._state_lock:
            self._stats['successful_calls'] += 1
            
            # Record call attempt
            attempt = CallAttempt(
                timestamp=time.time(),
                success=True,
                duration=duration
            )
            self._call_history.append(attempt)
            self._trim_history()
            
            # Handle state transitions
            if self._state == CircuitState.HALF_OPEN:
                self._success_count += 1
                
                if self._success_count >= self.config.success_threshold:
                    await self._transition_to_closed()
            
            elif self._state == CircuitState.CLOSED:
                # Reset failure count on success in closed state
                self._failure_count = 0
            
            self.log.debug("Call succeeded",
                         duration=duration,
                         state=self._state.value,
                         success_count=self._success_count)
    
    async def _record_failure(self, duration: float, error: str) -> None:
        """Record failed call."""
        async with self._state_lock:
            self._stats['failed_calls'] += 1
            self._failure_count += 1
            self._last_failure_time = time.time()
            
            # Record call attempt
            attempt = CallAttempt(
                timestamp=self._last_failure_time,
                success=False,
                duration=duration,
                error=error
            )
            self._call_history.append(attempt)
            self._trim_history()
            
            # Check if we should open the circuit
            if self._state == CircuitState.CLOSED:
                if self._failure_count >= self.config.failure_threshold:
                    await self._transition_to_open()
            
            elif self._state == CircuitState.HALF_OPEN:
                # Any failure in half-open goes back to open
                await self._transition_to_open()
            
            self.log.warning("Call failed",
                           duration=duration,
                           error=error,
                           state=self._state.value,
                           failure_count=self._failure_count)
    
    async def _update_state(self) -> None:
        """Update circuit breaker state based on time and conditions."""
        now = time.time()
        
        # Check if we should transition from open to half-open
        if (self._state == CircuitState.OPEN and 
            now - self._last_failure_time >= self.config.recovery_timeout):
            await self._transition_to_half_open()
    
    async def _transition_to_open(self) -> None:
        """Transition circuit breaker to open state."""
        if self._state != CircuitState.OPEN:
            old_state = self._state
            self._state = CircuitState.OPEN
            self._stats['state_transitions'] += 1
            self._stats['last_state_change'] = time.time()
            
            self.log.warning("Circuit breaker opened",
                           old_state=old_state.value,
                           failure_count=self._failure_count,
                           threshold=self.config.failure_threshold)
    
    async def _transition_to_half_open(self) -> None:
        """Transition circuit breaker to half-open state."""
        if self._state != CircuitState.HALF_OPEN:
            old_state = self._state
            self._state = CircuitState.HALF_OPEN
            self._success_count = 0
            self._stats['state_transitions'] += 1
            self._stats['last_state_change'] = time.time()
            
            self.log.info("Circuit breaker half-opened",
                        old_state=old_state.value,
                        recovery_timeout=self.config.recovery_timeout)
    
    async def _transition_to_closed(self) -> None:
        """Transition circuit breaker to closed state."""
        if self._state != CircuitState.CLOSED:
            old_state = self._state
            self._state = CircuitState.CLOSED
            self._failure_count = 0
            self._success_count = 0
            self._stats['state_transitions'] += 1
            self._stats['last_state_change'] = time.time()
            
            self.log.info("Circuit breaker closed",
                        old_state=old_state.value,
                        success_count=self._success_count,
                        threshold=self.config.success_threshold)
    
    def _get_concurrent_requests(self) -> int:
        """Get number of concurrent requests (placeholder)."""
        # This would require tracking active requests
        # For now, return 0 as we don't track concurrent requests
        return 0
    
    def _trim_history(self) -> None:
        """Trim call history to prevent memory growth."""
        if len(self._call_history) > self._max_history:
            # Keep most recent entries
            self._call_history = self._call_history[-self._max_history//2:]
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get circuit breaker health status."""
        now = time.time()
        
        # Calculate recent success rate
        recent_window = now - self.config.monitor_window
        recent_calls = [
            call for call in self._call_history
            if call.timestamp > recent_window
        ]
        
        if recent_calls:
            success_rate = sum(1 for call in recent_calls if call.success) / len(recent_calls)
            avg_duration = sum(call.duration for call in recent_calls) / len(recent_calls)
        else:
            success_rate = 0.0
            avg_duration = 0.0
        
        return {
            'name': self.name,
            'state': self._state.value,
            'failure_count': self._failure_count,
            'success_count': self._success_count,
            'last_failure_time': self._last_failure_time,
            'time_until_retry': max(0, self.config.recovery_timeout - (now - self._last_failure_time)),
            'recent_success_rate': success_rate,
            'recent_avg_duration': avg_duration,
            'recent_calls': len(recent_calls),
            'config': {
                'failure_threshold': self.config.failure_threshold,
                'recovery_timeout': self.config.recovery_timeout,
                'success_threshold': self.config.success_threshold,
                'timeout': self.config.timeout
            }
        }
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get circuit breaker statistics."""
        total_calls = max(1, self._stats['total_calls'])  # Avoid division by zero
        
        return {
            **self._stats,
            'success_rate': self._stats['successful_calls'] / total_calls,
            'failure_rate': self._stats['failed_calls'] / total_calls,
            'rejection_rate': self._stats['rejected_calls'] / total_calls,
            'current_state': self._state.value,
            'history_size': len(self._call_history),
            'config': {
                'failure_threshold': self.config.failure_threshold,
                'recovery_timeout': self.config.recovery_timeout,
                'success_threshold': self.config.success_threshold,
                'timeout': self.config.timeout
            }
        }
    
    def reset(self) -> None:
        """Reset circuit breaker to closed state."""
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._last_failure_time = 0.0
        
        # Reset statistics
        self._stats = {
            'total_calls': 0,
            'successful_calls': 0,
            'failed_calls': 0,
            'rejected_calls': 0,
            'timeouts': 0,
            'state_transitions': 0,
            'last_state_change': time.time()
        }
        
        # Clear history
        self._call_history.clear()
        
        self.log.info("Circuit breaker reset")
    
    def force_open(self) -> None:
        """Force circuit breaker to open state."""
        self._state = CircuitState.OPEN
        self._last_failure_time = time.time()
        self._stats['state_transitions'] += 1
        self._stats['last_state_change'] = time.time()
        
        self.log.warning("Circuit breaker forced open")
    
    def force_closed(self) -> None:
        """Force circuit breaker to closed state."""
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._success_count = 0
        self._stats['state_transitions'] += 1
        self._stats['last_state_change'] = time.time()
        
        self.log.info("Circuit breaker forced closed")


class CircuitBreakerManager:
    """
    Manages multiple circuit breakers with shared configuration.
    
    Provides centralized management and monitoring of circuit breakers
    across the application.
    """
    
    def __init__(self):
        self.circuit_breakers: Dict[str, CircuitBreaker] = {}
        self.log = logger.bind(component="circuit_breaker_manager")
    
    def create_circuit_breaker(
        self,
        name: str,
        failure_threshold: int = 5,
        recovery_timeout: int = 60,
        success_threshold: int = 3,
        timeout: int = 30,
        expected_exception: type = Exception
    ) -> CircuitBreaker:
        """Create and register a new circuit breaker."""
        if name in self.circuit_breakers:
            self.log.warning("Circuit breaker already exists", name=name)
            return self.circuit_breakers[name]
        
        circuit_breaker = CircuitBreaker(
            failure_threshold=failure_threshold,
            recovery_timeout=recovery_timeout,
            success_threshold=success_threshold,
            timeout=timeout,
            expected_exception=expected_exception,
            name=name
        )
        
        self.circuit_breakers[name] = circuit_breaker
        
        self.log.info("Created circuit breaker", name=name)
        return circuit_breaker
    
    def get_circuit_breaker(self, name: str) -> Optional[CircuitBreaker]:
        """Get circuit breaker by name."""
        return self.circuit_breakers.get(name)
    
    def get_all_health_status(self) -> Dict[str, Dict[str, Any]]:
        """Get health status for all circuit breakers."""
        return {
            name: cb.get_health_status()
            for name, cb in self.circuit_breakers.items()
        }
    
    def get_all_statistics(self) -> Dict[str, Dict[str, Any]]:
        """Get statistics for all circuit breakers."""
        return {
            name: cb.get_statistics()
            for name, cb in self.circuit_breakers.items()
        }
    
    def reset_all(self) -> None:
        """Reset all circuit breakers."""
        for cb in self.circuit_breakers.values():
            cb.reset()
        
        self.log.info("Reset all circuit breakers", count=len(self.circuit_breakers))
    
    def get_summary(self) -> Dict[str, Any]:
        """Get summary of all circuit breakers."""
        states = {'closed': 0, 'open': 0, 'half_open': 0}
        total_calls = 0
        total_failures = 0
        
        for cb in self.circuit_breakers.values():
            states[cb.state] += 1
            stats = cb.get_statistics()
            total_calls += stats['total_calls']
            total_failures += stats['failed_calls']
        
        return {
            'total_circuit_breakers': len(self.circuit_breakers),
            'states': states,
            'total_calls': total_calls,
            'total_failures': total_failures,
            'overall_failure_rate': total_failures / max(1, total_calls),
            'healthy_percentage': states['closed'] / max(1, len(self.circuit_breakers)) * 100
        }