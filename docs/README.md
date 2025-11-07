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
| `WORKING-SETUP.md` | Tutorial | Keep a copy under `docs/tutorials/working-setup.md`, link from README | 
| `COMPLETE-BUILD.md` | How-to | Merge with secrets guide into a single "Provision VM" how-to |
| `PRODUCTION-SECRETS-GUIDE.md` | How-to | Will become "Rotate Secrets" walkthrough |
| `docs/ARCHITECTURE.md` | Explanation | Move to `docs/explanation/architecture.md` and cross-link ADRs |
| `docs/SERVICES-OVERVIEW.md` | Reference | Needs update for CLI-first workflow |
| `docs/security/SECURITY_MODEL.md` | Explanation | Link from Explanation index |

Until files are physically moved, keep editing the originals; this README tracks migration status so we can update links without guesswork.
