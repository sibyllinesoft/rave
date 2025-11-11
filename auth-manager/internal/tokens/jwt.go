package tokens

import (
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Issuer issues and validates short-lived JWT tokens for downstream bridges.
type Issuer struct {
	key []byte
	now func() time.Time
}

// Token represents an issued JWT and its expiry timestamp.
type Token struct {
	Value     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

// ErrInvalidToken indicates the JWT could not be verified.
var ErrInvalidToken = errors.New("token invalid")

// NewIssuer builds an Issuer using the provided shared secret (raw or base64 encoded).
func NewIssuer(secret string) (*Issuer, error) {
	if secret == "" {
		return nil, fmt.Errorf("signing secret must not be empty")
	}
	key := decodeSecret(secret)
	if len(key) < 16 {
		return nil, fmt.Errorf("signing secret too short")
	}
	return &Issuer{key: key, now: time.Now}, nil
}

// SetNowFunc overrides the clock used for issuing tokens (useful for tests).
func (i *Issuer) SetNowFunc(fn func() time.Time) {
	if fn == nil {
		i.now = time.Now
		return
	}
	i.now = fn
}

// Issue creates a JWT for the given subject/audience with the specified TTL.
func (i *Issuer) Issue(subject string, audience []string, ttl time.Duration, extraClaims map[string]any) (Token, error) {
	if subject == "" {
		return Token{}, fmt.Errorf("subject is required")
	}
	if ttl <= 0 {
		return Token{}, fmt.Errorf("ttl must be greater than zero")
	}

	now := i.now().UTC()
	exp := now.Add(ttl)

	claims := jwt.MapClaims{
		"sub": subject,
		"iat": now.Unix(),
		"exp": exp.Unix(),
	}
	if len(audience) == 1 {
		claims["aud"] = audience[0]
	} else if len(audience) > 1 {
		claims["aud"] = audience
	}
	for k, v := range extraClaims {
		claims[k] = v
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(i.key)
	if err != nil {
		return Token{}, err
	}
	return Token{Value: signed, ExpiresAt: exp}, nil
}

// Validate verifies the provided JWT and returns its claims.
func (i *Issuer) Validate(tokenStr string) (map[string]any, error) {
	parser := jwt.NewParser(jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	token, err := parser.Parse(tokenStr, func(t *jwt.Token) (any, error) {
		return i.key, nil
	})
	if err != nil {
		return nil, ErrInvalidToken
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	result := make(map[string]any, len(claims))
	for k, v := range claims {
		result[k] = v
	}
	return result, nil
}

func decodeSecret(secret string) []byte {
	if b, err := base64.StdEncoding.DecodeString(secret); err == nil && len(b) > 0 {
		return b
	}
	if b, err := base64.RawStdEncoding.DecodeString(secret); err == nil && len(b) > 0 {
		return b
	}
	if b, err := base64.URLEncoding.DecodeString(secret); err == nil && len(b) > 0 {
		return b
	}
	if b, err := base64.RawURLEncoding.DecodeString(secret); err == nil && len(b) > 0 {
		return b
	}
	return []byte(secret)
}
