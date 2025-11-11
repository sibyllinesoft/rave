package server

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/rave-org/rave/auth-manager/internal/config"
	"github.com/rave-org/rave/auth-manager/internal/mattermost"
	"github.com/rave-org/rave/auth-manager/internal/pomerium"
	"github.com/rave-org/rave/auth-manager/internal/shadow"
	"github.com/rave-org/rave/auth-manager/internal/tokens"
)

// Server owns the HTTP surface area for the auth-manager control plane.
type Server struct {
	cfg            config.Config
	shadowStore    shadow.Store
	httpServer     *http.Server
	pomeriumSecret []byte
	mmClient       *mattermost.Client
	tokenIssuer    *tokens.Issuer
	metricsRegistry    *prometheus.Registry
	mattermostSessions prometheus.Counter
	tokensIssued       prometheus.Counter
}

// New wires up the HTTP server, routes, and store. A nil store falls back to the
// in-memory implementation so developers can run the binary without extra
// dependencies.
func New(cfg config.Config, store shadow.Store) *Server {
	if store == nil {
		store = newStoreFromConfig(cfg)
	}

	mux := http.NewServeMux()
	srv := &Server{
		cfg:            cfg,
		shadowStore:    store,
		pomeriumSecret: pomerium.DecodeSharedSecret(cfg.PomeriumSharedSecret),
	}
	if cfg.MattermostAdminToken != "" {
		srv.mmClient = mattermost.NewClient(cfg.MattermostURL, cfg.MattermostAdminToken)
	}
	if issuer, err := tokens.NewIssuer(cfg.SigningKey); err != nil {
		log.Fatalf("auth-manager: invalid signing key: %v", err)
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
	mux.HandleFunc("/bridge/mattermost", srv.requirePomerium(srv.handleMattermostBridge))
	mux.HandleFunc("/api/v1/tokens/issue", srv.requirePomerium(srv.handleTokenIssue))
	mux.HandleFunc("/api/v1/tokens/validate", srv.requirePomerium(srv.handleTokenValidate))
	mux.Handle("/metrics", promhttp.HandlerFor(srv.metricsRegistry, promhttp.HandlerOpts{}))

	srv.httpServer = &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      logRequest(mux),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	return srv
}

// Start begins serving HTTP requests.
func (s *Server) Start() error {
	log.Printf("auth-manager listening on %s (idp=%s, mattermost=%s)", s.cfg.ListenAddr, s.cfg.SourceIDP, s.cfg.MattermostURL)
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
	respondJSON(w, http.StatusOK, map[string]any{
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
			respondError(w, http.StatusServiceUnavailable, err)
			return
		}
	}
	respondJSON(w, http.StatusOK, map[string]any{"status": "ready"})
}

func (s *Server) handleShadowUsers(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		users, err := s.shadowStore.List(r.Context())
		if err != nil {
			respondError(w, http.StatusInternalServerError, err)
			return
		}
		respondJSON(w, http.StatusOK, map[string]any{"shadow_users": users})
	case http.MethodPost:
		var payload struct {
			Provider   string            `json:"provider"`
			Subject    string            `json:"subject"`
			Email      string            `json:"email"`
			Name       string            `json:"name"`
			Attributes map[string]string `json:"attributes"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			respondError(w, http.StatusBadRequest, err)
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
			respondError(w, http.StatusBadRequest, errors.New("provider and subject are required"))
			return
		}
		user, err := s.shadowStore.Upsert(r.Context(), shadow.Identity{
			Provider: payload.Provider,
			Subject:  payload.Subject,
			Email:    payload.Email,
			Name:     payload.Name,
		}, payload.Attributes)
		if err != nil {
			respondError(w, http.StatusInternalServerError, err)
			return
		}
		respondJSON(w, http.StatusCreated, user)
	default:
		w.Header().Set("Allow", "GET, POST")
		respondJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method not allowed"})
	}
}

func (s *Server) handleExchange(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusNotImplemented, map[string]string{
		"error": "oauth exchange pipeline not yet implemented",
	})
}

func (s *Server) handleMattermostBridge(w http.ResponseWriter, r *http.Request) {
	identity, ok := pomerium.IdentityFromContext(r.Context())
	if !ok {
		respondError(w, http.StatusUnauthorized, errors.New("pomerium identity missing from context"))
		return
	}

	if s.mmClient == nil {
		respondError(w, http.StatusNotImplemented, errors.New("mattermost client not configured"))
		return
	}

	if identity.Email == "" {
		respondError(w, http.StatusBadRequest, errors.New("pomerium identity missing email claim"))
		return
	}

	attributes := map[string]string{}
	if identity.User != "" {
		attributes["user"] = identity.User
	}
	if len(identity.Groups) > 0 {
		attributes["groups"] = strings.Join(identity.Groups, ",")
	}

	mmUser, err := s.mmClient.EnsureUser(r.Context(), mattermost.Identity{
		Email: identity.Email,
		Name:  identity.Name,
		User:  identity.User,
	})
	if err != nil {
		respondError(w, http.StatusBadGateway, err)
		return
	}

	session, err := s.mmClient.CreateSession(r.Context(), mmUser.ID)
	if err != nil {
		respondError(w, http.StatusBadGateway, err)
		return
	}
	if s.mattermostSessions != nil {
		s.mattermostSessions.Inc()
	}

	attributes["mattermost_user_id"] = mmUser.ID
	shadowUser, err := s.shadowStore.Upsert(r.Context(), shadow.Identity{
		Provider: "pomerium",
		Subject:  identity.Subject,
		Email:    identity.Email,
		Name:     identity.Name,
	}, attributes)
	if err != nil {
		respondError(w, http.StatusInternalServerError, err)
		return
	}

	respondJSON(w, http.StatusOK, map[string]any{
		"shadow_user": shadowUser,
		"mattermost": map[string]any{
			"user":    mmUser,
			"session": session,
			"cookies": []map[string]any{
				{
					"name":     "MMAUTHTOKEN",
					"value":    session.Token,
					"path":     "/",
					"secure":   strings.HasPrefix(strings.ToLower(s.cfg.MattermostURL), "https"),
					"httpOnly": true,
				},
			},
		},
	})
}

func (s *Server) requirePomerium(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		identity, err := pomerium.IdentityFromRequest(r, s.pomeriumSecret)
		if err != nil {
			status := http.StatusUnauthorized
			if errors.Is(err, pomerium.ErrInvalidAssertion) {
				status = http.StatusForbidden
			}
			respondError(w, status, err)
			return
		}
		ctx := pomerium.WithIdentity(r.Context(), identity)
		next.ServeHTTP(w, r.WithContext(ctx))
	}
}

func (s *Server) handleTokenIssue(w http.ResponseWriter, r *http.Request) {
	if s.tokenIssuer == nil {
		respondError(w, http.StatusInternalServerError, errors.New("token issuer not configured"))
		return
	}

	identity, ok := pomerium.IdentityFromContext(r.Context())
	if !ok {
		respondError(w, http.StatusUnauthorized, errors.New("pomerium identity missing from context"))
		return
	}

	var payload struct {
		Subject    string                 `json:"subject"`
		Audience   []string               `json:"audience"`
		TTLSeconds int                    `json:"ttl_seconds"`
		Claims     map[string]interface{} `json:"claims"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		respondError(w, http.StatusBadRequest, err)
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
		respondError(w, http.StatusBadRequest, err)
		return
	}
	if s.tokensIssued != nil {
		s.tokensIssued.Inc()
	}
	respondJSON(w, http.StatusOK, map[string]any{
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
		respondError(w, http.StatusInternalServerError, errors.New("token issuer not configured"))
		return
	}

	var payload struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		respondError(w, http.StatusBadRequest, err)
		return
	}
	if payload.Token == "" {
		respondError(w, http.StatusBadRequest, errors.New("token is required"))
		return
	}

	claims, err := s.tokenIssuer.Validate(payload.Token)
	if err != nil {
		respondError(w, http.StatusUnauthorized, err)
		return
	}
	respondJSON(w, http.StatusOK, map[string]any{
		"claims": claims,
	})
}

func respondJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("write response: %v", err)
	}
}

func respondError(w http.ResponseWriter, status int, err error) {
	respondJSON(w, status, map[string]string{"error": err.Error()})
}

func logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

func newStoreFromConfig(cfg config.Config) shadow.Store {
	if cfg.DatabaseURL == "" {
		return shadow.NewMemoryStore()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	store, err := shadow.NewPostgresStore(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Printf("auth-manager: failed to init postgres store (%v); falling back to in-memory store", err)
		return shadow.NewMemoryStore()
	}
	return store
}
