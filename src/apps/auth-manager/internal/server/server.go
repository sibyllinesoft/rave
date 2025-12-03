package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/rave-org/rave/apps/auth-manager/internal/config"
	"github.com/rave-org/rave/apps/auth-manager/internal/mattermost"
	"github.com/rave-org/rave/apps/auth-manager/internal/n8n"
	"github.com/rave-org/rave/apps/auth-manager/internal/shadow"
	"github.com/rave-org/rave/apps/auth-manager/internal/webhook"
)

// Server owns the HTTP surface area for the auth-manager control plane.
type Server struct {
	cfg              config.Config
	shadowStore      shadow.Store
	httpServer       *http.Server
	mmClient         *mattermost.Client
	n8nClient        *n8n.Client
	metricsRegistry  *prometheus.Registry
	usersProvisioned prometheus.Counter
	webhooksReceived prometheus.Counter
	logger           *slog.Logger
	mmBreaker        *circuitBreaker
	n8nBreaker       *circuitBreaker
}

// New wires up the HTTP server, routes, and store.
func New(cfg config.Config, store shadow.Store, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}

	srv := &Server{
		cfg:        cfg,
		logger:     logger,
		mmBreaker:  newCircuitBreaker(5, 30*time.Second),
		n8nBreaker: newCircuitBreaker(5, 30*time.Second),
	}
	if store == nil {
		store = srv.newStoreFromConfig()
	}
	srv.shadowStore = store

	if cfg.MattermostAdminToken != "" {
		srv.mmClient = mattermost.NewClient(cfg.MattermostInternalURL, cfg.MattermostAdminToken)
	}

	if cfg.N8NEnabled && cfg.N8NOwnerEmail != "" && cfg.N8NOwnerPass != "" {
		srv.n8nClient = n8n.NewClient(cfg.N8NInternalURL, cfg.N8NOwnerEmail, cfg.N8NOwnerPass)
	}

	reg := prometheus.NewRegistry()
	srv.metricsRegistry = reg
	srv.usersProvisioned = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "auth_manager_users_provisioned_total",
		Help: "Number of users provisioned to downstream services",
	})
	srv.webhooksReceived = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "auth_manager_webhooks_received_total",
		Help: "Number of webhook events received from Authentik",
	})
	reg.MustRegister(srv.usersProvisioned, srv.webhooksReceived)

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", srv.handleHealth)
	mux.HandleFunc("/readyz", srv.handleReady)
	mux.HandleFunc("/api/v1/shadow-users", srv.handleShadowUsers)
	mux.HandleFunc("/webhook/authentik", srv.handleAuthentikWebhook)
	mux.HandleFunc("/api/v1/sync", srv.handleManualSync)
	mux.HandleFunc("/auth/mattermost", srv.handleMattermostForwardAuth)
	mux.HandleFunc("/auth/n8n", srv.handleN8NForwardAuth)
	mux.Handle("/metrics", promhttp.HandlerFor(srv.metricsRegistry, promhttp.HandlerOpts{}))

	srv.httpServer = &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      srv.logRequest(mux),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	return srv
}

// Start begins serving HTTP requests.
func (s *Server) Start() error {
	s.logger.Info("auth-manager listening", "addr", s.cfg.ListenAddr, "mattermost", s.cfg.MattermostURL)
	if err := s.cfg.Validate(); err != nil {
		return err
	}
	err := s.httpServer.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

// Shutdown gracefully stops the HTTP listener.
func (s *Server) Shutdown(ctx context.Context) error {
	if err := s.httpServer.Shutdown(ctx); err != nil {
		return err
	}
	if s.shadowStore != nil {
		return s.shadowStore.Close(ctx)
	}
	return nil
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	s.respondJSON(w, http.StatusOK, map[string]any{
		"status":       "ok",
		"mattermost":   s.cfg.MattermostURL,
		"current_time": time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if s.shadowStore != nil {
		if err := s.shadowStore.HealthCheck(ctx); err != nil {
			s.respondError(w, http.StatusServiceUnavailable, err)
			return
		}
	}
	s.respondJSON(w, http.StatusOK, map[string]any{"status": "ready"})
}

func (s *Server) handleShadowUsers(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		users, err := s.shadowStore.List(r.Context())
		if err != nil {
			s.respondError(w, http.StatusInternalServerError, err)
			return
		}
		s.respondJSON(w, http.StatusOK, map[string]any{"shadow_users": users})
	default:
		w.Header().Set("Allow", "GET")
		s.respondJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

// handleAuthentikWebhook receives webhook notifications from Authentik.
// Authentik sends these when users are created, updated, or deleted.
func (s *Server) handleAuthentikWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		s.respondJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	event, err := webhook.ParseRequest(r, s.cfg.WebhookSecret)
	if err != nil {
		s.logger.Warn("webhook parse failed", "err", err)
		s.respondError(w, http.StatusUnauthorized, err)
		return
	}

	s.webhooksReceived.Inc()
	s.logger.Info("webhook received",
		"action", event.Action(),
		"is_user_event", event.IsUserEvent(),
		"severity", event.Severity,
	)

	// Only process user-related events
	if !event.IsUserEvent() {
		s.respondJSON(w, http.StatusOK, map[string]string{"status": "ignored", "reason": "not a user event"})
		return
	}

	userInfo := event.ExtractUser()
	if userInfo.Email == "" {
		s.respondJSON(w, http.StatusOK, map[string]string{"status": "ignored", "reason": "no email in event"})
		return
	}

	// Process based on action
	switch event.Action() {
	case webhook.ActionModelCreated, webhook.ActionModelUpdated, webhook.ActionUserWrite, webhook.ActionLogin:
		if err := s.provisionUser(r.Context(), userInfo); err != nil {
			s.logger.Error("provision failed", "email", userInfo.Email, "err", err)
			s.respondError(w, http.StatusInternalServerError, err)
			return
		}
		s.respondJSON(w, http.StatusOK, map[string]any{
			"status": "provisioned",
			"email":  userInfo.Email,
		})
	case webhook.ActionModelDeleted:
		// For now, just log deletion - don't deprovision
		s.logger.Info("user deleted in authentik", "email", userInfo.Email)
		s.respondJSON(w, http.StatusOK, map[string]any{
			"status": "noted",
			"action": "deleted",
			"email":  userInfo.Email,
		})
	default:
		s.respondJSON(w, http.StatusOK, map[string]string{"status": "ignored", "reason": "unhandled action"})
	}
}

// handleMattermostForwardAuth is called by Traefik's ForwardAuth middleware.
// It reads Authentik identity headers (set by Authentik's proxy outpost forward-auth),
// ensures the user exists in Mattermost, creates a session, and returns Set-Cookie headers.
//
// Flow:
// 1. User visits /mattermost
// 2. Traefik calls Authentik's outpost forward-auth endpoint (e.g., /outpost.goauthentik.io/auth/traefik)
// 3. If not authenticated, Authentik redirects to login
// 4. After login, Authentik sets X-Authentik-* headers
// 5. Traefik then calls this endpoint with those headers
// 6. We create Mattermost session and return cookies via addAuthCookiesToResponse
func (s *Server) handleMattermostForwardAuth(w http.ResponseWriter, r *http.Request) {
	// Extract user identity from Authentik headers (set by Authentik proxy outpost)
	email := headerFirst(r,
		"X-Authentik-Email",
		"X-Auth-Request-Email",
		"X-Forwarded-Email",
	)
	username := headerFirst(r,
		"X-Authentik-Username",
		"X-Auth-Request-User",
		"X-Forwarded-User",
		"Remote-User",
	)
	name := headerFirst(r,
		"X-Authentik-Name",
		"X-Auth-Request-Name",
		"X-Auth-Request-User",
		"X-Forwarded-User",
	)
	isXHR := strings.EqualFold(r.Header.Get("X-Requested-With"), "XMLHttpRequest") ||
		strings.Contains(strings.ToLower(r.Header.Get("Accept")), "json")

	// Log all X-Authentik headers for debugging
	for key, values := range r.Header {
		lowerKey := strings.ToLower(key)
		if strings.HasPrefix(lowerKey, "x-authentik") || strings.HasPrefix(lowerKey, "x-auth-request") {
			s.logger.Debug("authentik header", "key", key, "values", values)
		}
	}

	// If no Authentik headers, check if user already has Mattermost cookies
	if email == "" {
		// Check for existing Mattermost session
		if _, err := r.Cookie("MMAUTHTOKEN"); err == nil {
			// User already has a Mattermost session, allow through
			w.WriteHeader(http.StatusOK)
			return
		}
		// No Authentik identity and no Mattermost session - deny
		s.logger.Debug("no authentik identity headers found", "path", r.URL.Path)
		http.Error(w, "Unauthorized - no Authentik session", http.StatusUnauthorized)
		return
	}

	s.logger.Info("forward auth request",
		"email", email,
		"username", username,
		"name", name,
		"path", r.Header.Get("X-Forwarded-Uri"),
	)

	if s.mmClient == nil {
		w.Header().Set("X-Rave-Auth-Error", "mattermost-client-misconfigured")
		s.logger.Error("mattermost client not configured")
		http.Error(w, "Mattermost not configured", http.StatusServiceUnavailable)
		return
	}

	// Check circuit breaker
	if s.mmBreaker != nil && !s.mmBreaker.allow() {
		w.Header().Set("X-Rave-Auth-Error", "mattermost-circuit-open")
		if retry := int(s.mmBreaker.remaining().Seconds()); retry > 0 {
			w.Header().Set("Retry-After", strconv.Itoa(retry))
		}
		s.logger.Warn("mattermost circuit open", "email", email)
		http.Error(w, "Mattermost temporarily unavailable", http.StatusServiceUnavailable)
		return
	}

	ctx := r.Context()

	// Ensure user exists in Mattermost
	mmUser, err := s.mmClient.EnsureUser(ctx, mattermost.Identity{
		Email: email,
		Name:  name,
		User:  username,
	})
	if err != nil {
		s.recordMattermostFailure(err)
		s.logger.Error("failed to ensure mattermost user", "email", email, "err", err)
		w.Header().Set("X-Rave-Auth-Error", "mattermost-provision-failed")
		http.Error(w, "Failed to provision user", http.StatusInternalServerError)
		return
	}
	s.recordMattermostSuccess()

	// Create Mattermost session
	session, err := s.mmClient.CreateSession(ctx, mmUser.ID)
	if err != nil {
		s.recordMattermostFailure(err)
		s.logger.Error("failed to create mattermost session", "email", email, "user_id", mmUser.ID, "err", err)
		w.Header().Set("X-Rave-Auth-Error", "mattermost-session-failed")
		http.Error(w, "Failed to create session", http.StatusInternalServerError)
		return
	}
	s.recordMattermostSuccess()

	s.logger.Info("mattermost session created",
		"email", email,
		"mattermost_user_id", mmUser.ID,
		"session_id", session.ID,
	)

	// Set Mattermost session cookies
	// These cookies will be passed through by Traefik to the client
	http.SetCookie(w, &http.Cookie{
		Name:     "MMAUTHTOKEN",
		Value:    session.Token,
		Path:     "/",
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteLaxMode,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     "MMUSERID",
		Value:    mmUser.ID,
		Path:     "/",
		HttpOnly: false, // Mattermost client JS needs this
		Secure:   true,
		SameSite: http.SameSiteLaxMode,
	})

	if isXHR {
		bearer := "Bearer " + session.Token
		w.Header().Set("Authorization", bearer)
		w.Header().Set("X-MMAUTHTOKEN", session.Token)
	}

	// Return 200 to allow the request through
	w.WriteHeader(http.StatusOK)
}

// handleN8NForwardAuth is called by Traefik's ForwardAuth middleware for n8n.
// It reads Authentik identity headers (set by Authentik's proxy outpost forward-auth),
// ensures the user exists in n8n, and allows the request through.
//
// Unlike Mattermost which uses session cookies, n8n SSO via proxy works by:
// 1. User visits /n8n
// 2. Traefik calls Authentik's outpost forward-auth endpoint
// 3. If not authenticated, Authentik redirects to login
// 4. After login, Authentik sets X-Authentik-* headers
// 5. Traefik then calls this endpoint with those headers
// 6. We ensure the n8n user exists and allow through
// 7. n8n sees the authenticated user headers from Authentik
func (s *Server) handleN8NForwardAuth(w http.ResponseWriter, r *http.Request) {
	// Extract user identity from Authentik headers (set by Authentik proxy outpost)
	email := headerFirst(r,
		"X-Authentik-Email",
		"X-Auth-Request-Email",
		"X-Forwarded-Email",
	)
	username := headerFirst(r,
		"X-Authentik-Username",
		"X-Auth-Request-User",
		"X-Forwarded-User",
		"Remote-User",
	)
	name := headerFirst(r,
		"X-Authentik-Name",
		"X-Auth-Request-Name",
		"X-Auth-Request-User",
		"X-Forwarded-User",
	)

	// Log all X-Authentik headers for debugging
	for key, values := range r.Header {
		lowerKey := strings.ToLower(key)
		if strings.HasPrefix(lowerKey, "x-authentik") || strings.HasPrefix(lowerKey, "x-auth-request") {
			s.logger.Debug("n8n authentik header", "key", key, "values", values)
		}
	}

	// If no Authentik headers, deny access
	if email == "" {
		s.logger.Debug("no authentik identity headers found for n8n", "path", r.URL.Path)
		http.Error(w, "Unauthorized - no Authentik session", http.StatusUnauthorized)
		return
	}

	s.logger.Info("n8n forward auth request",
		"email", email,
		"username", username,
		"name", name,
		"path", r.Header.Get("X-Forwarded-Uri"),
	)

	// If n8n client is not configured, just allow through (n8n will handle its own auth)
	if s.n8nClient == nil {
		s.logger.Debug("n8n client not configured, allowing through")
		w.WriteHeader(http.StatusOK)
		return
	}

	// Check circuit breaker
	if s.n8nBreaker != nil && !s.n8nBreaker.allow() {
		s.logger.Warn("n8n circuit open", "email", email)
		// Allow through anyway - n8n will handle auth
		w.WriteHeader(http.StatusOK)
		return
	}

	ctx := r.Context()

	// Ensure user exists in n8n (best effort - don't block if it fails)
	_, err := s.n8nClient.EnsureUser(ctx, n8n.Identity{
		Email:    email,
		Name:     name,
		Username: username,
	})
	if err != nil {
		s.recordN8NFailure(err)
		s.logger.Warn("failed to ensure n8n user (allowing through)", "email", email, "err", err)
		// Don't block - just log and allow through
	} else {
		s.recordN8NSuccess()
		s.logger.Info("n8n user ensured", "email", email)
	}

	// Return 200 to allow the request through
	// n8n will see the X-Authentik-* headers and can use them for user identification
	w.WriteHeader(http.StatusOK)
}

func (s *Server) recordN8NFailure(err error) {
	if s.n8nBreaker == nil {
		return
	}
	if opened := s.n8nBreaker.recordFailure(); opened {
		s.logger.Error("n8n circuit opened", "cooldown", s.n8nBreaker.remaining(), "err", err)
	} else {
		s.logger.Warn("n8n operation failed", "err", err)
	}
}

func (s *Server) recordN8NSuccess() {
	if s.n8nBreaker == nil {
		return
	}
	s.n8nBreaker.recordSuccess()
}

// handleManualSync allows triggering a sync for a specific user via API.
func (s *Server) handleManualSync(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		s.respondJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
		return
	}

	var payload struct {
		Email    string `json:"email"`
		Username string `json:"username"`
		Name     string `json:"name"`
		Subject  string `json:"subject"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		s.respondError(w, http.StatusBadRequest, err)
		return
	}

	if payload.Email == "" {
		s.respondError(w, http.StatusBadRequest, errors.New("email is required"))
		return
	}

	userInfo := &webhook.UserInfo{
		Email:    payload.Email,
		Username: payload.Username,
		Name:     payload.Name,
		Subject:  payload.Subject,
	}

	if err := s.provisionUser(r.Context(), userInfo); err != nil {
		s.respondError(w, http.StatusInternalServerError, err)
		return
	}

	s.respondJSON(w, http.StatusOK, map[string]any{
		"status": "provisioned",
		"email":  payload.Email,
	})
}

// provisionUser ensures a user exists in all downstream services.
func (s *Server) provisionUser(ctx context.Context, info *webhook.UserInfo) error {
	// Store in shadow database
	subject := info.Subject
	if subject == "" {
		subject = info.Email // Use email as fallback subject
	}

	attributes := map[string]string{}
	if info.Username != "" {
		attributes["username"] = info.Username
	}

	shadowUser, err := s.shadowStore.Upsert(ctx, shadow.Identity{
		Provider: "authentik",
		Subject:  subject,
		Email:    info.Email,
		Name:     info.Name,
	}, attributes)
	if err != nil {
		return fmt.Errorf("shadow store upsert: %w", err)
	}

	// Provision to Mattermost
	if s.mmClient != nil {
		if s.mmBreaker != nil && !s.mmBreaker.allow() {
			s.logger.Warn("mattermost circuit open, skipping provisioning", "email", info.Email)
		} else {
			mmUser, err := s.mmClient.EnsureUser(ctx, mattermost.Identity{
				Email: info.Email,
				Name:  info.Name,
				User:  info.Username,
			})
			if err != nil {
				s.recordMattermostFailure(err)
				return fmt.Errorf("mattermost provision: %w", err)
			}
			s.recordMattermostSuccess()
			s.logger.Info("user provisioned to mattermost",
				"email", info.Email,
				"mattermost_id", mmUser.ID,
				"shadow_id", shadowUser.ID,
			)
		}
	}

	s.usersProvisioned.Inc()
	return nil
}

func (s *Server) recordMattermostFailure(err error) {
	if s.mmBreaker == nil {
		return
	}
	if opened := s.mmBreaker.recordFailure(); opened {
		s.logger.Error("mattermost circuit opened", "cooldown", s.mmBreaker.remaining(), "err", err)
	} else {
		s.logger.Warn("mattermost operation failed", "err", err)
	}
}

func (s *Server) recordMattermostSuccess() {
	if s.mmBreaker == nil {
		return
	}
	s.mmBreaker.recordSuccess()
}

func (s *Server) respondJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		s.logger.Error("write response", "err", err)
	}
}

func (s *Server) respondError(w http.ResponseWriter, status int, err error) {
	s.respondJSON(w, status, map[string]string{"error": err.Error()})
}

// headerFirst returns the first non-empty header value from the provided list of keys.
func headerFirst(r *http.Request, keys ...string) string {
	for _, key := range keys {
		if val := strings.TrimSpace(r.Header.Get(key)); val != "" {
			return val
		}
	}
	return ""
}

func (s *Server) logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		s.logger.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}

func (s *Server) newStoreFromConfig() shadow.Store {
	if s.cfg.DatabaseURL == "" {
		s.logger.Warn("AUTH_MANAGER_DATABASE_URL not set; using in-memory shadow store (data lost on restart)")
		return shadow.NewMemoryStore()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	store, err := shadow.NewPostgresStore(ctx, s.cfg.DatabaseURL)
	if err != nil {
		s.logger.Error("failed to init postgres store, falling back to memory", "err", err)
		return shadow.NewMemoryStore()
	}
	return store
}

type circuitBreaker struct {
	mu           sync.Mutex
	failureCount int
	threshold    int
	cooldown     time.Duration
	openUntil    time.Time
}

func newCircuitBreaker(threshold int, cooldown time.Duration) *circuitBreaker {
	return &circuitBreaker{threshold: threshold, cooldown: cooldown}
}

func (c *circuitBreaker) allow() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.openUntil.IsZero() {
		now := time.Now()
		if now.Before(c.openUntil) {
			return false
		}
		c.openUntil = time.Time{}
		c.failureCount = 0
	}
	return true
}

func (c *circuitBreaker) remaining() time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.openUntil.IsZero() {
		return 0
	}
	d := time.Until(c.openUntil)
	if d < 0 {
		return 0
	}
	return d
}

func (c *circuitBreaker) recordSuccess() {
	c.mu.Lock()
	c.failureCount = 0
	c.openUntil = time.Time{}
	c.mu.Unlock()
}

func (c *circuitBreaker) recordFailure() (opened bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.failureCount++
	if c.failureCount >= c.threshold {
		c.openUntil = time.Now().Add(c.cooldown)
		c.failureCount = 0
		return true
	}
	return false
}
