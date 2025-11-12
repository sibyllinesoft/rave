package bridge

import (
	"reflect"
	"testing"

	"github.com/rave-org/rave/auth-manager/internal/pomerium"
)

func TestCanonicalIdentityMattermostMapping(t *testing.T) {
	pID := pomerium.Identity{
		Subject: "user-123",
		Email:   "jane@example.com",
		Name:    "Jane Doe",
		User:    "Jane.D",
		Groups:  []string{"devs"},
	}

	canon := FromPomerium(pID)
	if canon.Username != "jane.d" {
		t.Fatalf("unexpected username: %s", canon.Username)
	}

	mm := canon.MattermostIdentity()
	if mm.Email != "jane@example.com" {
		t.Fatalf("unexpected email: %s", mm.Email)
	}
	if mm.Name != "Jane Doe" {
		t.Fatalf("unexpected name: %s", mm.Name)
	}
	if mm.User != "jane.d" {
		t.Fatalf("unexpected user: %s", mm.User)
	}
}

func TestCanonicalIdentityN8NMapping(t *testing.T) {
	pID := pomerium.Identity{
		Subject: "abc-789",
		Email:   "sam@example.org",
		Name:    "Sam Example",
		User:    "Sam.Ex",
		Groups:  []string{"admins"},
	}

	n8n := FromPomerium(pID).N8NUserPayload()

	if n8n.Email != "sam@example.org" {
		t.Fatalf("unexpected email: %s", n8n.Email)
	}
	if n8n.FirstName != "Sam" || n8n.LastName != "Example" {
		t.Fatalf("unexpected names: %+v", n8n)
	}
	if n8n.Role != "admin" {
		t.Fatalf("expected admin role, got %s", n8n.Role)
	}
	if n8n.ExternalID != "abc-789" {
		t.Fatalf("unexpected external id: %s", n8n.ExternalID)
	}
}

func TestCanonicalIdentityHandlesMissingFields(t *testing.T) {
	pID := pomerium.Identity{
		Subject: "123",
		Email:   "",
		Name:    "",
		User:    "",
		Groups:  nil,
	}

	canon := FromPomerium(pID)
	if canon.Username == "" {
		t.Fatalf("expected fallback username")
	}

	mm := canon.MattermostIdentity()
	if mm.Name == "" {
		t.Fatalf("expected fallback name")
	}

	n8n := canon.N8NUserPayload()
	if n8n.DisplayName == "" {
		t.Fatalf("expected fallback display name")
	}
	if !reflect.DeepEqual(canon.Groups, []string{}) {
		t.Fatalf("expected empty groups slice copy")
	}
}
