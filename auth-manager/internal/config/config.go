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
	ListenAddr           string
	MattermostURL        string
	MattermostAdminToken string
	SourceIDP            string
	SigningKey           string
	PomeriumSharedSecret string
	DatabaseURL          string
}

// FromEnv builds a Config by reading environment variables and falling back to
// sane defaults that work inside the RAVE VM.
func FromEnv() Config {
	cfg := Config{
		ListenAddr:           getEnv("AUTH_MANAGER_LISTEN_ADDR", ":8088"),
		MattermostURL:        getEnv("AUTH_MANAGER_MATTERMOST_URL", "http://127.0.0.1:8065"),
		MattermostAdminToken: getSecretFromEnv("AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN", "AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN_FILE", ""),
		SourceIDP:            getEnv("AUTH_MANAGER_SOURCE_IDP", "gitlab"),
		SigningKey:           getSecretFromEnv("AUTH_MANAGER_SIGNING_KEY", "AUTH_MANAGER_SIGNING_KEY_FILE", ""),
		DatabaseURL:          getEnv("AUTH_MANAGER_DATABASE_URL", ""),
		PomeriumSharedSecret: getSecretFromEnv("AUTH_MANAGER_POMERIUM_SHARED_SECRET", "AUTH_MANAGER_POMERIUM_SHARED_SECRET_FILE", ""),
	}

	if cfg.SigningKey == "" {
		cfg.SigningKey = randomKey()
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
	if c.SigningKey == "" {
		return fmt.Errorf("signing key must not be empty")
	}
	if c.PomeriumSharedSecret == "" {
		return fmt.Errorf("pomerium shared secret must not be empty")
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
		panic(fmt.Errorf("generate signing key: %w", err))
	}
	return base64.RawURLEncoding.EncodeToString(buf)
}
