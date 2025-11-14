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

func TestIssuerIncludesAudience(t *testing.T) {
	issuer, err := NewIssuer("another-secret-value-here")
	if err != nil {
		t.Fatalf("NewIssuer failed: %v", err)
	}
	issuer.SetNowFunc(func() time.Time { return time.Unix(2_000_000_100, 0).UTC() })

	token, err := issuer.Issue("service-subject", []string{"mattermost", "n8n"}, time.Minute, nil)
	if err != nil {
		t.Fatalf("Issue failed: %v", err)
	}
	claims, err := issuer.Validate(token.Value)
	if err != nil {
		t.Fatalf("Validate failed: %v", err)
	}
	aud, ok := claims["aud"].([]interface{})
	if !ok || len(aud) != 2 {
		t.Fatalf("expected audience array, got %#v", claims["aud"])
	}
	if aud[0] != "mattermost" || aud[1] != "n8n" {
		t.Fatalf("unexpected audience claims: %#v", aud)
	}
}
