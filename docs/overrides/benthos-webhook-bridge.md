# Benthos Webhook Bridge Layer

The `benthos` override layer ships a ready-to-run Benthos pipeline that exposes
`/hooks/{source}` over HTTP, normalizes incoming JSON/YAML payloads, and forwards
 them into NATS/JetStream under `webhooks.<source>` subjects. Use it to aggregate
external webhooks (GitHub, Stripe, etc.) without rebuilding the base VM image.

## Contents

```
config/overrides/benthos/
  files/etc/benthos/pipelines/webhook-router.yaml   # Benthos config (HTTP server + NATS)
  systemd/benthos-webhook-bridge.service            # Systemd unit referencing the config
```

## Usage

1. Customize the Bloblang section inside `webhook-router.yaml` if you need additional
   normalization, auth checks, or subject routing logic (defaults route to `webhooks.<source>`
   and POST the normalized JSON to `http://127.0.0.1:5678/webhook/benthos` for n8n).
2. Create an n8n workflow with a Webhook node using the path `benthos` (production URL
   `https://localhost:8443/n8n/webhook/benthos`). Benthos will deliver every message there in
   addition to NATS/JetStream.
3. Apply the layer: `rave overrides apply --company <vm> --layer benthos` (or `--dry-run` first).
4. Enable the unit on the VM if needed: `systemctl enable --now benthos-webhook-bridge`.

### Security & Auth
- Place shared-secret validation in the Bloblang processor (e.g., compare
  `meta("http_header:X-Hub-Signature")`).
- To expose the listener publicly, pair with a reverse proxy route that enforces
  TLS and origin filtering (nginx location block under the same layer works well).
- GitLab is pre-wired (via `gitlab-benthos-webhook.service`) to send system hooks to
  `http://127.0.0.1:4195/hooks/gitlab`, so the listener only needs to be reachable
  locally unless you plan to ingest third-party hooks.

### Extending
- Duplicate the layer or add additional Benthos configs (one per service) by
  copying the YAML/env files and creating extra systemd units. Update
  `metadata.json` to restart the right units.
- Use `nats://nats.jetstream.svc:4222` URLs plus JetStream options to land
  normalized events into a dedicated stream for replay/analytics.
