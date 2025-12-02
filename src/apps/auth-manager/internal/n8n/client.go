package n8n

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	// ErrNotFound is returned when n8n returns a 404.
	ErrNotFound = errors.New("n8n resource not found")
	// ErrUnauthorized is returned when authentication fails.
	ErrUnauthorized = errors.New("n8n authentication failed")
)

// Identity captures the fields needed to create/update an n8n user.
type Identity struct {
	Email    string
	Name     string
	Username string
}

// User represents an n8n user.
type User struct {
	ID        string `json:"id"`
	Email     string `json:"email"`
	FirstName string `json:"firstName"`
	LastName  string `json:"lastName"`
	Role      string `json:"role"`
	Disabled  bool   `json:"disabled"`
}

// Session represents an n8n session with the auth cookie.
type Session struct {
	UserID string
	Cookie string
}

// Client is a minimal n8n REST API client.
type Client struct {
	baseURL    string
	httpClient *http.Client
	ownerEmail string
	ownerPass  string
}

// NewClient creates a client against the given n8n base URL.
// ownerEmail and ownerPass are credentials for the n8n owner account used to manage users.
func NewClient(baseURL, ownerEmail, ownerPass string) *Client {
	trimmed := strings.TrimRight(baseURL, "/")
	return &Client{
		baseURL:    trimmed,
		ownerEmail: ownerEmail,
		ownerPass:  ownerPass,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

// EnsureUser guarantees an n8n user exists for the provided identity.
// n8n doesn't have a public user creation API for non-owner scenarios,
// so this primarily verifies the user can be looked up or creates them via invite.
func (c *Client) EnsureUser(ctx context.Context, ident Identity) (User, error) {
	if ident.Email == "" {
		return User{}, errors.New("identity email required")
	}

	// First authenticate as owner to get a session
	ownerCookie, err := c.login(ctx, c.ownerEmail, c.ownerPass)
	if err != nil {
		return User{}, fmt.Errorf("owner login failed: %w", err)
	}

	// Try to find user by email
	user, err := c.getUserByEmail(ctx, ownerCookie, ident.Email)
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return User{}, err
	}

	// User doesn't exist - invite them
	return c.inviteUser(ctx, ownerCookie, ident)
}

// CreateSession creates an n8n session for the user.
// Since n8n uses cookie-based auth, this returns the session cookie.
// The user must already exist with a password set.
func (c *Client) CreateSession(ctx context.Context, email, password string) (Session, error) {
	cookie, err := c.login(ctx, email, password)
	if err != nil {
		return Session{}, err
	}
	return Session{
		Cookie: cookie,
	}, nil
}

// login authenticates with n8n and returns the session cookie.
func (c *Client) login(ctx context.Context, email, password string) (string, error) {
	payload := map[string]string{
		"email":    email,
		"password": password,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/rest/login", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return "", ErrUnauthorized
	}
	if resp.StatusCode >= 400 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("n8n login failed: %s", strings.TrimSpace(string(errBody)))
	}

	// Extract the session cookie
	for _, cookie := range resp.Cookies() {
		if cookie.Name == "n8n-auth" {
			return cookie.Value, nil
		}
	}

	return "", errors.New("no n8n-auth cookie in response")
}

// getUserByEmail looks up a user by email.
func (c *Client) getUserByEmail(ctx context.Context, authCookie, email string) (User, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/rest/users", nil)
	if err != nil {
		return User{}, err
	}
	req.Header.Set("Cookie", "n8n-auth="+authCookie)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return User{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return User{}, fmt.Errorf("n8n get users failed: %s", strings.TrimSpace(string(errBody)))
	}

	var result struct {
		Data []User `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return User{}, err
	}

	for _, user := range result.Data {
		if strings.EqualFold(user.Email, email) {
			return user, nil
		}
	}

	return User{}, ErrNotFound
}

// inviteUser sends an invite to create a new n8n user.
func (c *Client) inviteUser(ctx context.Context, authCookie string, ident Identity) (User, error) {
	first, last := splitName(ident.Name)
	payload := []map[string]string{
		{
			"email":     ident.Email,
			"firstName": first,
			"lastName":  last,
			"role":      "global:member",
		},
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return User{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/rest/invitations", bytes.NewReader(body))
	if err != nil {
		return User{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Cookie", "n8n-auth="+authCookie)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return User{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		errBody, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return User{}, fmt.Errorf("n8n invite failed: %s", strings.TrimSpace(string(errBody)))
	}

	var result struct {
		Data []struct {
			User User `json:"user"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return User{}, err
	}

	if len(result.Data) == 0 {
		return User{}, errors.New("no user returned from invite")
	}

	return result.Data[0].User, nil
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
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "ChangeMe123!"
	}
	for i := range buf {
		buf[i] = letters[int(buf[i])%len(letters)]
	}
	return string(buf)
}
