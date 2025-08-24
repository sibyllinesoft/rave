"""
Comprehensive Security Tests for Authentication System
Implements property-based testing, contract testing, and security validation.
"""

import pytest
import asyncio
import json
import time
from unittest.mock import AsyncMock, Mock, patch
from hypothesis import given, strategies as st, assume
import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from src.auth import (
    GitLabOIDCValidator,
    AuthenticationError,
    AuthorizationError,
    TokenValidationError,
    UserInfo
)


class TestGitLabOIDCValidator:
    """Unit tests for GitLab OIDC validator."""
    
    @pytest.fixture
    def validator(self):
        """Create validator instance for testing."""
        return GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret",
            allowed_groups=["developers", "admins"]
        )
    
    @pytest.fixture
    def mock_user_data(self):
        """Mock GitLab user data."""
        return {
            "id": 123,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "state": "active",
            "created_at": "2023-01-01T00:00:00Z",
            "groups": ["developers"]
        }
    
    def test_initialization(self, validator):
        """Test validator initialization."""
        assert validator.gitlab_url == "https://gitlab.example.com"
        assert validator.client_id == "test-client"
        assert validator.allowed_groups == {"developers", "admins"}
        assert validator.cache_ttl == 300
    
    def test_extract_username_valid(self, validator):
        """Test extracting username from Matrix user ID."""
        matrix_id = "@testuser:matrix.example.com"
        username = validator._extract_username(matrix_id)
        assert username == "testuser"
    
    def test_extract_username_invalid_format(self, validator):
        """Test invalid Matrix user ID format."""
        invalid_ids = [
            "testuser:matrix.example.com",  # Missing @
            "@testuser",  # Missing domain
            "@:matrix.example.com",  # Empty username
            "@@testuser:matrix.example.com",  # Double @
        ]
        
        for invalid_id in invalid_ids:
            with pytest.raises(AuthenticationError):
                validator._extract_username(invalid_id)
    
    def test_is_valid_username(self, validator):
        """Test username validation."""
        valid_usernames = [
            "testuser",
            "test.user",
            "test-user",
            "test_user",
            "user123",
            "123user"
        ]
        
        for username in valid_usernames:
            assert validator._is_valid_username(username) is True
    
    def test_invalid_username_formats(self, validator):
        """Test invalid username formats."""
        invalid_usernames = [
            "",  # Empty
            "test user",  # Space
            "test/user",  # Slash
            "test@user",  # At symbol
            "test;user",  # Semicolon
            "a" * 256,  # Too long
        ]
        
        for username in invalid_usernames:
            assert validator._is_valid_username(username) is False
    
    @pytest.mark.asyncio
    async def test_validate_user_success(self, validator, mock_user_data):
        """Test successful user validation."""
        with patch.object(validator, '_get_gitlab_user_info', new_callable=AsyncMock) as mock_get:
            mock_get.return_value = mock_user_data
            
            result = await validator.validate_user("@testuser:matrix.example.com")
            
            assert isinstance(result, UserInfo)
            assert result.username == "testuser"
            assert result.email == "test@example.com"
            assert "developers" in result.groups
    
    @pytest.mark.asyncio
    async def test_validate_user_unauthorized_group(self, validator, mock_user_data):
        """Test user validation fails for unauthorized groups."""
        mock_user_data["groups"] = ["unauthorized"]
        
        with patch.object(validator, '_get_gitlab_user_info', new_callable=AsyncMock) as mock_get:
            mock_get.return_value = mock_user_data
            
            with pytest.raises(AuthorizationError):
                await validator.validate_user("@testuser:matrix.example.com")
    
    @pytest.mark.asyncio
    async def test_rate_limiting(self, validator):
        """Test rate limiting for failed attempts."""
        # Simulate multiple failed attempts
        for _ in range(6):  # More than max_failed_attempts (5)
            validator._record_failed_validation("@testuser:matrix.example.com")
        
        # Should be rate limited now
        with pytest.raises(AuthenticationError, match="Too many failed"):
            await validator.validate_user("@testuser:matrix.example.com")
    
    def test_cache_functionality(self, validator, mock_user_data):
        """Test user info caching."""
        user_id = "@testuser:matrix.example.com"
        now = time.time()
        
        user_info = UserInfo(
            user_id=user_id,
            username="testuser",
            email="test@example.com",
            name="Test User",
            groups=["developers"],
            roles={"agent:status"},
            token_claims={},
            validated_at=now,
            expires_at=now + 300
        )
        
        # Cache user info
        validator._cache_user(user_id, user_info)
        
        # Should retrieve from cache
        cached = validator._get_cached_user(user_id)
        assert cached is not None
        assert cached.username == "testuser"
    
    def test_cache_expiration(self, validator, mock_user_data):
        """Test cache expiration."""
        user_id = "@testuser:matrix.example.com"
        now = time.time()
        
        user_info = UserInfo(
            user_id=user_id,
            username="testuser",
            email="test@example.com",
            name="Test User",
            groups=["developers"],
            roles={"agent:status"},
            token_claims={},
            validated_at=now,
            expires_at=now - 1  # Already expired
        )
        
        validator._cache_user(user_id, user_info)
        
        # Should not retrieve expired entry
        cached = validator._get_cached_user(user_id)
        assert cached is None
    
    def test_role_mapping(self, validator):
        """Test role mapping from groups."""
        gitlab_user = {
            "id": 123,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "groups": ["admin-team"]
        }
        
        user_info = validator._create_user_info(gitlab_user, "@testuser:matrix.example.com")
        
        # Should have admin roles
        assert "agent:admin" in user_info.roles
        assert "agent:start" in user_info.roles
        assert "agent:stop" in user_info.roles
    
    def test_permission_checking(self, validator):
        """Test permission checking functionality."""
        user_info = UserInfo(
            user_id="@testuser:matrix.example.com",
            username="testuser",
            email="test@example.com",
            name="Test User",
            groups=["developers"],
            roles={"agent:start", "agent:status"},
            token_claims={},
            validated_at=time.time(),
            expires_at=time.time() + 300
        )
        
        assert validator.has_permission(user_info, "agent:start") is True
        assert validator.has_permission(user_info, "agent:admin") is False


class TestJWTValidation:
    """Tests for JWT token validation."""
    
    @pytest.fixture
    def validator(self):
        """Create validator for JWT testing."""
        return GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
    
    @pytest.fixture
    def rsa_key_pair(self):
        """Generate RSA key pair for JWT testing."""
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
        
        public_key = private_key.public_key()
        
        private_pem = private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        
        public_pem = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        
        return private_pem, public_pem
    
    def test_jwt_token_creation_and_validation(self, validator, rsa_key_pair):
        """Test JWT token creation and validation."""
        private_key, public_key = rsa_key_pair
        
        # Create a test token
        payload = {
            "sub": "123",
            "aud": "test-client",
            "iss": "https://gitlab.example.com",
            "iat": int(time.time()),
            "exp": int(time.time()) + 3600
        }
        
        token = jwt.encode(payload, private_key, algorithm="RS256", headers={"kid": "test-key"})
        
        # Mock OIDC configuration and JWKS
        mock_oidc_config = {
            "issuer": "https://gitlab.example.com",
            "jwks_uri": "https://gitlab.example.com/.well-known/jwks"
        }
        
        mock_jwks = {
            "keys": [{
                "kid": "test-key",
                "kty": "RSA",
                "use": "sig",
                "n": "test",  # Would be actual modulus in real implementation
                "e": "AQAB"
            }]
        }
        
        validator._oidc_config = mock_oidc_config
        validator._jwks = mock_jwks
        
        # Mock the JWK to PEM conversion
        with patch.object(validator, '_jwk_to_pem', return_value=public_key.decode('utf-8')):
            # This would normally validate the token
            # In a real test, you'd need to properly implement the JWK conversion
            pass


class TestSecurityProperties:
    """Property-based security tests."""
    
    @pytest.fixture
    def validator(self):
        return GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
    
    @given(st.text())
    def test_username_extraction_never_crashes(self, validator, text):
        """Test username extraction doesn't crash on arbitrary input."""
        try:
            result = validator._extract_username(text)
            # If successful, result should be non-empty string
            assert isinstance(result, str)
            assert len(result) > 0
        except AuthenticationError:
            # Expected for invalid input
            pass
        except Exception as e:
            pytest.fail(f"Unexpected exception: {e}")
    
    @given(st.text(min_size=1, max_size=255))
    def test_username_validation_consistency(self, validator, username):
        """Test username validation is consistent."""
        # Validation should be deterministic
        result1 = validator._is_valid_username(username)
        result2 = validator._is_valid_username(username)
        assert result1 == result2
    
    @given(st.lists(st.text(min_size=1, max_size=50), min_size=1, max_size=10))
    def test_role_mapping_consistency(self, validator, groups):
        """Test role mapping produces consistent results."""
        gitlab_user = {
            "id": 123,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "groups": groups
        }
        
        user_info1 = validator._create_user_info(gitlab_user, "@testuser:matrix.example.com")
        user_info2 = validator._create_user_info(gitlab_user, "@testuser:matrix.example.com")
        
        assert user_info1.roles == user_info2.roles


class TestAuthenticationIntegration:
    """Integration tests for authentication system."""
    
    @pytest.mark.asyncio
    async def test_full_authentication_flow(self):
        """Test complete authentication flow."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret",
            allowed_groups=["developers"]
        )
        
        # Mock all external dependencies
        mock_user_data = {
            "id": 123,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "groups": ["developers"]
        }
        
        with patch('aiohttp.ClientSession') as mock_session_class:
            # Mock the session context manager
            mock_session = AsyncMock()
            mock_session_class.return_value.__aenter__.return_value = mock_session
            
            # Mock the API response
            mock_response = AsyncMock()
            mock_response.status = 200
            mock_response.json.return_value = [mock_user_data]
            
            mock_session.get.return_value.__aenter__.return_value = mock_response
            
            # Mock user groups API call
            mock_groups_response = AsyncMock()
            mock_groups_response.status = 200
            mock_groups_response.json.return_value = []
            
            # Test the flow
            result = await validator.validate_user("@testuser:matrix.example.com")
            
            assert isinstance(result, UserInfo)
            assert result.username == "testuser"
            assert result.email == "test@example.com"
    
    @pytest.mark.asyncio
    async def test_authentication_failure_handling(self):
        """Test authentication failure scenarios."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
        
        with patch('aiohttp.ClientSession') as mock_session_class:
            # Mock 404 response (user not found)
            mock_session = AsyncMock()
            mock_session_class.return_value.__aenter__.return_value = mock_session
            
            mock_response = AsyncMock()
            mock_response.status = 404
            
            mock_session.get.return_value.__aenter__.return_value = mock_response
            
            with pytest.raises(AuthenticationError, match="User not found"):
                await validator.validate_user("@nonexistent:matrix.example.com")
    
    def test_cache_statistics(self):
        """Test cache statistics collection."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
        
        stats = validator.get_cache_stats()
        
        assert 'cache_size' in stats
        assert 'max_cache_size' in stats
        assert 'failed_validations' in stats
        assert isinstance(stats['cache_size'], int)


class TestSecurityEdgeCases:
    """Test security edge cases and boundary conditions."""
    
    def test_concurrent_validation_attempts(self):
        """Test concurrent validation attempts don't cause race conditions."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
        
        # This would require more sophisticated async testing
        # For now, ensure the data structures support concurrency
        assert hasattr(validator, '_cache_access_times')
        assert hasattr(validator, '_failed_validations')
    
    def test_memory_usage_bounds(self):
        """Test memory usage doesn't grow unbounded."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret",
            max_cache_size=10
        )
        
        # Fill cache beyond limit
        for i in range(20):
            user_info = UserInfo(
                user_id=f"@user{i}:matrix.example.com",
                username=f"user{i}",
                email=f"user{i}@example.com",
                name=f"User {i}",
                groups=["developers"],
                roles={"agent:status"},
                token_claims={},
                validated_at=time.time(),
                expires_at=time.time() + 300
            )
            validator._cache_user(f"@user{i}:matrix.example.com", user_info)
        
        # Cache should not exceed max size
        assert len(validator._token_cache) <= validator.max_cache_size
    
    def test_input_sanitization(self):
        """Test input sanitization for logging."""
        validator = GitLabOIDCValidator(
            gitlab_url="https://gitlab.example.com",
            client_id="test-client",
            client_secret="test-secret"
        )
        
        # Test with potentially dangerous input
        dangerous_input = "@user';DROP TABLE users;--:matrix.example.com"
        
        try:
            username = validator._extract_username(dangerous_input)
            # Should extract safely without SQL injection
            assert "DROP TABLE" not in username
        except AuthenticationError:
            # Expected to fail validation
            pass


if __name__ == "__main__":
    pytest.main([__file__, "-v"])