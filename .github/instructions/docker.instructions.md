---
applyTo: "**/{Dockerfile,docker-compose*.yml,docker-compose*.yaml,compose*.yml,compose*.yaml,.env.example}"
---

# Docker-specific Instructions

- Preserve current runtime behavior unless a change is explicitly requested.
- Do not change exposed ports, protocol choices, container names, volume targets, or restart behavior without a clear reason.
- Prefer explicit environment variables over hardcoded values.
- Keep Compose files easy to read and easy to override.
- Avoid unnecessary services, wrappers, sidecars, or templating layers.
- Favor deterministic container startup over aggressive automation.

## Volumes and persistence
- Treat all mounted paths as persistence-sensitive.
- Do not rename, relocate, or repurpose existing volume targets unless explicitly requested.
- Assume save data compatibility matters more than cleanup aesthetics.
- If a mount change is necessary, mention migration impact clearly.

## Image and startup behavior
- Prefer transparent entrypoint behavior over hidden logic.
- Do not add fragile sleeps or timing-based startup unless there is no safer option.
- If startup logic changes, keep logs clear and operator-friendly.
- Any behavior affecting updates or first-run setup should be documented in README.

## Validation mindset
- Prefer changes that are easy to inspect from `docker compose config`, container logs, and mounted files.
- Avoid patterns that make troubleshooting harder for operators.