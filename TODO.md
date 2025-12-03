### 1. Maintenance & Project Hygiene
To make the project easier to develop and maintain, consider the following structural changes:

**A. Manage Go Dependencies properly**
The repository includes the `vendor/` directory (files 5-23, 60-197). This accounts for the vast majority of the file count and noise.
*   **Action:** Remove `src/apps/auth-manager/vendor` from source control.
*   **Fix:** Add `vendor/` to `.gitignore`. Let Nix handle dependencies using `vendorHash` in your `buildGoModule` derivation, or use standard Go modules locally.

**B. Centralize and Decouple Scripts**
You have Python scripts embedded in `infra/nixos/modules/...` (e.g., File 3: `ensure-gitlab-mattermost-ci.py`).
*   **Issue:** Editing Python inside a Nix module definition or a deep subdirectory is difficult for linting and testing.
*   **Fix:** Move these scripts to `src/scripts/` or `src/tools/`. In your Nix configuration, reference them by path or package them as binaries. This allows you to run standard Python linters (black, mypy, ruff) on them.

**C. Unify Entry Points**
You have various shell scripts for testing (`scripts/test-e2e.sh`, `scripts/spinup_smoke.sh`).
*   **Recommendation:** Create a `Justfile` or `Makefile`. This documents the "official" way to run things.
    *   Example: `just test-auth`, `just dev-vm`, `just lint`.

---

### 2. Authentik Integration Issues
The Authentik setup "isn't working." Based on `src/apps/auth-manager/internal/server/server.go` (File 11) and `src/apps/auth-manager/internal/webhook/authentik.go` (File 37), here are the likely causes:

#### Issue A: Webhook Payload Mismatch
In `src/apps/auth-manager/internal/webhook/authentik.go` (File 37), the struct `AuthentikEvent` expects a highly specific JSON structure:

```go
type EventContext struct {
    // ...
    User *EventUser `json:"user"` // Expects a nested user object
    // ...
}
```

**The Problem:** Default Authentik webhooks do **not** send this structure. They usually send a flat event or a different structure depending on the event transport type.
**The Fix:**
1.  In Authentik, go to **Events -> Notifications -> Transports**.
2.  Select your Webhook transport.
3.  Ensure the **Property Mapping** is creating the JSON structure your Go code expects.
4.  **Debugging:** In `server.go` line 168 (`handleAuthentikWebhook`), the logger warns `webhook parse failed` or logs `ignored`. Check the `auth-manager` logs. You likely need to update the Go struct to match the *actual* JSON Authentik is sending, or update Authentik's transformation.

#### Issue B: Forward Auth Header Mismatch
In `src/apps/auth-manager/internal/server/server.go` (File 11), the `handleMattermostForwardAuth` function strictly looks for these headers:

```go
email := r.Header.Get("X-Authentik-Email")
username := r.Header.Get("X-Authentik-Username")
name := r.Header.Get("X-Authentik-Name")
```

**The Problem:** Authentik's Proxy Provider does not send `X-Authentik-Email` by default. It usually sends `X-Auth-Request-Email` or `Remote-User` / `X-Forwarded-User`.
**The Fix:**
1.  In Authentik, go to **Applications -> Providers -> (Your Proxy Provider)**.
2.  Edit the provider.
3.  Look for **Advanced protocol settings**.
4.  Under **Additional Headers**, you must explicitly map them:
    ```text
    X-Authentik-Email: user.email
    X-Authentik-Username: user.username
    X-Authentik-Name: user.name
    ```
    *Without this configuration in Authentik, the variables in your Go server will be empty strings, and it will return `401 Unauthorized`.*

#### Issue C: Circuit Breaker False Positives
Your server uses a circuit breaker (File 11, Line 48: `newCircuitBreaker(5, 30*time.Second)`).
**The Risk:** If Authentik misconfigures or the database is slow on startup (common in dev VMs), the circuit breaker opens.
*   **Observation:** The `handleMattermostForwardAuth` function returns `503 Service Unavailable` if the breaker is open.
*   **Fix:** Check your logs for `"mattermost circuit open"`. If this happens during boot, your `STARTUP_TIMEOUT` in `run-auth-manager-local.sh` (File 30) might be too short, or the breaker sensitivity is too high for a local dev environment.

### 3. Code Specific Findings

**1. Hardcoded Secrets in Scripts**
*   File 25 (`fix-certificates.sh`) contains `sshpass -p 'debug123'`.
*   File 43 (`start-rave-demo.sh`) contains `Password: rave-development-password`.
*   **Recommendation:** Ensure these are only used in local dev/sandbox environments. If these scripts run in CI/CD or Production, switch to SSH keys or environment variable injection immediately.

**2. Insecure TLS Skipping**
*   File 45 (`check_database.sh`) and others use `curl -k`.
*   **Recommendation:** You have a script `fix-certificates.sh` (File 25). Ensure this runs *before* health checks so you can drop the `-k` flag and actually verify TLS is working correctly.

**3. Shadow User Database Logic**
*   In `src/apps/auth-manager/internal/server/server.go`:
    ```go
    if cfg.DatabaseURL == "" {
        return shadow.NewMemoryStore()
    }
    ```
*   **Risk:** If the Postgres connection fails or isn't configured in the environment variables, it silently falls back to `MemoryStore`. Users will be provisioned, work fine, and then **disappear** when the service restarts.
*   **Fix:** Make `DatabaseURL` mandatory in production, or add a massive warning log when falling back to Memory Store.

### Summary of Next Steps
1.  **Git:** Add `src/apps/auth-manager/vendor/` to `.gitignore`.
2.  **Authentik:** Configure "Additional Headers" in the Authentik Proxy Provider to send `X-Authentik-Email`.
3.  **Authentik:** Verify the Webhook JSON body matches the Go struct tags in `authentik.go`.
4.  **Go:** Check `auth-manager` logs to see if it's falling back to `MemoryStore` unintentionally.
