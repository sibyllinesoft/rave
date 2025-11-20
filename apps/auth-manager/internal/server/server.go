package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/rave-org/rave/apps/auth-manager/internal/bridge"
	"github.com/rave-org/rave/apps/auth-manager/internal/config"
	"github.com/rave-org/rave/apps/auth-manager/internal/mattermost"
	"github.com/rave-org/rave/apps/auth-manager/internal/pomerium"
	"github.com/rave-org/rave/apps/auth-manager/internal/shadow"
	"github.com/rave-org/rave/apps/auth-manager/internal/tokens"
)

// Server owns the HTTP surface area for the auth-manager control plane.
type Server struct {
	cfg                    config.Config
	shadowStore            shadow.Store
	httpServer             *http.Server
	pomeriumSecret         []byte
	mmClient               *mattermost.Client
	tokenIssuer            *tokens.Issuer
	metricsRegistry        *prometheus.Registry
	mattermostSessions     prometheus.Counter
	tokensIssued           prometheus.Counter
	mattermostProxy        *httputil.ReverseProxy
	mattermostPublicURL    *url.URL
	mattermostPathPrefix   string
	mattermostCookieDomain string
	mattermostCookiePath   string
	mattermostCookieSecure bool
	logger                 *slog.Logger
	mmBreaker              *circuitBreaker
}

// New wires up the HTTP server, routes, and store. A nil store falls back to the
// in-memory implementation so developers can run the binary without extra
// dependencies.
func New(cfg config.Config, store shadow.Store, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}

	srv := &Server{
		cfg:            cfg,
		logger:         logger,
		pomeriumSecret: pomerium.DecodeSharedSecret(cfg.PomeriumSharedSecret),
		mmBreaker:      newCircuitBreaker(5, 30*time.Second),
	}
	if store == nil {
		store = srv.newStoreFromConfig()
	}
	srv.shadowStore = store

	mux := http.NewServeMux()

	publicURL, err := url.Parse(cfg.MattermostURL)
	if err != nil {
		logger.Error("invalid mattermost URL", "url", cfg.MattermostURL, "err", err)
		panic(err)
	}
	internalURL, err := url.Parse(cfg.MattermostInternalURL)
	if err != nil {
		logger.Error("invalid mattermost internal URL", "url", cfg.MattermostInternalURL, "err", err)
		panic(err)
	}
	srv.mattermostPublicURL = publicURL
	srv.mattermostPathPrefix = normalizePathPrefix(publicURL.Path)
	srv.mattermostCookiePath = srv.mattermostPathPrefix
	if srv.mattermostCookiePath == "" {
		srv.mattermostCookiePath = "/"
	}
	srv.mattermostCookieDomain = publicURL.Hostname()
	srv.mattermostCookieSecure = strings.EqualFold(publicURL.Scheme, "https")
	srv.mattermostProxy = newMattermostProxy(internalURL, srv.mattermostPathPrefix)
	if srv.mattermostProxy != nil {
		srv.mattermostProxy.ErrorHandler = srv.handleProxyError
	}

	if cfg.MattermostAdminToken != "" {
		srv.mmClient = mattermost.NewClient(cfg.MattermostInternalURL, cfg.MattermostAdminToken)
	}
	if issuer, err := tokens.NewIssuer(cfg.SigningKey); err != nil {
		logger.Error("invalid signing key", "err", err)
		panic(err)
	} else {
		srv.tokenIssuer = issuer
	}

	reg := prometheus.NewRegistry()
	srv.metricsRegistry = reg
	srv.mattermostSessions = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "auth_manager_mattermost_sessions_total",
		Help: "Number of Mattermost sessions issued via the bridge",
	})
	srv.tokensIssued = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "auth_manager_tokens_issued_total",
		Help: "Number of JWT tokens issued via /api/v1/tokens/issue",
	})
	reg.MustRegister(srv.mattermostSessions, srv.tokensIssued)

	mux.HandleFunc("/healthz", srv.handleHealth)
	mux.HandleFunc("/readyz", srv.handleReady)
	mux.HandleFunc("/api/v1/shadow-users", srv.handleShadowUsers)
	mux.HandleFunc("/api/v1/oauth/exchange", srv.handleExchange)
	if srv.mattermostProxy != nil {
		mux.Handle("/mattermost", srv.requirePomerium(srv.handleMattermostProxy))
		mux.Handle("/mattermost/", srv.requirePomerium(srv.handleMattermostProxy))
	}
	mux.HandleFunc("/bridge/mattermost", srv.requirePomerium(srv.handleMattermostLegacy))
	mux.HandleFunc("/api/v1/tokens/issue", srv.requirePomerium(srv.handleTokenIssue))
	mux.HandleFunc("/api/v1/tokens/validate", srv.requirePomerium(srv.handleTokenValidate))
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
	s.logger.Info("auth-manager listening", "addr", s.cfg.ListenAddr, "idp", s.cfg.SourceIDP, "mattermost", s.cfg.MattermostURL)
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
		"source_idp":   s.cfg.SourceIDP,
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
	case http.MethodPost:
		var payload struct {
			Provider   string            `json:"provider"`
			Subject    string            `json:"subject"`
			Email      string            `json:"email"`
			Name       string            `json:"name"`
			Attributes map[string]string `json:"attributes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			s.respondError(w, http.StatusBadRequest, err)
			return
		}
		if payload.Provider == "" || payload.Subject == "" {
			if identity, err := pomerium.IdentityFromRequest(r, s.pomeriumSecret); err == nil {
				payload.Provider = "pomerium"
				payload.Subject = identity.Subject
				if payload.Email == "" {
					payload.Email = identity.Email
				}
				if payload.Name == "" {
					payload.Name = identity.Name
				}
				if payload.Attributes == nil {
					payload.Attributes = map[string]string{}
				}
				if identity.User != "" {
					payload.Attributes["user"] = identity.User
				}
				if len(identity.Groups) > 0 {
					payload.Attributes["groups"] = strings.Join(identity.Groups, ",")
				}
			}
		}
		if payload.Provider == "" || payload.Subject == "" {
			s.respondError(w, http.StatusBadRequest, errors.New("provider and subject are required"))
			return
		}
		user, err := s.shadowStore.Upsert(r.Context(), shadow.Identity{
			Provider: payload.Provider,
			Subject:  payload.Subject,
			Email:    payload.Email,
			Name:     payload.Name,
		}, payload.Attributes)
		if err != nil {
			s.respondError(w, http.StatusInternalServerError, err)
			return
		}
		s.respondJSON(w, http.StatusCreated, user)
	default:
		w.Header().Set("Allow", "GET, POST")
		s.respondJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

func (s *Server) handleExchange(w http.ResponseWriter, r *http.Request) {
	s.respondJSON(w, http.StatusNotImplemented, map[string]string{
		"error": "oauth exchange pipeline not yet implemented",
	})
}

func (s *Server) handleMattermostProxy(w http.ResponseWriter, r *http.Request) {
	identity, ok := pomerium.IdentityFromContext(r.Context())
	if !ok {
		s.respondError(w, http.StatusUnauthorized, errors.New("pomerium identity missing from context"))
		return
	}

	if s.mmClient == nil || s.mattermostProxy == nil {
		s.respondError(w, http.StatusNotImplemented, errors.New("mattermost client not configured"))
		return
	}

	if s.mmBreaker != nil && !s.mmBreaker.allow() {
		wait := s.mmBreaker.remaining()
		s.respondError(w, http.StatusServiceUnavailable, fmt.Errorf("mattermost temporarily unavailable, retry in %s", wait.Truncate(time.Second)))
		return
	}

	if identity.Email == "" {
		s.respondError(w, http.StatusBadRequest, errors.New("pomerium identity missing email claim"))
		return
	}

	if needsRedirectToSlash(r.URL.Path, s.mattermostPathPrefix) {
		target := ensureTrailingSlash(r.URL.Path)
		if r.URL.RawQuery != "" {
			target = target + "?" + r.URL.RawQuery
		}
		http.Redirect(w, r, target, http.StatusFound)
		return
	}

	if !hasMattermostCookie(r) {
		session, err := s.ensureMattermostSession(r.Context(), identity)
		if err != nil {
			s.recordMattermostFailure(err)
			s.respondError(w, http.StatusBadGateway, err)
			return
		}
		s.recordMattermostSuccess()
		for _, cookie := range s.buildMattermostCookies(session.UserID, session.Token) {
			http.SetCookie(w, cookie)
			r.AddCookie(requestCookieFor(cookie))
		}
	}

	s.mattermostProxy.ServeHTTP(w, r)
	s.recordMattermostSuccess()
}

func (s *Server) handleMattermostLegacy(w http.ResponseWriter, r *http.Request) {
	identity, ok := pomerium.IdentityFromContext(r.Context())
	if !ok {
		s.respondError(w, http.StatusUnauthorized, errors.New("pomerium identity missing from context"))
		return
	}

	if s.mmClient == nil {
		s.respondError(w, http.StatusNotImplemented, errors.New("mattermost client not configured"))
		return
	}

	if identity.Email == "" {
		s.respondError(w, http.StatusBadRequest, errors.New("pomerium identity missing email claim"))
		return
	}

	session, err := s.ensureMattermostSession(r.Context(), identity)
	if err != nil {
		s.recordMattermostFailure(err)
		s.respondError(w, http.StatusBadGateway, err)
		return
	}
	s.recordMattermostSuccess()

	s.respondJSON(w, http.StatusOK, map[string]any{
		"session": session,
	})
}

func (s *Server) ensureMattermostSession(ctx context.Context, identity pomerium.Identity) (mattermost.Session, error) {
	canon := bridge.FromPomerium(identity)
	mmIdent := canon.MattermostIdentity()

	attributes := map[string]string{}
	if mmIdent.User != "" {
		attributes["user"] = mmIdent.User
	}
	if len(identity.Groups) > 0 {
		attributes["groups"] = strings.Join(identity.Groups, ",")
	}

	mmUser, err := s.mmClient.EnsureUser(ctx, mmIdent)
	if err != nil {
		return mattermost.Session{}, err
	}

	session, err := s.mmClient.CreateSession(ctx, mmUser.ID)
	if err != nil {
		return mattermost.Session{}, err
	}
	if s.mattermostSessions != nil {
		s.mattermostSessions.Inc()
	}

	attributes["mattermost_user_id"] = mmUser.ID
	_, err = s.shadowStore.Upsert(ctx, shadow.Identity{
		Provider: "pomerium",
		Subject:  canon.Subject,
		Email:    canon.Email,
		Name:     mmIdent.Name,
	}, attributes)
	if err != nil {
		return mattermost.Session{}, err
	}

	return session, nil
}

func hasMattermostCookie(r *http.Request) bool {
	if _, err := r.Cookie("MMAUTHTOKEN"); err == nil {
		return true
	}
	return false
}

func needsRedirectToSlash(path, prefix string) bool {
	if prefix == "" || prefix == "/" {
		return false
	}
	trimmed := strings.TrimSuffix(prefix, "/")
	if trimmed == "" {
		trimmed = "/"
	}
	return path == trimmed && !strings.HasSuffix(path, "/")
}

func ensureTrailingSlash(path string) string {
	if strings.HasSuffix(path, "/") {
		return path
	}
	return path + "/"
}

func (s *Server) buildMattermostCookies(userID, token string) []*http.Cookie {
	path := s.mattermostCookiePath
	if path == "" {
		path = "/"
	}
	domain := s.mattermostCookieDomain
	secure := s.mattermostCookieSecure
	return []*http.Cookie{
		{
			Name:     "MMAUTHTOKEN",
			Value:    token,
			Path:     path,
			Domain:   domain,
			Secure:   secure,
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
		},
		{
			Name:     "MMUSERID",
			Value:    userID,
			Path:     path,
			Domain:   domain,
			Secure:   secure,
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
		},
	}
}

func requestCookieFor(c *http.Cookie) *http.Cookie {
	return &http.Cookie{
		Name:  c.Name,
		Value: c.Value,
	}
}

func (s *Server) requirePomerium(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		identity, err := pomerium.IdentityFromRequest(r, s.pomeriumSecret)
		if err != nil {
			status := http.StatusUnauthorized
			if errors.Is(err, pomerium.ErrInvalidAssertion) {
				status = http.StatusForbidden
			}
			s.respondError(w, status, err)
			return
		}
		ctx := pomerium.WithIdentity(r.Context(), identity)
		next.ServeHTTP(w, r.WithContext(ctx))
	}
}

func (s *Server) handleTokenIssue(w http.ResponseWriter, r *http.Request) {
	if s.tokenIssuer == nil {
		s.respondError(w, http.StatusInternalServerError, errors.New("token issuer not configured"))
		return
	}

	identity, ok := pomerium.IdentityFromContext(r.Context())
	if !ok {
		s.respondError(w, http.StatusUnauthorized, errors.New("pomerium identity missing from context"))
		return
	}

	var payload struct {
		Subject    string                 `json:"subject"`
		Audience   []string               `json:"audience"`
		TTLSeconds int                    `json:"ttl_seconds"`
		Claims     map[string]interface{} `json:"claims"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		s.respondError(w, http.StatusBadRequest, err)
		return
	}
	if payload.Subject == "" {
		payload.Subject = identity.Subject
	}
	if payload.Claims == nil {
		payload.Claims = map[string]interface{}{}
	}
	ttl := time.Duration(payload.TTLSeconds) * time.Second
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}

	token, err := s.tokenIssuer.Issue(payload.Subject, payload.Audience, ttl, payload.Claims)
	if err != nil {
		s.respondError(w, http.StatusBadRequest, err)
		return
	}
	if s.tokensIssued != nil {
		s.tokensIssued.Inc()
	}
	s.respondJSON(w, http.StatusOK, map[string]any{
		"token":         token.Value,
		"expires_at":    token.ExpiresAt.Format(time.RFC3339Nano),
		"subject":       payload.Subject,
		"issued_to":     identity.Subject,
		"audience":      payload.Audience,
		"custom_claims": payload.Claims,
	})
}

func (s *Server) handleTokenValidate(w http.ResponseWriter, r *http.Request) {
	if s.tokenIssuer == nil {
		s.respondError(w, http.StatusInternalServerError, errors.New("token issuer not configured"))
		return
	}

	var payload struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		s.respondError(w, http.StatusBadRequest, err)
		return
	}
	if payload.Token == "" {
		s.respondError(w, http.StatusBadRequest, errors.New("token is required"))
		return
	}

	claims, err := s.tokenIssuer.Validate(payload.Token)
	if err != nil {
		s.respondError(w, http.StatusUnauthorized, err)
		return
	}
	s.respondJSON(w, http.StatusOK, map[string]any{
		"claims": claims,
	})
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

func (s *Server) handleProxyError(w http.ResponseWriter, r *http.Request, err error) {
	s.recordMattermostFailure(err)
	s.respondError(w, http.StatusBadGateway, err)
}

func (s *Server) logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		s.logger.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
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

func (s *Server) newStoreFromConfig() shadow.Store {
	if s.cfg.DatabaseURL == "" {
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

func newMattermostProxy(target *url.URL, publicPrefix string) *httputil.ReverseProxy {
	proxy := httputil.NewSingleHostReverseProxy(target)
	prefix := normalizePathPrefix(publicPrefix)
	basePath := target.Path
	proxy.Director = func(req *http.Request) {
		req.URL.Scheme = target.Scheme
		req.URL.Host = target.Host
		req.Host = target.Host
		trimmed := stripPublicPrefix(req.URL.Path, prefix)
		req.URL.Path = singleJoiningSlash(basePath, trimmed)
		if req.URL.RawPath != "" {
			req.URL.RawPath = req.URL.Path
		}
	}
	return proxy
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

func normalizePathPrefix(prefix string) string {
	if prefix == "" {
		return "/"
	}
	if !strings.HasPrefix(prefix, "/") {
		prefix = "/" + prefix
	}
	if prefix != "/" && strings.HasSuffix(prefix, "/") {
		prefix = strings.TrimSuffix(prefix, "/")
	}
	if prefix == "" {
		return "/"
	}
	return prefix
}

func stripPublicPrefix(path, prefix string) string {
	if prefix == "/" || prefix == "" {
		return path
	}
	if strings.HasPrefix(path, prefix) {
		stripped := strings.TrimPrefix(path, prefix)
		if stripped == "" {
			return "/"
		}
		if !strings.HasPrefix(stripped, "/") {
			return "/" + stripped
		}
		return stripped
	}
	return path
}

func singleJoiningSlash(a, b string) string {
	aslash := strings.HasSuffix(a, "/")
	bslash := strings.HasPrefix(b, "/")
	switch {
	case aslash && bslash:
		return a + b[1:]
	case !aslash && !bslash:
		return a + "/" + b
	}
	return a + b
}
