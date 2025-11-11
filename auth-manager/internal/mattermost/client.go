package mattermost

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var (
	// ErrNotFound is returned when Mattermost signals a 404 for the requested resource.
	ErrNotFound = errors.New("mattermost resource not found")
)

// Identity captures the fields we need to create/update a Mattermost user.
type Identity struct {
	Email string
	Name  string
	User  string
}

// User represents the subset of Mattermost user fields we care about.
type User struct {
	ID        string `json:"id"`
	Username  string `json:"username"`
	Email     string `json:"email"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
	CreateAt  int64  `json:"create_at"`
	UpdateAt  int64  `json:"update_at"`
}

// Session mirrors the JSON payload returned by POST /users/{id}/sessions.
type Session struct {
	ID        string `json:"id"`
	Token     string `json:"token"`
	UserID    string `json:"user_id"`
	CreateAt  int64  `json:"create_at"`
	ExpiresAt int64  `json:"expires_at"`
	DeviceID  string `json:"device_id"`
}

// Client is a minimal Mattermost REST API client focused on user/session flows.
type Client struct {
	baseURL    string
	token      string
	httpClient *http.Client
}

// NewClient creates a client against the given Mattermost base URL (host:port, no trailing slash).
func NewClient(baseURL, token string) *Client {
	trimmed := strings.TrimRight(baseURL, "/")
	return &Client{
		baseURL: trimmed,
		token:   token,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

// EnsureUser guarantees a local Mattermost user exists for the provided identity.
func (c *Client) EnsureUser(ctx context.Context, ident Identity) (User, error) {
	if ident.Email == "" {
		return User{}, errors.New("identity email required")
	}

	user, err := c.getUserByEmail(ctx, ident.Email)
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return User{}, err
	}

	return c.createUser(ctx, ident)
}

// CreateSession creates a Mattermost session for the given user ID.
func (c *Client) CreateSession(ctx context.Context, userID string) (Session, error) {
	path := fmt.Sprintf("/api/v4/users/%s/sessions", url.PathEscape(userID))
	payload := map[string]any{
		"device_id":  "",
		"expires_at": 0,
	}
	var session Session
	if err := c.do(ctx, http.MethodPost, path, payload, &session); err != nil {
		return Session{}, err
	}
	return session, nil
}

func (c *Client) getUserByEmail(ctx context.Context, email string) (User, error) {
	path := fmt.Sprintf("/api/v4/users/email/%s", url.PathEscape(email))
	var user User
	if err := c.do(ctx, http.MethodGet, path, nil, &user); err != nil {
		return User{}, err
	}
	return user, nil
}

func (c *Client) createUser(ctx context.Context, ident Identity) (User, error) {
	username := deriveUsername(ident)
	first, last := splitName(ident.Name)
	payload := map[string]any{
		"email":           ident.Email,
		"username":        username,
		"first_name":      first,
		"last_name":       last,
		"password":        randomPassword(),
		"allow_marketing": false,
		"locale":          "en",
		"email_verified":  true,
	}
	var user User
	if err := c.do(ctx, http.MethodPost, "/api/v4/users", payload, &user); err != nil {
		return User{}, err
	}
	return user, nil
}

func (c *Client) do(ctx context.Context, method, path string, body any, dest any) error {
	fullURL := c.baseURL + path
	var reader io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(buf)
	}

	req, err := http.NewRequestWithContext(ctx, method, fullURL, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return ErrNotFound
	}
	if resp.StatusCode >= 400 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("mattermost %s %s failed: %s", method, path, strings.TrimSpace(string(errBody)))
	}

	if dest != nil {
		if err := json.NewDecoder(resp.Body).Decode(dest); err != nil {
			return err
		}
	}
	return nil
}

func deriveUsername(ident Identity) string {
	candidate := ident.User
	if candidate == "" && ident.Email != "" {
		candidate = strings.Split(ident.Email, "@")[0]
	}
	if candidate == "" {
		candidate = fmt.Sprintf("shadow-%d", time.Now().Unix())
	}
	cleaned := strings.ToLower(candidate)
	cleaned = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '.' || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, cleaned)
	cleaned = strings.Trim(cleaned, "-._")
	if cleaned == "" {
		cleaned = fmt.Sprintf("shadow-%d", time.Now().Unix())
	}
	if len(cleaned) > 22 {
		cleaned = cleaned[:22]
	}
	return cleaned
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

func randomPassword() string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "ChangeMe123!"
	}
	for i := range buf {
		buf[i] = letters[int(buf[i])%len(letters)]
	}
	return string(buf)
}
