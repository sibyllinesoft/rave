package shadow

import (
	"context"
	"fmt"
	"sync"
	"time"
)

// Identity represents the upstream identity provider result we care about.
type Identity struct {
	Provider string `json:"provider"`
	Subject  string `json:"subject"`
	Email    string `json:"email"`
	Name     string `json:"name"`
}

// ShadowUser is the record we will hand to systems like Mattermost.
type ShadowUser struct {
	ID         string            `json:"id"`
	Identity   Identity          `json:"identity"`
	Attributes map[string]string `json:"attributes"`
	CreatedAt  time.Time         `json:"created_at"`
	UpdatedAt  time.Time         `json:"updated_at"`
}

// Store captures the persistence contract for shadow users.
type Store interface {
	Upsert(ctx context.Context, ident Identity, attributes map[string]string) (ShadowUser, error)
	List(ctx context.Context) ([]ShadowUser, error)
	Close(ctx context.Context) error
	HealthCheck(ctx context.Context) error
}

// MemoryStore is a trivial in-memory implementation useful for prototyping.
type MemoryStore struct {
	mu    sync.RWMutex
	users map[string]ShadowUser
}

// NewMemoryStore builds an empty MemoryStore.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{users: make(map[string]ShadowUser)}
}

// Upsert inserts or updates a shadow user in-place using provider+subject as the key.
func (m *MemoryStore) Upsert(ctx context.Context, ident Identity, attributes map[string]string) (ShadowUser, error) {
	key := identityKey(ident)

	m.mu.Lock()
	defer m.mu.Unlock()

	user, ok := m.users[key]
	now := time.Now().UTC()
	if !ok {
		user = ShadowUser{
			ID:         key,
			Identity:   ident,
			Attributes: map[string]string{},
			CreatedAt:  now,
		}
	}

	// Merge attributes while keeping prior keys when not provided.
	if user.Attributes == nil {
		user.Attributes = map[string]string{}
	}
	for k, v := range attributes {
		user.Attributes[k] = v
	}

	user.Identity = ident
	user.UpdatedAt = now
	m.users[key] = user

	return user, nil
}

// List returns a snapshot of existing shadow users.
func (m *MemoryStore) List(ctx context.Context) ([]ShadowUser, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	out := make([]ShadowUser, 0, len(m.users))
	for _, user := range m.users {
		out = append(out, user)
	}
	return out, nil
}

// Close implements Store.
func (m *MemoryStore) Close(ctx context.Context) error {
	return nil
}

// HealthCheck implements Store.
func (m *MemoryStore) HealthCheck(ctx context.Context) error {
	return nil
}

func identityKey(ident Identity) string {
	return fmt.Sprintf("%s::%s", ident.Provider, ident.Subject)
}
