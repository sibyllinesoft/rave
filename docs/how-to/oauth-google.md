# Configure Google OAuth for Pomerium

This guide walks through registering a Google OAuth client, storing the credentials with SOPS, and baking them into a RAVE VM image so Pomerium can act as the front door for Mattermost and other services.
If you plan to use (the now default) Authentik or disable Pomerium entirely, see
`docs/how-to/authentik.md` for the `RAVE_DISABLE_POMERIUM` workflow and the required secrets.

## 1. Prerequisites

- A Google Cloud project with OAuth consent screen configured for internal testing.
- The repo's AGE private key (usually `~/.config/sops/age/keys.txt`). Run `rave secrets init` if you still need to bootstrap it.
- `.env` populated with `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` (used as fallbacks when CLI flags are omitted).

## 2. Register the OAuth client

1. Visit <https://console.cloud.google.com/apis/credentials> and click **Create Credentials → OAuth client ID**.
2. Choose **Web application** and add the following authorized redirect URIs (adjust the port if you override HTTPS later):
   - `https://localhost:8443/oauth2/callback`
   - `https://localhost:8443/pomerium/callback` (optional legacy path)
3. Note the generated **Client ID** and **Client secret**.

## 3. Store the secrets with SOPS

Update `config/secrets.yaml` so `sops-nix` can materialise the credentials inside the VM:

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops config/secrets.yaml
```

Add (or update) entries similar to:

```yaml
pomerium:
    google-client-id: <encrypted client id>
    google-client-secret: <encrypted client secret>
```

Save and commit the encrypted file. The existing `sops` metadata at the bottom of the file will update automatically.

Finally, tell `sops-nix` where to write the decrypted files by adding selectors (if they do not already exist) to `infra/nixos/configs/complete-production.nix`:

```nix
{ selector = "[\"pomerium\"][\"google-client-id\"]";
  path = "/run/secrets/pomerium/google-client-id"; ... }
{ selector = "[\"pomerium\"][\"google-client-secret\"]";
  path = "/run/secrets/pomerium/google-client-secret"; ... }
```

## 4. Build an image with the Google IdP baked in

Use the new IdP flags on `rave vm build-image` (or `rave vm create`) to point the build at your credentials. The CLI prefers CLI arguments, then `.env`, and finally the SOPS selectors if you pass `--idp-secret-selector`.

```bash
export GOOGLE_OAUTH_CLIENT_ID=your-client-id
export GOOGLE_OAUTH_CLIENT_SECRET=your-client-secret

rave vm build-image \
  --profile production \
  --idp-provider google \
  --idp-client-id "$GOOGLE_OAUTH_CLIENT_ID" \
  --idp-client-secret "$GOOGLE_OAUTH_CLIENT_SECRET"
```

If you already copied the secrets into `/run/secrets/pomerium/google-client-secret`, switch to the selector form so the secret never touches the build logs:

```bash
rave vm build-image \
  --profile production \
  --idp-provider google \
  --idp-client-id "$GOOGLE_OAUTH_CLIENT_ID" \
  --idp-secret-selector '["pomerium"]["google-client-secret"]'
```

The same flags are available on `rave vm create` so tenant-specific images can carry their own OAuth metadata.

## 5. Verify end-to-end

1. Launch the VM (`rave vm launch-local --profile production --https-port 8443`).
2. Visit `https://localhost:8443/mattermost/`. You should be redirected to Pomerium, then Google, and land back in Mattermost with a session already minted by Auth Manager.
3. Inspect `journalctl -u pomerium.service -u auth-manager.service` if anything fails—the injected IdP metadata is printed at start-up.

## 6. Rotating credentials

Rotate the Google secret by editing `config/secrets.yaml` with `sops`, re-running `rave secrets install <vm-name>`, and either rebuilding the qcow2 or restarting the VM so Pomerium picks up the new `/run/secrets/pomerium/*` content.

Need more context? See `docs/how-to/provision-complete-vm.md` for the full VM provisioning workflow and `apps/E2E-POMERIUM-PLAN.md` for the remaining stretch goals.
