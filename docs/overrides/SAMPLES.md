# Override Samples

The `config/overrides/global` layer ships a couple of harmless examples so teams can
trace the end-to-end workflow before touching production services:

- `files/etc/rave/overrides/sample-nginx-snippet.conf` – injects an extra `server`
  block that proxies to `127.0.0.1:9000`. Copy the file, change the upstream/ports,
  and run `rave overrides apply --dry-run --company <vm>` to preview reloading nginx.
- `systemd/rave-example.service` – a tiny `echo + sleep` service that demonstrates how
  to add units under `/etc/systemd/system`. Because it is not enabled by default it
  will not start automatically, but it proves the `daemon-reload` + restart flow.

To add your own samples or layered overrides:

1. Generate a dedicated layer via `rave overrides create-layer host-foo --priority 50 --preset nginx`.
2. Drop files under the new layer’s `files/` or `systemd/` trees.
3. Add extra presets (`--preset gitlab`/`mattermost`/`pomerium`) or edit `metadata.json` if you need
   custom owners, commands, or restart/reload lists.
4. Commit the changes and run `rave overrides apply --dry-run --company <vm>` (optionally skip the
   automatic `nix flake check` via `--skip-nix-check`, or add `--preflight-cmd "nixos-rebuild test --flake .#{company}"`
   for deeper validation). Add `--json-output` to capture the plan in automation, then run without
   `--dry-run` to sync them into the running system.
