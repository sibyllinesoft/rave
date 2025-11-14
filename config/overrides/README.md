# RAVE Override Layers

This directory contains Git-tracked override layers that can be projected into live RAVE-managed hosts via the CLI. Each layer mirrors the target filesystem tree so contributors can edit configs naturally and ship them with commits.

```
config/
  overrides/
    global/
      layer.json        # Layer metadata (name, priority, directories)
      metadata.json     # Pattern-based ownership + restart hints
      files/            # Files copied verbatim to / on the host
      systemd/          # Entire unit files -> /etc/systemd/system
```

Start by editing the `global` layer (it already contains a sample nginx snippet and
systemd unit under `files/` and `systemd/`). Run `rave overrides apply --company <name>`
to sync the changes into a VM, or `rave overrides apply --dry-run --company <name>` to
preview what would change. The dry-run automatically executes `nix flake check` unless you
pass `--skip-nix-check`, ensuring you don't stream a broken config.

When you need host- or app-specific layers, let the CLI scaffold them via
`rave overrides create-layer <name> --priority 50 --preset nginx` rather than building the
tree by hand—each layer gets its own `layer.json`, `metadata.json`, and mirror directories.
Presets (`nginx`, `gitlab`, `mattermost`, `pomerium`) append common restart/reload patterns so
operators don't have to duplicate metadata. Add `--preflight-cmd "nixos-rebuild test --flake .#{company}"`
to `rave overrides apply --dry-run` when you want to run host-specific checks before the remote preview.

## Provided layers

- `global` – default shadow filesystem for all hosts (sample nginx + systemd snippets).
- `benthos` – webhook normalization + NATS bridge (see `docs/overrides/benthos-webhook-bridge.md`).
- Mattermost integration guidance lives in `docs/overrides/mattermost-benthos-webhooks.md`; it
  walks through creating outgoing hooks that publish into Benthos so everything lands in
  the same pipeline as GitLab/Outline events.
