# Manage Encrypted Secrets with SOPS

This guide replaces the ad-hoc notes that used to live in `PRODUCTION-SECRETS-GUIDE.md`. Use it any time you rotate Age keys, onboard a teammate, or double-check that `config/secrets.yaml` is still encrypted properly.

## Prerequisites
- `sops` 3.7+ and `age` installed on your workstation.
- Access to the repository (clean `git status`).
- At least one Age private key stored in `~/.config/sops/age/` or another secure location.

## 1. Generate or Import an Age Key
If you do not already have a private key that can decrypt RAVE secrets:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/rave.agekey
age-keygen -y ~/.config/sops/age/rave.agekey  # prints the public key
```
Copy the public key (the string starting with `age1…`). Keep the `.agekey` file out of Git; it is already ignored.

## 2. Update `.sops.yaml`
1. Open `.sops.yaml` in your editor.
2. Under the top-level `keys:` list, add your public key (one per line). The refactor lint script insists that only real keys remain, so remove any placeholder `example` entries while you are here.
3. Append the key to every `creation_rules` stanza that should decrypt `config/secrets.yaml`. Usually it is enough to update the first rule with `path_regex: secrets\.yaml$`.
4. Save the file.

### GitHub Actions / CI Recipient
The repository now ships with a dedicated Age public key for the GitHub Actions pipeline (`*ci_key` in `.sops.yaml`). Keep the matching private key in the `SOPS_AGE_KEY_CI` GitHub secret (or the equivalent CI secret store) so workflow jobs can decrypt `config/secrets.yaml` during image builds. Regenerate the key pair if you rotate CI credentials and re-run `sops updatekeys config/secrets.yaml` so the encrypted payload includes the new recipient.

## 3. Export the Private Key for Tooling
`sops` and Nix builds read the private key path from `SOPS_AGE_KEY_FILE`. Set it before editing or building:
```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/rave.agekey
```
For long-lived shells, add the export to your profile or use direnv.

## 4. Edit Secrets Safely
```bash
sops config/secrets.yaml
```
SOPS will decrypt into your editor, then re-encrypt on save. Never copy secrets outside the editor buffer; rely on the Age recipients to control access.

## 5. Run the Lint Script
The refactor plan introduced a small guard-rail to keep `.sops.yaml` and `config/secrets.yaml` in sync:
```bash
python scripts/secrets/lint.py
```
The script verifies:
- `.sops.yaml` exposes at least one non-placeholder Age key.
- Every creation rule references concrete keys.
- `config/secrets.yaml` remains encrypted and only lists recipients that `.sops.yaml` knows about.

If any check fails, fix the reported section and rerun the linter before committing.

## 6. Preview Secret Syncs
Before touching a running VM you can inspect exactly which `/run/secrets/**` files would be written:

```bash
rave secrets diff --secrets-file config/secrets.yaml
```

The command prints a table containing the target path, owner/group, permissions, payload size, and a SHA256 digest (first 12 hex characters) for every file. Use `--format json` if you want to feed the plan into other tooling.

## 7. Sync Secrets into the VM
Once linting passes, push the values into the VM or qcow build:
```bash
rave secrets install --profile production
```
This command decrypts `config/secrets.yaml`, writes the `/run/secrets/**` files expected by the NixOS modules, and restarts affected services. Use `--profile development` for the lightweight image.

### Reference: Grafana secrets

| Selector in `config/secrets.yaml` | Purpose | Runtime path | Consumer |
| --- | --- | --- | --- |
| `grafana.secret-key` | Cookie/session signing key. | `/run/secrets/grafana/secret-key` | `services.grafana.settings.security.secret_key` |
| `grafana.db-password` | Database password Grafana uses in its DSN. | `/run/secrets/grafana/db-password` | Grafana DSN + `postgres-set-grafana-password.service` |
| `database.grafana-password` | Admin UI password (`admin` user). | `/run/secrets/grafana/admin-password` | Grafana security settings |
| `database.mattermost-password` | Mattermost PostgreSQL role password. | `/run/secrets/database/mattermost-password` | `postgres-set-mattermost-password.service` + CLI refresh |
| `database.penpot-password` | Penpot PostgreSQL role password. | `/run/secrets/database/penpot-password` | `postgres-set-penpot-password.service` + CLI refresh |
| `database.n8n-password` | n8n PostgreSQL role password. | `/run/secrets/database/n8n-password` | `postgres-set-n8n-password.service` + CLI refresh |
| `database.outline-password` | Outline PostgreSQL role password. | `/run/secrets/database/outline-password` | Outline module + `postgresql.postStart` hook |
| `database.prometheus-password` | Prometheus exporter PostgreSQL role password. | `/run/secrets/database/prometheus-password` | `postgres-set-prometheus-password.service` + CLI refresh |
| `outline.secret-key` | Outline SESSION/COOKIE key. | `/run/secrets/outline/secret-key` | Outline container `SECRET_KEY` |
| `outline.utils-secret` | Outline UTILS secret for background jobs. | `/run/secrets/outline/utils-secret` | Outline container `UTILS_SECRET` |
| `outline.webhook-secret` | Outline outgoing webhook shared secret. | `/run/secrets/outline/webhook-secret` | Outline container `WEBHOOK_SECRET` |
| `benthos.gitlab-webhook-secret` | Token attached to GitLab system hooks targeting Benthos. | `/run/secrets/benthos/gitlab-webhook-secret` | `gitlab-benthos-webhook.service` + GitLab hook provisioning |

During boot, the `postgres-set-{grafana,mattermost,penpot,n8n,prometheus}-password` services read their respective secrets and update the Postgres roles before the applications start.
Running `rave secrets install` copies these files and immediately refreshes each database password via SSH, so operators do not have to run manual `psql` statements after a rotation.

## 8. Rotate Keys Periodically
- Create a new Age key, add it to `.sops.yaml`, and rerun `sops updatekeys config/secrets.yaml`.
- Remove the old key only after confirming all operators updated their private keys.
- Re-run `python scripts/secrets/lint.py` and `rave secrets install` to propagate the change.

## Related Commands
- `sops updatekeys config/secrets.yaml` – refreshes the encrypted payload with the latest recipients.
- `rave secrets diff` – shows what will change before installing secrets (see CLI help).
- `scripts/secrets/lint.py --help` – additional flags if you store secrets in a non-default path.
