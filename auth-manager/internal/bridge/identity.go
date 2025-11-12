package bridge

import (
	"strings"

	"github.com/rave-org/rave/auth-manager/internal/mattermost"
	"github.com/rave-org/rave/auth-manager/internal/pomerium"
)

// CanonicalIdentity normalises the upstream OAuth/Pomerium payload into the
// subset of attributes downstream bridges care about.
type CanonicalIdentity struct {
	Subject  string
	Email    string
	Name     string
	Username string
	Groups   []string
}

// FromPomerium converts a pomerium.Identity into the canonical format used by
// bridge-specific mappers.
func FromPomerium(id pomerium.Identity) CanonicalIdentity {
	username := id.User
	if username == "" && id.Email != "" {
		username = strings.Split(id.Email, "@")[0]
	}
	if username == "" {
		username = "shadow-" + id.Subject
	}
	username = sanitizeHandle(username)

	groups := make([]string, len(id.Groups))
	copy(groups, id.Groups)
	return CanonicalIdentity{
		Subject:  id.Subject,
		Email:    strings.TrimSpace(id.Email),
		Name:     strings.TrimSpace(id.Name),
		Username: username,
		Groups:   groups,
	}
}

// MattermostIdentity maps the canonical identity to the Mattermost client schema.
func (ci CanonicalIdentity) MattermostIdentity() mattermost.Identity {
	name := ci.Name
	if name == "" {
		name = strings.Title(ci.Username)
	}
	return mattermost.Identity{
		Email: ci.Email,
		Name:  name,
		User:  ci.Username,
	}
}

// N8NUser models the portion of the n8n user schema we expect to drive.
type N8NUser struct {
	Email       string
	FirstName   string
	LastName    string
	DisplayName string
	ExternalID  string
	Role        string
}

// N8NUserPayload derives a default n8n user profile for the canonical identity.
func (ci CanonicalIdentity) N8NUserPayload() N8NUser {
	first, last := splitName(ci.Name)
	if first == "" {
		first = strings.Title(ci.Username)
	}
	display := strings.TrimSpace(ci.Name)
	if display == "" {
		display = first
	}
	role := "member"
	if len(ci.Groups) > 0 && strings.Contains(strings.ToLower(ci.Groups[0]), "admin") {
		role = "admin"
	}

	return N8NUser{
		Email:       ci.Email,
		FirstName:   first,
		LastName:    last,
		DisplayName: display,
		ExternalID:  ci.Subject,
		Role:        role,
	}
}

func sanitizeHandle(input string) string {
	lower := strings.ToLower(input)
	builder := strings.Builder{}
	for _, r := range lower {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_' {
			builder.WriteRune(r)
		} else {
			builder.WriteRune('-')
		}
	}
	handle := strings.Trim(builder.String(), "-._")
	if handle == "" {
		handle = "user"
	}
	if len(handle) > 22 {
		handle = handle[:22]
	}
	return handle
}

func splitName(full string) (string, string) {
	trimmed := strings.TrimSpace(full)
	if trimmed == "" {
		return "", ""
	}
	parts := strings.Fields(trimmed)
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.Join(parts[1:], " ")
}
