package webhook

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

// Event actions from Authentik
const (
	ActionModelCreated = "model_created"
	ActionModelUpdated = "model_updated"
	ActionModelDeleted = "model_deleted"
	ActionLogin        = "login"
	ActionLogout       = "logout"
	ActionUserWrite    = "user_write"
)

// AuthentikEvent represents a webhook payload from Authentik's notification system.
// See: https://docs.goauthentik.io/sys-mgmt/events/transports/
type AuthentikEvent struct {
	// Standard webhook fields
	Body          string `json:"body"`
	Severity      string `json:"severity"`
	UserEmail     string `json:"user_email"`
	UserUsername  string `json:"user_username"`
	EventUserEmail    string `json:"event_user_email"`
	EventUserUsername string `json:"event_user_username"`

	// Event context (when using custom body mapping)
	Event *EventContext `json:"event,omitempty"`
}

// EventContext contains the actual event data when using a custom body mapping.
type EventContext struct {
	Action    string                 `json:"action"`
	App       string                 `json:"app"`
	ModelName string                 `json:"model_name"`
	ObjectPK  string                 `json:"object_pk"`
	Context   map[string]interface{} `json:"context"`
	User      *EventUser             `json:"user"`
	Created   time.Time              `json:"created"`
}

// EventUser represents user info in event context.
type EventUser struct {
	PK       int    `json:"pk"`
	Email    string `json:"email"`
	Username string `json:"username"`
	Name     string `json:"name"`
}

// UserInfo extracts user information from the event, handling both standard
// webhook format and custom body mappings.
type UserInfo struct {
	Email    string
	Username string
	Name     string
	Subject  string // Authentik user PK as string
}

// ExtractUser pulls user info from various places in the event payload.
func (e *AuthentikEvent) ExtractUser() *UserInfo {
	info := &UserInfo{}

	// Try event context first (custom body mapping)
	if e.Event != nil {
		if e.Event.User != nil {
			info.Email = e.Event.User.Email
			info.Username = e.Event.User.Username
			info.Name = e.Event.User.Name
			info.Subject = intToString(e.Event.User.PK)
		}
		// For model events, the user might be in context
		if ctx := e.Event.Context; ctx != nil {
			if email, ok := ctx["email"].(string); ok && info.Email == "" {
				info.Email = email
			}
			if username, ok := ctx["username"].(string); ok && info.Username == "" {
				info.Username = username
			}
			if name, ok := ctx["name"].(string); ok && info.Name == "" {
				info.Name = name
			}
			if pk, ok := ctx["pk"].(float64); ok && info.Subject == "" {
				info.Subject = intToString(int(pk))
			}
		}
	}

	// Fall back to standard webhook fields
	if info.Email == "" {
		info.Email = e.EventUserEmail
	}
	if info.Username == "" {
		info.Username = e.EventUserUsername
	}

	return info
}

// IsUserEvent returns true if this event is about a user model.
func (e *AuthentikEvent) IsUserEvent() bool {
	if e.Event == nil {
		return false
	}
	return strings.EqualFold(e.Event.ModelName, "user") ||
		strings.EqualFold(e.Event.App, "authentik_core") && strings.Contains(strings.ToLower(e.Event.ModelName), "user")
}

// Action returns the event action (model_created, login, etc.)
func (e *AuthentikEvent) Action() string {
	if e.Event != nil {
		return e.Event.Action
	}
	return ""
}

func intToString(i int) string {
	if i == 0 {
		return ""
	}
	return strings.TrimSpace(strings.Replace(string(rune(i)), "\x00", "", -1))
}

// ParseRequest reads and validates a webhook request from Authentik.
// If secret is non-empty, it validates the X-Authentik-Signature header.
func ParseRequest(r *http.Request, secret string) (*AuthentikEvent, error) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20)) // 1MB limit
	if err != nil {
		return nil, err
	}
	defer r.Body.Close()

	// Validate signature if secret is configured
	if secret != "" {
		sig := r.Header.Get("X-Authentik-Signature")
		if sig == "" {
			// Also check Authorization header for Bearer token style
			auth := r.Header.Get("Authorization")
			if strings.HasPrefix(auth, "Bearer ") {
				if strings.TrimPrefix(auth, "Bearer ") != secret {
					return nil, errors.New("invalid bearer token")
				}
			} else {
				return nil, errors.New("missing signature header")
			}
		} else {
			// HMAC-SHA256 signature validation
			if !validateSignature(body, sig, secret) {
				return nil, errors.New("invalid signature")
			}
		}
	}

	var event AuthentikEvent
	if err := json.Unmarshal(body, &event); err != nil {
		return nil, err
	}

	return &event, nil
}

func validateSignature(body []byte, signature, secret string) bool {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(signature), []byte(expected))
}
