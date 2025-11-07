# RAVE Documentation Hub

RAVE now follows the Divio documentation model so contributors and AI agents can quickly find the right source of truth.

## Taxonomy
| Category | Purpose | Directory |
| --- | --- | --- |
| Tutorials | Step-by-step introductions for new operators | `docs/tutorials/`
| How-to guides | Task oriented playbooks | `docs/how-to/`
| Reference | API/CLI/configuration reference material | `docs/reference/`
| Explanation | Architecture, ADRs, deep dives | `docs/explanation/`

## Migration Queue (2025-11-07)
| Existing File | Target Category | Notes |
| --- | --- | --- |
| `WORKING-SETUP.md` | Tutorial | ✅ Moved to `docs/tutorials/working-setup.md` (root file is now a pointer) |
| `COMPLETE-BUILD.md` | Explanation/How-to | Mostly covered by `docs/how-to/provision-complete-vm.md`; keep for deep-dive context until trimmed |
| `PRODUCTION-SECRETS-GUIDE.md` | How-to | Superseded by the provisioning guide; carve out a future \"Rotate Secrets\" doc |
| `docs/ARCHITECTURE.md` | Explanation | Move to `docs/explanation/architecture.md` and cross-link ADRs |
| `docs/SERVICES-OVERVIEW.md` | Reference | Needs update for CLI-first workflow |
| `docs/security/SECURITY_MODEL.md` | Explanation | Link from Explanation index |

Until files are physically moved, keep editing the originals; this README tracks migration status so we can update links without guesswork.

## Published Guides
- **Tutorial:** `docs/tutorials/working-setup.md` — walkthrough for launching the dev VM locally.
- **How-to:** `docs/how-to/repo-hygiene.md` — run the hygiene script before committing to keep artifacts out of Git.
- **How-to:** `docs/how-to/provision-complete-vm.md` — single source of truth for building, launching, and publishing qcow2 images with SOPS secrets.
