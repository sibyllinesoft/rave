package tokens

import (
	"testing"
	"time"
)

func TestIssuerIssueAndValidate(t *testing.T) {
	issuer, err := NewIssuer("c2VjcmV0LXZhbHVlLWZvci10ZXN0aW5n")
	if err != nil {
		t.Fatalf("NewIssuer failed: %v", err)
	}
	now := time.Unix(2_000_000_000, 0).UTC()
	issuer.SetNowFunc(func() time.Time { return now })

	token, err := issuer.Issue("user-123", []string{"mattermost"}, 5*time.Minute, map[string]any{"roles": []string{"dev"}})
	if err != nil {
		t.Fatalf("Issue failed: %v", err)
	}
	if token.Value == "" {
		t.Fatalf("expected token value")
	}
	if token.ExpiresAt.Before(now) {
		t.Fatalf("unexpected expiry: %v", token.ExpiresAt)
	}

	claims, err := issuer.Validate(token.Value)
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}
	if claims["sub"] != "user-123" {
		t.Fatalf("unexpected subject: %v", claims["sub"])
	}
}

func TestIssuerValidateRejectsInvalid(t *testing.T) {
	issuer, err := NewIssuer("short-but-usable-secret")
	if err != nil {
		t.Fatalf("NewIssuer failed: %v", err)
	}
	if _, err := issuer.Validate("not-a-jwt"); err == nil {
		t.Fatalf("expected error for invalid token")
	}
}
