package pomerium

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

func TestParseAssertion(t *testing.T) {
	secret := []byte("test-secret")
	claims := Claims{
		Issuer:  "pomerium",
		Subject: "user-123",
		Email:   "jane@example.com",
		Name:    "Jane Example",
		User:    "jane",
		Groups:  []string{"rave"},
		Issued:  time.Now().Unix(),
		Expires: time.Now().Add(5 * time.Minute).Unix(),
	}

	token := mustBuildToken(claims, secret)
	req, _ := http.NewRequest(http.MethodGet, "https://example.com", nil)
	req.Header.Set(headerAssertion, token)

	identity, err := IdentityFromRequest(req, secret)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if identity.Email != claims.Email || identity.Subject != claims.Subject {
		t.Fatalf("unexpected identity %+v", identity)
	}
}

func mustBuildToken(claims Claims, secret []byte) string {
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)

	hB64 := base64.RawURLEncoding.EncodeToString(headerJSON)
	cB64 := base64.RawURLEncoding.EncodeToString(claimsJSON)

	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(hB64))
	mac.Write([]byte{'.'})
	mac.Write([]byte(cB64))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))

	return hB64 + "." + cB64 + "." + sig
}
