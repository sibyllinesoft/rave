# OIDC Setup Guide

This guide explains how to wire external OAuth/OIDC providers (Google or GitHub) into a RAVE VM so GitLab and Mattermost enforce single-sign-on.

## Prerequisites

- RAVE CLI installed and on your `PATH` (`pip install -r apps/cli/requirements.txt`).
- VM(s) already created via `rave vm create` and currently running (`rave vm start <company>`).
- `sops` available with access to the age key that can decrypt `config/secrets.yaml`.
- For Google Cloud: the `gcloud` CLI authenticated against the project that will host the OAuth client.
- For GitHub: a GitHub account with permission to create OAuth applications.

## 1. Collect Redirect URIs and Origins

Each company VM exposes GitLab behind a unique HTTPS port. The CLI can generate the callback URLs required when registering OAuth clients:

```bash
# List redirects for the selected VM (defaults to loopback + 127.0.0.1)
rave oauth redirects mattermost-final

# Include production hosts or tunnel endpoints
rave oauth redirects mattermost-final --host gitlab.example.com --host https://gitlab.staging.example.com:10443
```

The output is split into two blocks:

- **Suggested origins** – add these as "Authorized JavaScript origins" (Google) or allowed domains if your provider supports it.
- **Redirect URIs** – copy these verbatim into the Google/GitHub configuration.

If you do not want loopback addresses, add `--no-loopback` to the command.

> **Tip**: Run `rave oauth redirects` with no arguments to print the URLs for every VM configured under `~/.config/rave/vms/`.

## 2. Provision OAuth Clients

### Google Cloud

1. Generate the `gcloud alpha iam oauth-clients create` command tailored for your VM:
   ```bash
   rave oauth bootstrap google --company mattermost-final --project <gcp-project-id>
   ```
   The CLI prints (and optionally runs with `--run`) a `gcloud` command that includes all redirect URIs.

2. Execute the generated command. Capture the `clientId` and `clientSecret` that Google returns.

3. Persist the secret using `sops` so future VM rebuilds stay in sync:
   ```bash
   sops --set '["gitlab"]["oauth-provider-client-secret"] "<client-secret>"' config/secrets.yaml
   ```

4. Apply the credentials to the running VM (GitLab is updated immediately, no rebuild required):
   ```bash
   rave oauth apply --company mattermost-final --provider google --client-id <client-id>
   ```

5. For long-term persistence, update the NixOS config so future rebuilds embed the correct client ID:
   - Edit `infra/nixos/configs/complete-production.nix` and set `services.rave.gitlab.oauth.clientId = "<client-id>";`.
   - Commit the change so future builds pick up the ID.

### GitHub

GitHub does not yet expose an API for provisioning OAuth Apps from the CLI. Use the developer settings UI instead:

1. Visit <https://github.com/settings/developers> → **New OAuth App**.
2. Use these settings:
   - **Application name**: `RAVE GitLab (<company>)`
   - **Homepage URL**: `https://localhost:<https-port>/gitlab`
   - **Authorization callback URL(s)**: copy everything under "GitHub redirect URIs" from `rave oauth redirects`.
3. Copy the Client ID and generate a Client Secret.
4. Persist the secret with `sops` and apply credentials:
   ```bash
   sops --set '["gitlab"]["oauth-provider-client-secret"] "<client-secret>"' config/secrets.yaml
   rave oauth apply --company mattermost-final --provider github --client-id <client-id>
   ```
5. Update `services.rave.gitlab.oauth.clientId` in the Nix config so rebuilds continue to use the GitHub ID.

## 3. Apply or Update Credentials Later

`rave oauth apply` can be rerun whenever you rotate secrets or switch providers. Useful options:

- `--no-secret-sync`: skip copying the secret into `/run/secrets/gitlab/...` (handy when testing temporary credentials).
- `--auto-sign-in/--no-auto-sign-in`: toggle GitLab’s automatic redirect to the external provider. Disable if you want the sign-in page to show the normal login form for troubleshooting.

Example rotation:
```bash
rave oauth apply \
  --company mattermost-final \
  --provider google \
  --client-id <new-client-id> \
  --client-secret <new-secret> \
  --no-auto-sign-in
```

## 4. Testing the Flow

1. Add or sync the user via the CLI (the GitLab identity will be populated on first OAuth login):
   ```bash
   rave user add someone@example.com --oauth-id someone --company mattermost-final --provider google
   ```
2. Open `https://localhost:<https-port>/gitlab/users/sign_in`.
3. Sign in with the external provider. GitLab should create/attach the identity and Mattermost will inherit access via GitLab SSO.
4. If you need to force GitLab to stop auto redirecting, append `?auto_sign_in=false` to the sign-in URL.

## 5. VM Port Reference

Retrieve the HTTPS port for each VM from the CLI:

```bash
jq '.ports.https' ~/.config/rave/vms/*.json
```

Example mapping (your ports may differ):

| Company           | HTTPS Port |
|-------------------|------------|
| mattermost-final  | 8443       |
| demo-company      | 9443       |
| rave-cli-test     | 8743       |

Use these ports when constructing production callback URLs (e.g., `https://gitlab.example.com:8443`).

## 6. CLI Reference

| Command | Purpose |
|---------|---------|
| `rave oauth redirects [company]` | Print origins and redirect URIs for Google/GitHub providers. |
| `rave oauth bootstrap google --company <name>` | Emit (or run with `--run`) a tailored `gcloud alpha iam oauth-clients create` invocation. |
| `rave oauth apply --company <name> --provider <google|github> --client-id …` | Push credentials into the running VM and update GitLab’s settings. |

Keep `config/secrets.yaml` committed after each change so the CLI can resync secrets during VM creation and boots. After updating secrets, run `rave secrets install <company>` to push them into a running VM.
