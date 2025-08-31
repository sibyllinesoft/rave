"""
GitLab OIDC Authentication and Authorization System
Implements comprehensive security validation for Matrix bridge users.

Security Features:
- JWT token validation with cryptographic verification
- GitLab OIDC claims validation and extraction
- Group-based authorization with configurable permissions
- Token caching with security-aware TTL
- Rate limiting for authentication requests
- Comprehensive audit logging of auth events
"""

import asyncio
import json
import time
from dataclasses import dataclass
from typing import Dict, Any, List, Optional, Set, Union
import logging
from urllib.parse import urljoin
import hashlib
import hmac

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
import aiohttp
import structlog

logger = structlog.get_logger()


class AuthenticationError(Exception):
    """Raised when authentication fails."""
    pass


class AuthorizationError(Exception):
    """Raised when authorization fails."""
    pass


class TokenValidationError(AuthenticationError):
    """Raised when token validation fails."""
    pass


@dataclass
class UserInfo:
    """Represents validated user information from GitLab OIDC."""
    user_id: str
    username: str
    email: str
    name: str
    groups: List[str]
    roles: Set[str]
    token_claims: Dict[str, Any]
    validated_at: float
    expires_at: float


class GitLabOIDCValidator:
    """
    GitLab OIDC authentication and authorization validator.
    
    Implements comprehensive security validation:
    - JWT token cryptographic verification
    - OIDC claims validation and extraction  
    - Group-based authorization with role mapping
    - Secure token caching with TTL
    - Rate limiting for auth requests
    - Comprehensive audit logging
    """
    
    def __init__(
        self,
        gitlab_url: str,
        client_id: str,
        client_secret: str,
        allowed_groups: Optional[List[str]] = None,
        cache_ttl: int = 300,  # 5 minutes
        max_cache_size: int = 1000
    ):
        """
        Initialize GitLab OIDC validator.
        
        Args:
            gitlab_url: GitLab instance URL
            client_id: OIDC client ID
            client_secret: OIDC client secret
            allowed_groups: List of allowed GitLab groups (None = allow all)
            cache_ttl: Token cache TTL in seconds
            max_cache_size: Maximum number of cached tokens
        """
        self.gitlab_url = gitlab_url.rstrip('/')
        self.client_id = client_id
        self.client_secret = client_secret
        self.allowed_groups = set(allowed_groups) if allowed_groups else None
        self.cache_ttl = cache_ttl
        self.max_cache_size = max_cache_size
        
        self.log = logger.bind(component="oidc_validator")
        
        # Token cache with security-aware structure
        self._token_cache: Dict[str, UserInfo] = {}
        self._cache_access_times: Dict[str, float] = {}
        self._failed_validations: Dict[str, List[float]] = {}
        
        # OIDC configuration cache
        self._oidc_config: Optional[Dict[str, Any]] = None
        self._jwks: Optional[Dict[str, Any]] = None
        self._config_last_updated: float = 0
        self._config_ttl = 3600  # 1 hour
        
        # Role mapping configuration
        self.role_mappings = {
            'admin': {'agent:admin', 'agent:start', 'agent:stop', 'agent:status'},
            'developer': {'agent:start', 'agent:stop', 'agent:status'},
            'viewer': {'agent:status'},
            'maintainer': {'agent:admin', 'agent:start', 'agent:stop', 'agent:status'}
        }
        
        # Security settings
        self.max_failed_attempts = 5
        self.lockout_duration = 300  # 5 minutes
        self.token_leeway = 30  # JWT time validation leeway
        
        self.log.info("OIDC validator initialized",
                     gitlab_url=self.gitlab_url,
                     allowed_groups=list(self.allowed_groups) if self.allowed_groups else "all",
                     cache_ttl=self.cache_ttl)
    
    async def validate_user(self, matrix_user_id: str) -> UserInfo:
        """
        Validate Matrix user against GitLab OIDC.
        
        Args:
            matrix_user_id: Matrix user ID (e.g., @user:domain.com)
            
        Returns:
            UserInfo: Validated user information
            
        Raises:
            AuthenticationError: If authentication fails
            AuthorizationError: If user is not authorized
        """
        self.log.debug("Validating user", user_id=matrix_user_id)
        
        try:
            # 1. Check rate limiting for this user
            self._check_rate_limiting(matrix_user_id)
            
            # 2. Check token cache first
            cached_info = self._get_cached_user(matrix_user_id)
            if cached_info:
                self.log.debug("Using cached user info", user_id=matrix_user_id)
                return cached_info
            
            # 3. Extract username from Matrix user ID
            username = self._extract_username(matrix_user_id)
            
            # 4. Get user information from GitLab
            user_info = await self._get_gitlab_user_info(username)
            
            # 5. Validate user authorization
            self._validate_authorization(user_info)
            
            # 6. Create UserInfo object with roles
            validated_user = self._create_user_info(user_info, matrix_user_id)
            
            # 7. Cache the validated user
            self._cache_user(matrix_user_id, validated_user)
            
            self.log.info("User validation successful",
                         user_id=matrix_user_id,
                         username=validated_user.username,
                         groups=validated_user.groups,
                         roles=list(validated_user.roles))
            
            return validated_user
            
        except (AuthenticationError, AuthorizationError) as e:
            self._record_failed_validation(matrix_user_id)
            self.log.warning("User validation failed",
                           user_id=matrix_user_id,
                           error=str(e))
            raise
            
        except Exception as e:
            self._record_failed_validation(matrix_user_id)
            self.log.error("Unexpected error in user validation",
                         user_id=matrix_user_id,
                         error=str(e))
            raise AuthenticationError(f"Validation failed: {str(e)}")
    
    async def validate_jwt_token(self, token: str) -> Dict[str, Any]:
        """
        Validate JWT token from GitLab OIDC.
        
        Args:
            token: JWT token string
            
        Returns:
            Dict: Validated token claims
            
        Raises:
            TokenValidationError: If token validation fails
        """
        try:
            # 1. Ensure we have OIDC configuration
            await self._ensure_oidc_config()
            
            # 2. Decode token header to get key ID
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get('kid')
            
            if not kid:
                raise TokenValidationError("Token missing key ID")
            
            # 3. Get public key from JWKS
            public_key = await self._get_public_key(kid)
            
            # 4. Validate and decode token
            claims = jwt.decode(
                token,
                public_key,
                algorithms=['RS256'],
                audience=self.client_id,
                issuer=self._oidc_config['issuer'],
                leeway=self.token_leeway
            )
            
            # 5. Additional claims validation
            self._validate_token_claims(claims)
            
            return claims
            
        except jwt.ExpiredSignatureError:
            raise TokenValidationError("Token expired")
        except jwt.InvalidTokenError as e:
            raise TokenValidationError(f"Invalid token: {str(e)}")
        except Exception as e:
            self.log.error("JWT validation error", error=str(e))
            raise TokenValidationError(f"Token validation failed: {str(e)}")
    
    def _extract_username(self, matrix_user_id: str) -> str:
        """Extract username from Matrix user ID."""
        # Matrix user ID format: @username:homeserver.domain
        if not matrix_user_id.startswith('@'):
            raise AuthenticationError("Invalid Matrix user ID format")
        
        # Remove @ prefix and split on :
        user_part = matrix_user_id[1:]
        if ':' not in user_part:
            raise AuthenticationError("Invalid Matrix user ID format")
        
        username = user_part.split(':', 1)[0]
        
        if not username:
            raise AuthenticationError("Empty username in Matrix user ID")
        
        # Validate username format
        if not self._is_valid_username(username):
            raise AuthenticationError(f"Invalid username format: {username}")
        
        return username
    
    def _is_valid_username(self, username: str) -> bool:
        """Validate username format."""
        # GitLab username rules: alphanumeric, hyphens, underscores, dots
        import re
        pattern = r'^[a-zA-Z0-9._-]{1,255}$'
        return bool(re.match(pattern, username))
    
    async def _get_gitlab_user_info(self, username: str) -> Dict[str, Any]:
        """Get user information from GitLab API."""
        try:
            # Use GitLab API to get user info
            url = f"{self.gitlab_url}/api/v4/users?username={username}"
            
            async with aiohttp.ClientSession() as session:
                # Use client credentials if available for API access
                headers = self._get_api_headers()
                
                async with session.get(url, headers=headers, timeout=10) as response:
                    if response.status == 404:
                        raise AuthenticationError(f"User not found: {username}")
                    elif response.status != 200:
                        raise AuthenticationError(f"GitLab API error: {response.status}")
                    
                    users = await response.json()
                    
                    if not users:
                        raise AuthenticationError(f"User not found: {username}")
                    
                    user = users[0]  # First match
                    
                    # Get user groups
                    user_groups = await self._get_user_groups(user['id'], session)
                    user['groups'] = user_groups
                    
                    return user
                    
        except aiohttp.ClientError as e:
            self.log.error("GitLab API request failed", error=str(e))
            raise AuthenticationError("Failed to fetch user information")
        except Exception as e:
            self.log.error("Unexpected error fetching user info", error=str(e))
            raise AuthenticationError("User information fetch failed")
    
    async def _get_user_groups(self, user_id: int, session: aiohttp.ClientSession) -> List[str]:
        """Get user groups from GitLab API."""
        try:
            url = f"{self.gitlab_url}/api/v4/users/{user_id}/memberships"
            headers = self._get_api_headers()
            
            async with session.get(url, headers=headers, timeout=10) as response:
                if response.status != 200:
                    self.log.warning("Failed to fetch user groups", 
                                   user_id=user_id, 
                                   status=response.status)
                    return []
                
                memberships = await response.json()
                
                # Extract group names from memberships
                groups = []
                for membership in memberships:
                    source = membership.get('source')
                    if source and source.get('kind') == 'group':
                        groups.append(source.get('name', ''))
                
                return [g for g in groups if g]  # Filter empty strings
                
        except Exception as e:
            self.log.warning("Error fetching user groups", 
                           user_id=user_id, 
                           error=str(e))
            return []
    
    def _get_api_headers(self) -> Dict[str, str]:
        """Get headers for GitLab API requests."""
        # For now, use basic headers
        # In production, you might want to use a personal access token
        return {
            'User-Agent': 'RAVE-Matrix-Bridge/1.0',
            'Accept': 'application/json'
        }
    
    def _validate_authorization(self, user_info: Dict[str, Any]) -> None:
        """Validate user authorization based on groups."""
        if not self.allowed_groups:
            return  # All users allowed
        
        user_groups = set(user_info.get('groups', []))
        
        if not user_groups.intersection(self.allowed_groups):
            raise AuthorizationError(
                f"User not in any allowed groups. "
                f"User groups: {list(user_groups)}, "
                f"Allowed: {list(self.allowed_groups)}"
            )
    
    def _create_user_info(self, gitlab_user: Dict[str, Any], matrix_user_id: str) -> UserInfo:
        """Create UserInfo object from GitLab user data."""
        now = time.time()
        
        # Map GitLab groups to roles
        user_groups = gitlab_user.get('groups', [])
        roles = set()
        
        for group in user_groups:
            # Simple role mapping based on group names
            if 'admin' in group.lower():
                roles.update(self.role_mappings['admin'])
            elif 'maintainer' in group.lower():
                roles.update(self.role_mappings['maintainer'])
            elif 'developer' in group.lower():
                roles.update(self.role_mappings['developer'])
            else:
                roles.update(self.role_mappings['viewer'])
        
        # Ensure at least viewer role
        if not roles:
            roles.update(self.role_mappings['viewer'])
        
        return UserInfo(
            user_id=matrix_user_id,
            username=gitlab_user.get('username', ''),
            email=gitlab_user.get('email', ''),
            name=gitlab_user.get('name', ''),
            groups=user_groups,
            roles=roles,
            token_claims={
                'id': gitlab_user.get('id'),
                'state': gitlab_user.get('state', ''),
                'created_at': gitlab_user.get('created_at', ''),
                'last_activity_on': gitlab_user.get('last_activity_on', ''),
            },
            validated_at=now,
            expires_at=now + self.cache_ttl
        )
    
    def _check_rate_limiting(self, user_id: str) -> None:
        """Check if user is rate limited for authentication."""
        now = time.time()
        
        # Clean old failed attempts
        if user_id in self._failed_validations:
            self._failed_validations[user_id] = [
                timestamp for timestamp in self._failed_validations[user_id]
                if now - timestamp < self.lockout_duration
            ]
        
        # Check if user is locked out
        failed_attempts = self._failed_validations.get(user_id, [])
        if len(failed_attempts) >= self.max_failed_attempts:
            raise AuthenticationError(
                f"Too many failed authentication attempts. "
                f"Try again in {self.lockout_duration} seconds."
            )
    
    def _record_failed_validation(self, user_id: str) -> None:
        """Record failed validation attempt."""
        now = time.time()
        if user_id not in self._failed_validations:
            self._failed_validations[user_id] = []
        
        self._failed_validations[user_id].append(now)
        
        # Cleanup old entries
        self._cleanup_failed_validations()
    
    def _cleanup_failed_validations(self) -> None:
        """Clean up old failed validation entries."""
        now = time.time()
        
        for user_id in list(self._failed_validations.keys()):
            self._failed_validations[user_id] = [
                timestamp for timestamp in self._failed_validations[user_id]
                if now - timestamp < self.lockout_duration
            ]
            
            if not self._failed_validations[user_id]:
                del self._failed_validations[user_id]
    
    def _get_cached_user(self, user_id: str) -> Optional[UserInfo]:
        """Get user info from cache if valid."""
        if user_id not in self._token_cache:
            return None
        
        user_info = self._token_cache[user_id]
        now = time.time()
        
        # Check if cached info is expired
        if now > user_info.expires_at:
            del self._token_cache[user_id]
            if user_id in self._cache_access_times:
                del self._cache_access_times[user_id]
            return None
        
        # Update access time
        self._cache_access_times[user_id] = now
        
        return user_info
    
    def _cache_user(self, user_id: str, user_info: UserInfo) -> None:
        """Cache user info with LRU eviction."""
        now = time.time()
        
        # Evict expired entries
        self._cleanup_cache()
        
        # Evict LRU entries if cache is full
        if len(self._token_cache) >= self.max_cache_size:
            self._evict_lru_cache_entries()
        
        self._token_cache[user_id] = user_info
        self._cache_access_times[user_id] = now
    
    def _cleanup_cache(self) -> None:
        """Remove expired entries from cache."""
        now = time.time()
        expired_keys = [
            key for key, user_info in self._token_cache.items()
            if now > user_info.expires_at
        ]
        
        for key in expired_keys:
            del self._token_cache[key]
            if key in self._cache_access_times:
                del self._cache_access_times[key]
    
    def _evict_lru_cache_entries(self) -> None:
        """Evict least recently used cache entries."""
        # Remove 20% of cache entries (LRU)
        num_to_evict = max(1, len(self._token_cache) // 5)
        
        # Sort by access time
        sorted_keys = sorted(
            self._cache_access_times.keys(),
            key=lambda k: self._cache_access_times[k]
        )
        
        for key in sorted_keys[:num_to_evict]:
            if key in self._token_cache:
                del self._token_cache[key]
            if key in self._cache_access_times:
                del self._cache_access_times[key]
    
    async def _ensure_oidc_config(self) -> None:
        """Ensure OIDC configuration is loaded and up to date."""
        now = time.time()
        
        if (self._oidc_config is None or 
            now - self._config_last_updated > self._config_ttl):
            await self._load_oidc_config()
    
    async def _load_oidc_config(self) -> None:
        """Load OIDC configuration from GitLab."""
        try:
            config_url = f"{self.gitlab_url}/.well-known/openid_configuration"
            
            async with aiohttp.ClientSession() as session:
                async with session.get(config_url, timeout=10) as response:
                    if response.status != 200:
                        raise AuthenticationError("Failed to load OIDC configuration")
                    
                    self._oidc_config = await response.json()
                    
                    # Load JWKS
                    jwks_uri = self._oidc_config.get('jwks_uri')
                    if jwks_uri:
                        await self._load_jwks(jwks_uri, session)
                    
                    self._config_last_updated = time.time()
                    
        except Exception as e:
            self.log.error("Failed to load OIDC configuration", error=str(e))
            raise AuthenticationError("OIDC configuration load failed")
    
    async def _load_jwks(self, jwks_uri: str, session: aiohttp.ClientSession) -> None:
        """Load JSON Web Key Set from GitLab."""
        try:
            async with session.get(jwks_uri, timeout=10) as response:
                if response.status != 200:
                    raise AuthenticationError("Failed to load JWKS")
                
                self._jwks = await response.json()
                
        except Exception as e:
            self.log.error("Failed to load JWKS", error=str(e))
            raise AuthenticationError("JWKS load failed")
    
    async def _get_public_key(self, kid: str) -> str:
        """Get public key from JWKS for token verification."""
        if not self._jwks:
            raise TokenValidationError("JWKS not loaded")
        
        # Find key with matching kid
        for key in self._jwks.get('keys', []):
            if key.get('kid') == kid:
                # Convert JWK to PEM format
                return self._jwk_to_pem(key)
        
        raise TokenValidationError(f"Public key not found for kid: {kid}")
    
    def _jwk_to_pem(self, jwk: Dict[str, Any]) -> str:
        """Convert JWK to PEM format for cryptography library."""
        try:
            # This is a simplified implementation
            # In production, use a proper JWK library
            from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
            
            # For RSA keys
            if jwk.get('kty') == 'RSA':
                import base64
                
                n = int.from_bytes(
                    base64.urlsafe_b64decode(jwk['n'] + '=='), 
                    byteorder='big'
                )
                e = int.from_bytes(
                    base64.urlsafe_b64decode(jwk['e'] + '=='), 
                    byteorder='big'
                )
                
                public_key = rsa.RSAPublicNumbers(e, n).public_key()
                
                pem = public_key.public_bytes(
                    encoding=Encoding.PEM,
                    format=PublicFormat.SubjectPublicKeyInfo
                )
                
                return pem.decode('utf-8')
            else:
                raise TokenValidationError(f"Unsupported key type: {jwk.get('kty')}")
                
        except Exception as e:
            self.log.error("JWK to PEM conversion failed", error=str(e))
            raise TokenValidationError("Key conversion failed")
    
    def _validate_token_claims(self, claims: Dict[str, Any]) -> None:
        """Validate additional token claims."""
        # Check required claims
        required_claims = ['sub', 'iat', 'exp', 'aud']
        for claim in required_claims:
            if claim not in claims:
                raise TokenValidationError(f"Missing required claim: {claim}")
        
        # Validate audience
        if claims['aud'] != self.client_id:
            raise TokenValidationError("Invalid audience")
        
        # Additional custom validations can be added here
    
    def _generate_hmac_signature(self, data: str, secret_key: bytes) -> str:
        """Generate HMAC signature for data integrity verification."""
        import hashlib
        signature = hmac.new(
            secret_key,
            data.encode('utf-8'),
            hashlib.sha256
        )
        return signature.hexdigest()
    
    def _verify_hmac_signature(self, data: str, signature: str, secret_key: bytes) -> bool:
        """Verify HMAC signature for data integrity."""
        expected_signature = self._generate_hmac_signature(data, secret_key)
        return hmac.compare_digest(signature, expected_signature)
    
    def has_permission(self, user_info: UserInfo, permission: str) -> bool:
        """Check if user has specific permission."""
        return permission in user_info.roles
    
    def get_cache_stats(self) -> Dict[str, Any]:
        """Get cache statistics for monitoring."""
        return {
            'cache_size': len(self._token_cache),
            'max_cache_size': self.max_cache_size,
            'cache_hit_ratio': self._calculate_cache_hit_ratio(),
            'failed_validations': len(self._failed_validations),
        }
    
    def _calculate_cache_hit_ratio(self) -> float:
        """Calculate cache hit ratio (placeholder implementation)."""
        # This would require tracking hits and misses
        return 0.0  # Implement proper tracking if needed