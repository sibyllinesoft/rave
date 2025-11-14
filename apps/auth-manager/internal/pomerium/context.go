package pomerium

import "context"

type contextKey string

const identityKey contextKey = "pomerium-identity"

// WithIdentity stores the Pomerium identity in the provided context.
func WithIdentity(ctx context.Context, identity Identity) context.Context {
	return context.WithValue(ctx, identityKey, identity)
}

// IdentityFromContext extracts the stored Pomerium identity, if present.
func IdentityFromContext(ctx context.Context) (Identity, bool) {
	identity, ok := ctx.Value(identityKey).(Identity)
	return identity, ok
}
