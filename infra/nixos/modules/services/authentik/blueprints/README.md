This directory holds Authentik blueprint YAML files that are applied declaratively by
`authentik-apply-blueprints.service` after the core authentik services start.

Place one or more `*.yaml` (or `*.yml`) blueprints here to provision flows, providers,
and applications without manual clicks. Empty directories are ignored safely.
