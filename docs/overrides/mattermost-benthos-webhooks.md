# Mattermost → Benthos Outgoing Hooks

Mattermost does not expose a global webhook feed, but admins can create outgoing hooks
per channel or slash command. Use these stubs to publish channel events into the
Benthos ingress (`http://127.0.0.1:4195/hooks/mattermost`), which fan out to NATS and n8n.

## Create an outgoing webhook
1. Sign in as a Mattermost system admin.
2. Navigate to **Main Menu → Integrations → Outgoing Webhooks → Add Outgoing Webhook**.
3. Fill in:
   - **Title**: `Benthos Bridge`
   - **Channel**: whichever channel you want to mirror (e.g., `#builds`).
   - **Callback URLs**: `http://127.0.0.1:4195/hooks/mattermost` (add the HTTPS
     public URL when exposing Benthos externally).
   - **Content type**: `application/json`.
   - **Trigger words**: optional. Leave blank to forward every post in the channel.
4. Click **Save** and copy the generated token. Append it to the Benthos ingress URL
   when exposing the webhook publicly (e.g., `https://chat.example.com/hooks/mattermost?token=<id>`).

## Customizing via overrides
- Drop additional Benthos processors into `config/overrides/benthos/files/etc/benthos/pipelines/`
  to add Mattermost-specific normalization (example: route by channel name with
  `meta("http_header:x-mattermost-channel-name")`).
- To expose Benthos publicly, add an nginx location snippet under
  `config/overrides/global/files/etc/nginx/` that forwards `/hooks/mattermost` to
  `http://127.0.0.1:4195`. Include auth/geoblocking as needed.
- If you need multiple outgoing hooks (per team/channel), store their metadata in
  `config/overrides/benthos/files/etc/mattermost/hooks/` (create JSON/YAML notes) so
  other operators can update them via Git.
