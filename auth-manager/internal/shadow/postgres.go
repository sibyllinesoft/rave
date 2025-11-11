package shadow

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresStore persists shadow users in PostgreSQL.
type PostgresStore struct {
	pool *pgxpool.Pool
}

// NewPostgresStore connects to the database, ensures the schema exists, and returns a Store implementation.
func NewPostgresStore(ctx context.Context, dsn string) (*PostgresStore, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}

	store := &PostgresStore{pool: pool}
	if err := store.ensureSchema(ctx); err != nil {
		pool.Close()
		return nil, err
	}
	return store, nil
}

func (p *PostgresStore) ensureSchema(ctx context.Context) error {
	const ddl = `
CREATE TABLE IF NOT EXISTS shadow_users (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    subject TEXT NOT NULL,
    email TEXT,
    name TEXT,
    attributes JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`
	_, err := p.pool.Exec(ctx, ddl)
	return err
}

// Upsert implements the Store interface.
func (p *PostgresStore) Upsert(ctx context.Context, ident Identity, attributes map[string]string) (ShadowUser, error) {
	if attributes == nil {
		attributes = map[string]string{}
	}
	attrJSON, err := json.Marshal(attributes)
	if err != nil {
		return ShadowUser{}, err
	}

	const upsertSQL = `
INSERT INTO shadow_users (id, provider, subject, email, name, attributes, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6::jsonb, NOW(), NOW())
ON CONFLICT (id)
DO UPDATE SET
    email = EXCLUDED.email,
    name = EXCLUDED.name,
    attributes = EXCLUDED.attributes,
    updated_at = NOW()
RETURNING id, provider, subject, email, name, attributes, created_at, updated_at;
`

	key := identityKey(ident)
	row := p.pool.QueryRow(ctx, upsertSQL, key, ident.Provider, ident.Subject, ident.Email, ident.Name, string(attrJSON))
	return scanShadowUser(row)
}

// List implements the Store interface.
func (p *PostgresStore) List(ctx context.Context) ([]ShadowUser, error) {
	const listSQL = `
SELECT id, provider, subject, email, name, attributes, created_at, updated_at
FROM shadow_users
ORDER BY updated_at DESC
LIMIT 500;
`
	rows, err := p.pool.Query(ctx, listSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := []ShadowUser{}
	for rows.Next() {
		user, err := scanShadowUser(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return users, nil
}

// Close releases the underlying connection pool.
func (p *PostgresStore) Close(ctx context.Context) error {
	p.pool.Close()
	return nil
}

// HealthCheck pings the database to ensure the pool is healthy.
func (p *PostgresStore) HealthCheck(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	return p.pool.Ping(ctx)
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanShadowUser(r rowScanner) (ShadowUser, error) {
	var (
		id, provider, subject, email, name string
		attrRaw                            []byte
		createdAt, updatedAt               time.Time
	)

	if err := r.Scan(&id, &provider, &subject, &email, &name, &attrRaw, &createdAt, &updatedAt); err != nil {
		return ShadowUser{}, err
	}

	attrs := map[string]string{}
	if len(attrRaw) > 0 {
		if err := json.Unmarshal(attrRaw, &attrs); err != nil {
			return ShadowUser{}, err
		}
	}

	if attrs == nil {
		attrs = map[string]string{}
	}

	return ShadowUser{
		ID: id,
		Identity: Identity{
			Provider: provider,
			Subject:  subject,
			Email:    email,
			Name:     name,
		},
		Attributes: attrs,
		CreatedAt:  createdAt.UTC(),
		UpdatedAt:  updatedAt.UTC(),
	}, nil
}
