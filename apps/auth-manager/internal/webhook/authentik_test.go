package webhook

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestParseRequest_ValidBearerToken(t *testing.T) {
	body := `{
		"event": {
			"action": "model_created",
			"app": "authentik_core",
			"model_name": "user",
			"context": {
				"pk": 123,
				"email": "test@example.com",
				"username": "testuser",
				"name": "Test User"
			},
			"user": {
				"pk": 123,
				"email": "test@example.com",
				"username": "testuser",
				"name": "Test User"
			}
		},
		"severity": "notice"
	}`

	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer test-secret")

	event, err := ParseRequest(req, "test-secret")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if event.Action() != ActionModelCreated {
		t.Errorf("expected action %q, got %q", ActionModelCreated, event.Action())
	}

	if !event.IsUserEvent() {
		t.Error("expected IsUserEvent() to return true")
	}

	info := event.ExtractUser()
	if info.Email != "test@example.com" {
		t.Errorf("expected email %q, got %q", "test@example.com", info.Email)
	}
	if info.Username != "testuser" {
		t.Errorf("expected username %q, got %q", "testuser", info.Username)
	}
	if info.Name != "Test User" {
		t.Errorf("expected name %q, got %q", "Test User", info.Name)
	}
}

func TestParseRequest_InvalidBearerToken(t *testing.T) {
	body := `{"severity": "notice"}`
	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(body))
	req.Header.Set("Authorization", "Bearer wrong-secret")

	_, err := ParseRequest(req, "correct-secret")
	if err == nil {
		t.Fatal("expected error for invalid bearer token")
	}
}

func TestParseRequest_MissingAuth(t *testing.T) {
	body := `{"severity": "notice"}`
	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(body))

	_, err := ParseRequest(req, "test-secret")
	if err == nil {
		t.Fatal("expected error for missing auth")
	}
}

func TestParseRequest_NoSecretRequired(t *testing.T) {
	body := `{
		"event": {
			"action": "login",
			"app": "authentik_events",
			"model_name": "user"
		},
		"severity": "notice",
		"event_user_email": "user@example.com",
		"event_user_username": "user"
	}`

	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(body))

	event, err := ParseRequest(req, "") // No secret required
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if event.Action() != ActionLogin {
		t.Errorf("expected action %q, got %q", ActionLogin, event.Action())
	}

	info := event.ExtractUser()
	if info.Email != "user@example.com" {
		t.Errorf("expected email from event_user_email, got %q", info.Email)
	}
}

func TestExtractUser_FromContext(t *testing.T) {
	event := &AuthentikEvent{
		Event: &EventContext{
			Action:    ActionModelCreated,
			ModelName: "user",
			Context: map[string]interface{}{
				"pk":       float64(456),
				"email":    "context@example.com",
				"username": "contextuser",
				"name":     "Context User",
			},
		},
	}

	info := event.ExtractUser()
	if info.Email != "context@example.com" {
		t.Errorf("expected email from context, got %q", info.Email)
	}
}

func TestExtractUser_FromEventUser(t *testing.T) {
	event := &AuthentikEvent{
		Event: &EventContext{
			Action:    ActionLogin,
			ModelName: "user",
			User: &EventUser{
				PK:       789,
				Email:    "eventuser@example.com",
				Username: "eventuser",
				Name:     "Event User",
			},
		},
	}

	info := event.ExtractUser()
	if info.Email != "eventuser@example.com" {
		t.Errorf("expected email from event user, got %q", info.Email)
	}
	if info.Name != "Event User" {
		t.Errorf("expected name from event user, got %q", info.Name)
	}
}

func TestIsUserEvent(t *testing.T) {
	tests := []struct {
		name     string
		event    *AuthentikEvent
		expected bool
	}{
		{
			name:     "nil event",
			event:    &AuthentikEvent{},
			expected: false,
		},
		{
			name: "user model",
			event: &AuthentikEvent{
				Event: &EventContext{ModelName: "user"},
			},
			expected: true,
		},
		{
			name: "User model (capitalized)",
			event: &AuthentikEvent{
				Event: &EventContext{ModelName: "User"},
			},
			expected: true,
		},
		{
			name: "authentik_core app with user",
			event: &AuthentikEvent{
				Event: &EventContext{
					App:       "authentik_core",
					ModelName: "user",
				},
			},
			expected: true,
		},
		{
			name: "non-user model",
			event: &AuthentikEvent{
				Event: &EventContext{ModelName: "group"},
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.event.IsUserEvent(); got != tt.expected {
				t.Errorf("IsUserEvent() = %v, want %v", got, tt.expected)
			}
		})
	}
}
