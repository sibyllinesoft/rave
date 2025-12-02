package config

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"os"
	"strings"
)

// Config captures the tunable knobs for the auth-manager service.
type Config struct {
	ListenAddr            string
	MattermostURL         string
	MattermostInternalURL string
	MattermostAdminToken  string
	DatabaseURL           string
	WebhookSecret         string // Shared secret for validating Authentik webhooks

	// n8n configuration
	N8NEnabled     bool
	N8NURL         string
	N8NInternalURL string
	N8NOwnerEmail  string
	N8NOwnerPass   string
}

// FromEnv builds a Config by reading environment variables and falling back to
// sane defaults that work inside the RAVE VM.
func FromEnv() Config {
	cfg := Config{
		ListenAddr:            getEnv("AUTH_MANAGER_LISTEN_ADDR", ":8088"),
		MattermostURL:         getEnv("AUTH_MANAGER_MATTERMOST_URL", "https://localhost:8443/mattermost"),
		MattermostInternalURL: getEnv("AUTH_MANAGER_MATTERMOST_INTERNAL_URL", "http://127.0.0.1:8065"),
		MattermostAdminToken:  getSecretFromEnv("AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN", "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN_FILE", ""),
		DatabaseURL:           getEnv("AUTH_MANAGER_DATABASE_URL", ""),
		WebhookSecret:         getSecretFromEnv("AUTH_MANAGER_WEBHOOK_SECRET", "AUTH_MANAGER_WEBHOOK_SECRET_FILE", ""),

		// n8n configuration
		N8NEnabled:     getEnv("AUTH_MANAGER_N8N_ENABLED", "") == "true",
		N8NURL:         getEnv("AUTH_MANAGER_N8N_URL", "https://localhost:8443/n8n"),
		N8NInternalURL: getEnv("AUTH_MANAGER_N8N_INTERNAL_URL", "http://127.0.0.1:5678"),
		N8NOwnerEmail:  getSecretFromEnv("AUTH_MANAGER_N8N_OWNER_EMAIL", "AUTH_MANAGER_N8N_OWNER_EMAIL_FILE", ""),
		N8NOwnerPass:   getSecretFromEnv("AUTH_MANAGER_N8N_OWNER_PASS", "AUTH_MANAGER_N8N_OWNER_PASS_FILE", ""),
	}

	// Generate a random webhook secret if not provided (for dev)
	if cfg.WebhookSecret == "" {
		cfg.WebhookSecret = randomKey()
	}

	return cfg
}

// Validate performs minimal static validation on the configuration.
func (c Config) Validate() error {
	if c.ListenAddr == "" {
		return fmt.Errorf("listen address must not be empty")
	}
	if c.MattermostURL == "" {
		return fmt.Errorf("mattermost URL must not be empty")
	}
	if c.MattermostInternalURL == "" {
		return fmt.Errorf("mattermost internal URL must not be empty")
	}
	return nil
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok && value != "" {
		return value
	}
	return fallback
}

func getSecretFromEnv(valueKey, fileKey, fallback string) string {
	if path := os.Getenv(fileKey); path != "" {
		if data, err := os.ReadFile(path); err == nil {
			if trimmed := strings.TrimSpace(string(data)); trimmed != "" {
				return trimmed
			}
		}
	}
	if value := os.Getenv(valueKey); value != "" {
		return strings.TrimSpace(value)
	}
	return fallback
}

func randomKey() string {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		panic(fmt.Errorf("generate webhook secret: %w", err))
	}
	return base64.RawURLEncoding.EncodeToString(buf)
}
