#!/usr/bin/env bash
# Report tracked artifacts that should stay out of Git history.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Allow override via environment variable (default 50 MiB)
THRESHOLD_BYTES="${HYG_CHECK_THRESHOLD:-52428800}"

info() { printf "[hygiene] %s\n" "$*"; }
warn() { printf "[hygiene][WARN] %s\n" "$*"; }

info "Scanning tracked files >= $((THRESHOLD_BYTES / 1024 / 1024)) MiB"
large_found=0
while IFS= read -r -d '' file; do
  if [[ ! -f "$file" ]]; then
    continue
  fi
  size=$(stat -c '%s' "$file")
  if (( size >= THRESHOLD_BYTES )); then
    warn "Large file tracked: $file ($(numfmt --to=iec "$size"))"
    large_found=1
  fi
done < <(git ls-files -z)

if (( large_found == 0 )); then
  info "No tracked files exceed threshold"
fi

info "Checking for tracked VM/container artifacts"
tracked_patterns=("*.qcow2" "*.vdi" "*.vmdk" "*.iso" "gitlab-complete/**" "postgres/**" "redis/**" "run/**")
pattern_hits=0
for pattern in "${tracked_patterns[@]}"; do
  if git ls-files -- "$pattern" >/dev/null; then
    while read -r hit; do
      warn "Tracked artifact pattern '$pattern': $hit"
      pattern_hits=1
    done < <(git ls-files -- "$pattern")
  fi
done
if (( pattern_hits == 0 )); then
  info "No tracked VM/container artifacts detected"
fi

info "Listing untracked directories not covered by .gitignore"
untracked=$(git ls-files --others --directory --exclude-standard)
if [[ -n "$untracked" ]]; then
  warn "Untracked directories:\n$untracked"
else
  info "No unexpected untracked directories"
fi

info "Hygiene check complete"
