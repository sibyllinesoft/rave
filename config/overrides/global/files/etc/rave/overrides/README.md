This directory ships sample override payloads. Copy the snippets you need into
`config/overrides/<layer>/files/…` and edit them, or replace the files entirely.

Examples:
- `sample-nginx-snippet.conf` demonstrates adding an extra nginx `server` block.
- Drop application-specific configs under `/etc/rave/overrides/<app>/` so they stay
  isolated from upstream-managed files.
