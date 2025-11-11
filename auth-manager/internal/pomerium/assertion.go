package pomerium

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	headerAssertion = "X-Pomerium-Jwt-Assertion"
)

var (
	// ErrMissingAssertion indicates the request did not carry the Pomerium JWT header.
	ErrMissingAssertion = errors.New("pomerium assertion missing")
	// ErrInvalidAssertion indicates the JWT structure or signature was invalid.
	ErrInvalidAssertion = errors.New("pomerium assertion invalid")
)

// Identity captures the user context extracted from the Pomerium assertion.
type Identity struct {
	Subject   string
	Email     string
	Name      string
	User      string
	Groups    []string
	Issuer    string
	IssuedAt  time.Time
	ExpiresAt time.Time
}

// Claims reflects the subset of JWT claims we care about.
type Claims struct {
	Issuer  string   `json:"iss"`
	Subject string   `json:"sub"`
	Email   string   `json:"email"`
	Name    string   `json:"name"`
	User    string   `json:"user"`
	Groups  []string `json:"groups"`
	Issued  int64    `json:"iat"`
	Expires int64    `json:"exp"`
}

// IdentityFromRequest validates the Pomerium assertion on the request and returns the parsed identity.
func IdentityFromRequest(r *http.Request, sharedSecret []byte) (Identity, error) {
	assertion := r.Header.Get(headerAssertion)
	if assertion == "" {
		return Identity{}, ErrMissingAssertion
	}

	claims, err := parseAssertion(assertion, sharedSecret)
	if err != nil {
		return Identity{}, err
	}

	id := Identity{
		Subject:   claims.Subject,
		Email:     claims.Email,
		Name:      claims.Name,
		User:      claims.User,
		Groups:    append([]string(nil), claims.Groups...),
		Issuer:    claims.Issuer,
		IssuedAt:  time.Unix(claims.Issued, 0).UTC(),
		ExpiresAt: time.Unix(claims.Expires, 0).UTC(),
	}

	// Fallback to header claims if JWT lacked them.
	if id.Email == "" {
		id.Email = r.Header.Get("X-Pomerium-Claim-Email")
	}
	if id.Name == "" {
		id.Name = r.Header.Get("X-Pomerium-Claim-Name")
	}
	if id.User == "" {
		id.User = r.Header.Get("X-Pomerium-Claim-User")
	}

	return id, nil
}

func parseAssertion(assertion string, sharedSecret []byte) (Claims, error) {
	parts := strings.Split(assertion, ".")
	if len(parts) != 3 {
		return Claims{}, ErrInvalidAssertion
	}

	headerJSON, err := decodeSegment(parts[0])
	if err != nil {
		return Claims{}, ErrInvalidAssertion
	}
	var header struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return Claims{}, ErrInvalidAssertion
	}
	if header.Alg != "HS256" {
		return Claims{}, fmt.Errorf("unsupported jwt alg %q", header.Alg)
	}

	payload, err := decodeSegment(parts[1])
	if err != nil {
		return Claims{}, ErrInvalidAssertion
	}

	signature, err := decodeSegment(parts[2])
	if err != nil {
		return Claims{}, ErrInvalidAssertion
	}

	mac := hmac.New(sha256.New, sharedSecret)
	mac.Write([]byte(parts[0]))
	mac.Write([]byte{'.'})
	mac.Write([]byte(parts[1]))
	expected := mac.Sum(nil)
	if !hmac.Equal(signature, expected) {
		return Claims{}, ErrInvalidAssertion
	}

	var claims Claims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return Claims{}, ErrInvalidAssertion
	}
	return claims, nil
}

func decodeSegment(seg string) ([]byte, error) {
	if b, err := base64.RawURLEncoding.DecodeString(seg); err == nil {
		return b, nil
	}
	return base64.URLEncoding.DecodeString(seg)
}

// DecodeSharedSecret converts the configured string (which may itself be base64 encoded)
// into raw bytes suitable for JWT verification.
func DecodeSharedSecret(secret string) []byte {
	if secret == "" {
		return nil
	}
	if decoded, err := base64.StdEncoding.DecodeString(secret); err == nil {
		return decoded
	}
	if decoded, err := base64.URLEncoding.DecodeString(secret); err == nil {
		return decoded
	}
	return []byte(secret)
}
