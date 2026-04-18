---
applyTo: "**/{README.md,README*.md,*.md}"
---

# Documentation-specific Instructions

- Write documentation in English unless the user explicitly asks for another language.
- Keep documentation practical, direct, and operator-focused.
- Prefer short sections, bullet lists, tables, and concrete examples.
- Avoid marketing language, filler, and vague claims.

## Documentation structure
- Prefer this order when relevant: overview, quick start, configuration, persistence, updates, troubleshooting.
- Document defaults explicitly.
- Document every environment variable, port, volume, and important path.
- When behavior changes, update docs in the same change.

## Troubleshooting
- Include likely failure cases and simple recovery steps.
- Prefer copy-paste-ready commands where useful.
- State assumptions clearly, especially around Docker, Wine, permissions, networking, and persistence.
- If something is experimental or version-sensitive, say so directly.