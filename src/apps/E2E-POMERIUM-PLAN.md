# Pomerium → Google OAuth → Mattermost E2E Plan

Context on 2025-11-13: we already moved the CLI into `apps/cli`, the Go auth-manager into `apps/auth-manager`, and Nix sources under `infra/nixos`. Auth Manager now knows about both the public and internal Mattermost URLs and has plumbing ready for an embedded reverse proxy (`/mattermost*`) that can mint sessions automatically, but the proxy path still needs to be fully wired. This document captures the concrete steps required so the next agent can deliver a working end-to-end flow where:

1. Pomerium is configured for Google/GitHub/Azure (selectable from the CLI).
2. Auth Manager receives the Pomerium identity, ensures the Mattermost user exists, and forwards the request downstream while injecting the Mattermost session.
3. A `rave vm build-image --profile production --idp google ...` build produces a qcow image that boots with Google OAuth wired, so a human can authenticate through Google → Pomerium and land inside Mattermost already signed in.

---

## 1. Auth Manager Reverse Proxy & Session Injection

- [ ] Finish the reverse proxy implementation introduced in `apps/auth-manager/internal/server/server.go`:
  - Ensure `/mattermost` and `/mattermost/*` routes invoke the proxy, not just the legacy `/bridge/mattermost` JSON endpoint.
  - Double-check that `buildMattermostCookies` sets both `MMAUTHTOKEN` and `MMUSERID` with the correct domain/path (derived from `AUTH_MANAGER_MATTERMOST_URL`) and that we mirror them into the incoming `http.Request` before proxying.
  - Add integration tests (Go) that simulate a Pomerium identity and assert that the proxy injects cookies and forwards requests. Consider using `httptest.Server` for the upstream Mattermost stub.
  - Decide whether we need to strip/override incoming headers (e.g., `Authorization`) before proxying to avoid leaking the Pomerium assertion.

- [ ] Update the Mattermost client to hit the **internal** URL (already parameterised) and add a method to fetch the momentary user id from cookies if needed.

- [ ] Extend the auth-manager unit tests to cover:
  - Missing Mattermost internal URL.
  - Cookie generation when running on HTTP (dev) vs. HTTPS (prod).
  - Reuse of cached sessions (if you add that optimization).

## 2. Multi-provider Pomerium configuration

- [ ] Define provider presets (google/github/azure/gitlab/custom) in a new CLI module (e.g., `apps/cli/providers.py`) that returns:
  - `provider` ID (`google`, `github`, `azuread`, etc.)
  - Default issuer URLs.
  - Required scopes and audience.
  - Which secrets must exist in `config/secrets.yaml` or CLI flags.

- [ ] Extend `rave vm create` / `rave vm build-image` to accept `--idp-provider`, `--idp-client-id`, `--idp-client-secret`, and `--idp-redirect-uri`.
  - Persist the chosen provider metadata inside the VM config JSON so follow-up commands know which OAuth provider is baked into the image.
  - Teach `vm_manager.create_vm` to pass these values into the Nix build via environment variables or an override file (e.g., write a JSON metadata file and include it via `nix build .#production --argjson pomeriumConfig ...`).

- [ ] Update `infra/nixos/configs/complete-production.nix` (and the dev/demo variants) to read the provider data from `config.services.rave.pomerium.idp`.
  - Allow `clientSecretFile` to map to specific secrets (`config/secrets.yaml` entries keyed by provider, e.g., `pomerium/google-client-secret`).
  - Add a helper module that sets sane defaults for each provider (e.g., Google uses `https://accounts.google.com`, Azure uses `https://login.microsoftonline.com/{tenant}/v2.0`).

- [ ] Ensure secrets are created via SOPS:
  - Add new selectors under `config/secrets.yaml` for `pomerium/google-client-id`, `pomerium/google-client-secret`, etc.
  - Update `docs/how-to/manage-secrets.md` with the provider matrix and instructions for rotating them.

## 3. CLI UX & Docs

- [ ] `rave vm list-profiles` should display the active IdP per VM (read from the stored metadata).
- [ ] Add `rave vm show-auth` (or similar) to print the configured IdP provider, client ID, redirect URIs, and the generated Mattermost URL for the chosen VM.
- [ ] Update `README.md` and `docs/how-to/provision-complete-vm.md` with:
  - Steps to register Google OAuth (console instructions, redirect URI, scopes).
  - CLI examples: `rave vm build-image --profile production --idp google --idp-client-id ... --idp-client-secret ...`.
  - Explicit note that the default CLI experience is still GitLab unless flags override it.

## 4. Mattermost SSO alignment

- [ ] Ensure the Mattermost OAuth settings are converted to “OpenID Connect” mode if we switch providers.
  - For Google, we may prefer hooking into Mattermost’s native Google OAuth rather than using GitLab OAuth. Decide whether we keep GitLab as the backend IdP and let Pomerium handle Google, or if we need to adjust Mattermost’s own OAuth provider. Document the decision.
- [ ] If we keep GitLab internally but let Pomerium front Google, we must confirm GitLab can accept Google tokens (Sanity check: GitLab currently acts as the IdP, so you probably want Pomerium only. Make sure Mattermost’s GitLab OAuth is disabled when Pomerium takes over.)

## 5. Image build + E2E verification

- [ ] `nix build .#production` should accept a JSON file (generated by CLI) that contains:
  - Pomerium provider metadata.
  - Auth-manager listen URL (if non-default).
  - Mattermost public/internal URLs (to keep CLI overrides in sync).
  - Feature flags (e.g., disable GitLab OAuth on Mattermost when Pomerium is active).

- [ ] After building the qcow, run `rave vm launch-local --profile production --idp google ... --keep-vm` and perform an E2E test:
  1. Start Pomerium and verify `/pomerium/.well-known/pomerium` returns the new provider metadata.
  2. Hit `https://localhost:8443/mattermost/` → ensure the browser is redirected to Pomerium → Google OAuth login → returns to `/pomerium/mattermost/`.
  3. Confirm Mattermost renders without additional login prompts (Auth Manager should have injected cookies).
  4. Check Auth Manager logs (`journalctl -u auth-manager.service`) for `mattermost user created/session issued`.
  5. Document the exact Google OAuth steps (client ID, secret, allowed redirect URIs) in `docs/how-to/oauth-google.md` (new file).

- [ ] Capture the test commands and curl snippets in a new `apps/E2E-POMERIUM-GOOGLE.md` runbook so future automation can reproduce it.

## 6. Stretch goals / nice-to-have

- [ ] Add GitHub/Azure provider presets once the Google flow is working; they should follow the same CLI/Nix plumbing.
- [ ] Provide a `scripts/e2e/pomerium-google.sh` that spins up the VM, exposes SSH port overrides, and prints the relevant URLs / credentials.
- [ ] Consider adding a Python integration test under `tests/python/` that shells into the VM, hits the Auth Manager health endpoints, and ensures `/mattermost` responds with a 302 when cookies are missing.

---

**Dependencies / Open Questions**

1. Do we disable GitLab entirely when Pomerium fronts Google (so there’s only one IdP), or do we keep GitLab around for non-Google users? Decide before wiring the `services.rave.gitlab.oauth` options.
2. Where should CLI store third-party credentials? For now, use SOPS-managed selectors in `config/secrets.yaml`; long term we may want `pomerium-providers.yaml`.
3. Google OAuth requires verified redirect URIs. Confirm the host/ports we use (`https://localhost:8443/oauth2/callback`) are permitted, or provide instructions for tunnelling (ngrok, etc.) if not.

Once these tasks are complete, the next agent can run the documented commands to produce a qcow, boot it, and walk through Pomerium → Google → Mattermost without additional auth prompts. Use this plan as the authoritative TODO list. (When editing, keep it under `apps/` so it travels with the CLI/auth-manager code.)
