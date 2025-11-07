# Provision a Complete RAVE VM

This how-to combines the old "COMPLETE-BUILD" and "PRODUCTION-SECRETS-GUIDE" playbooks into a single, repeatable workflow for producing a ready-to-run qcow2 image with encrypted secrets.

## Prerequisites
- **Host tooling**: Nix 2.18+, QEMU, Python 3.10+, `age` + `sops` available on PATH.
- **Repository**: Fresh clone of `sibyllinesoft/rave` with `git status` clean.
- **Secrets**: An Age key pair stored locally (private key in `~/.config/sops/age/keys.txt` or via `SOPS_AGE_KEY_FILE`).
- **Disk space**: ≥40 GB free for the qcow2 output + build store.

> 💡 Tip: run `scripts/repo/hygiene-check.sh` before and after these steps to make sure large artifacts stay out of Git.

## Step 1 – Prepare Workspace
1. Update dependencies:
   ```bash
   nix flake update
   ```
2. Ensure CLI requirements are installed (only needs to be done once per host):
   ```bash
   cd cli && pip install -r requirements.txt && cd -
   ```
3. Export your Age key so `sops` and Nix builds can decrypt secrets:
   ```bash
   export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
   ```

## Step 2 – Manage Secrets with SOPS
1. Generate or rotate keys (one-time per environment):
   ```bash
   age-keygen -o ~/.config/sops/age/rave-prod.agekey
   age-keygen -y ~/.config/sops/age/rave-prod.agekey  # prints public key
   ```
2. Add the new recipient to `config/secrets.yaml` under the `sops.age` list and run:
   ```bash
   sops updatekeys config/secrets.yaml
   ```
3. Edit secrets securely:
   ```bash
   SOPS_AGE_KEY_FILE=~/.config/sops/age/rave-prod.agekey \
     sops config/secrets.yaml
   ```
4. Keep the private key out of Git and store it in your secret manager. The repo already ignores `*.age`/`*.agekey`.

## Step 3 – Build the Image
You can use either the raw Nix build or the CLI wrapper.

### Option A: Nix Flake (supports profiles + port overrides)
Pick the profile that matches your use case:

| Profile | Command | When to use |
| --- | --- | --- |
| Production | `nix build .#rave-qcow2` | Full stack, all services enabled, larger resource footprint. |
| Dev-minimal | `nix build .#rave-qcow2-dev` | Faster local iteration (Outline + n8n disabled, smaller VM). |
| Custom port | `nix build .#rave-qcow2-port-9443` | Same as production but with a baked-in HTTPS port override. |

Each build drops a qcow2 under `result/`. Copy it to `artifacts/` (gitignored) with a meaningful name:
```bash
cp result/nixos.qcow2 artifacts/rave-${PROFILE}-$(date +%Y%m%d).qcow2
```

Prefer the CLI? Run `rave vm build-image --profile dev` (or omit `--profile` for production) so the images land alongside the usual stamped filenames.
Use `rave vm list-profiles` any time you need to see the current set of supported profiles/attributes.

### Option B: CLI helper
```bash
rave vm build-image --profile production
```
This wraps the same flake output and drops the qcow2 under `run/`.

## Step 4 – Launch & Verify
1. Start the VM (CLI preferred):
   ```bash
   rave vm launch-local \
     --image artifacts/rave-complete-YYYYMMDD.qcow2 \
     --https-port 18221 --ssh-port 2224
   ```
2. Wait for GitLab to finish first-boot migrations (≈5–7 minutes). Watch logs with:
   ```bash
   rave vm logs localhost gitlab --follow
   ```
3. Confirm core endpoints:
   - Dashboard: `https://localhost:18221/`
   - GitLab: `https://localhost:18221/gitlab/`
   - Mattermost: `https://localhost:18221/mattermost/`
   - Grafana: `https://localhost:18221/grafana/`
   - Prometheus: `https://localhost:18221/prometheus/`

4. SSH for deeper checks:
   ```bash
   ssh -p 2224 root@localhost
   systemctl status gitlab mattermost grafana nats prometheus
   ```

## Step 5 – Publish the Artifact
1. Stop the VM (`Ctrl+C` in launcher or `rave vm stop`).
2. Move the qcow2 into long-term storage (S3, GCS, release asset) and document the download URL.
3. Record the build metadata (flake revision, commit SHA, secret set) in `docs/refactor/notes.md` or a release note.
4. Run `scripts/repo/hygiene-check.sh` to ensure the artifact path remains untracked.

## Troubleshooting
| Symptom | Fix |
| --- | --- |
| `sops` fails during build | Confirm `SOPS_AGE_KEY_FILE` points to the private key and that the key contains the recipient listed in `config/secrets.yaml`. |
| GitLab stuck migrating | SSH in and inspect `journalctl -u gitlab.service -f`; verify the database password secret exists under `/run/secrets/gitlab/db-password`. |
| Ports already in use | Stop other VMs or override host ports via `rave vm launch-local --https-port 19xxx`. |
| Large qcow2 accidentally staged | Delete the staged file, add it to `artifacts/`, rerun the hygiene script, and recommit. |

## Related Docs
- `docs/tutorials/working-setup.md` – end-to-end walkthrough for local devs.
- `PRODUCTION-SECRETS-GUIDE.md` (legacy) – historical context on secret hardening.
- `COMPLETE-BUILD.md` (legacy) – architecture deep dive for the full VM.
