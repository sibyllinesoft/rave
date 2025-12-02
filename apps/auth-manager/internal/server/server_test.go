package server

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/rave-org/rave/apps/auth-manager/internal/config"
	"github.com/rave-org/rave/apps/auth-manager/internal/shadow"
)

func TestHealthEndpoint(t *testing.T) {
	srv := newTestServer(t)

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp["status"] != "ok" {
		t.Errorf("expected status 'ok', got %v", resp["status"])
	}
}

func TestReadyEndpoint(t *testing.T) {
	srv := newTestServer(t)

	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}
}

func TestWebhookEndpoint_ValidRequest(t *testing.T) {
	srv := newTestServer(t)

	payload := `{
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

	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer test-secret")
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp["status"] != "provisioned" {
		t.Errorf("expected status 'provisioned', got %v", resp["status"])
	}

	// Verify user was stored in shadow store
	users, err := srv.shadowStore.List(context.Background())
	if err != nil {
		t.Fatalf("failed to list shadow users: %v", err)
	}

	if len(users) != 1 {
		t.Errorf("expected 1 shadow user, got %d", len(users))
	}

	if users[0].Identity.Email != "test@example.com" {
		t.Errorf("expected email 'test@example.com', got %s", users[0].Identity.Email)
	}
}

func TestWebhookEndpoint_InvalidAuth(t *testing.T) {
	srv := newTestServer(t)

	payload := `{"severity": "notice"}`
	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer wrong-secret")
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected status 401, got %d", w.Code)
	}
}

func TestWebhookEndpoint_NonUserEvent(t *testing.T) {
	srv := newTestServer(t)

	payload := `{
		"event": {
			"action": "model_created",
			"app": "authentik_core",
			"model_name": "group"
		},
		"severity": "notice"
	}`

	req := httptest.NewRequest(http.MethodPost, "/webhook/authentik", bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer test-secret")
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	if resp["status"] != "ignored" {
		t.Errorf("expected status 'ignored', got %v", resp["status"])
	}
}

func TestManualSyncEndpoint(t *testing.T) {
	srv := newTestServer(t)

	payload := `{
		"email": "manual@example.com",
		"name": "Manual User",
		"username": "manualuser"
	}`

	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync", bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d: %s", w.Code, w.Body.String())
	}

	// Verify user was stored
	users, err := srv.shadowStore.List(context.Background())
	if err != nil {
		t.Fatalf("failed to list shadow users: %v", err)
	}

	if len(users) != 1 {
		t.Errorf("expected 1 shadow user, got %d", len(users))
	}
}

func TestShadowUsersEndpoint(t *testing.T) {
	srv := newTestServer(t)

	// First add a user via manual sync
	payload := `{"email": "list@example.com", "name": "List User"}`
	req := httptest.NewRequest(http.MethodPost, "/api/v1/sync", bytes.NewBufferString(payload))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	srv.httpServer.Handler.ServeHTTP(w, req)

	// Now list users
	req = httptest.NewRequest(http.MethodGet, "/api/v1/shadow-users", nil)
	w = httptest.NewRecorder()
	srv.httpServer.Handler.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to parse response: %v", err)
	}

	users, ok := resp["shadow_users"].([]interface{})
	if !ok {
		t.Fatal("expected shadow_users array in response")
	}

	if len(users) != 1 {
		t.Errorf("expected 1 user, got %d", len(users))
	}
}

func newTestServer(t *testing.T) *Server {
	t.Helper()

	cfg := config.Config{
		ListenAddr:            ":0",
		MattermostURL:         "http://localhost:8065",
		MattermostInternalURL: "http://localhost:8065",
		MattermostAdminToken:  "", // No Mattermost in tests
		WebhookSecret:         "test-secret",
	}

	store := shadow.NewMemoryStore()
	srv := New(cfg, store, nil)

	return srv
}
