---
applyTo: "**/*.{sh,bash}"
---

# Script-specific Instructions

- Write scripts in clear, portable Bash unless the repository already uses a stricter shell convention.
- Keep scripts simple, linear, and easy to debug.
- Use English for variable names, comments, and log messages.
- Prefer explicit checks and readable branching over compact one-liners.
- Do not hide important behavior inside nested command substitutions or dense pipelines.

## Safety
- Avoid destructive behavior unless explicitly requested.
- Do not remove, reset, or overwrite persistent data implicitly.
- Treat mounted directories and save paths as critical.
- Fail loudly when required inputs or files are missing.

## Logging and troubleshooting
- Log the important execution steps in a concise way.
- Prefer logs that help an operator answer: what is starting, which config is used, where data is stored, and what failed.
- Error messages should be actionable, not generic.
- If adding retries or waiting logic, make it visible in logs.

## Script style
- Prefer small helper functions only when they improve readability.
- Avoid unnecessary abstraction, frameworks, or meta-scripting.
- Preserve existing entrypoint contract and argument behavior unless explicitly requested.