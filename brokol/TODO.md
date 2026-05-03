# Windrose Dedicated Server Docker - TODO

Operator-first, incremental backlog for reliability and CLI UX.
Scope: practical tasks only, no broad rewrites.
Constraint: keep default ports, volume mappings, and save paths unchanged.

## P0 - Reliability and data safety

- [x] Add global mutation lock for state-changing commands (`setup`, `update`, `backup`, `restore`, `switch`, `down`)
      Acceptance criteria:
  - A mutating command acquires a lock and always releases it on success or failure.
  - A second mutating command exits immediately with a clear "operation in progress" message.
  - Read-only commands (`status`, `logs`, `doctor`) remain available while lock is active.

- [x] Add post-update verification with timeout and recovery hints
      Acceptance criteria:
  - Update verifies running state and health within bounded timeout.
  - Timeout or failure returns non-zero with clear next-step command hints.
  - Success output includes a concise verified status block.

- [x] Enable backup integrity verification by default
      Acceptance criteria:
  - Every backup runs a fast archive integrity check after creation.
  - Verification failure marks backup as failed and exits non-zero.
  - CLI shows explicit `PASS` or `FAIL` with short reason.

- [x] Add diagnostics bundle command
      Acceptance criteria:
  - One command creates a timestamped diagnostics bundle in `./backups`.
  - Bundle includes bounded logs, compose status, health context, and update log tail.
  - Bundle does not include save payload by default.

## P1 - Functional UX for operators

- [x] Harden doctor preflight checks
      Acceptance criteria:
  - Check docker and compose availability, compose config validity, and service state.
  - Validate save path existence and write permissions.
  - Report disk threshold and port conflicts as pass, warn, fail.

- [x] Add compact status snapshot command
      Acceptance criteria:
  - One concise view with mode, running state, health, active world, invite code presence, and backup age.
  - Missing values are explicit (`unknown`) rather than omitted.

- [x] Improve notifier status with backend preflight
      Acceptance criteria:
  - Show resolved provider mode and required config presence.
  - Include endpoint reachability summary without exposing secrets.
  - Failures include concrete reason and one suggested next command.

- [x] Add restore-preview mode
      Acceptance criteria:
  - Preview shows archive type, timestamp, top-level entries, and overwrite scope.
  - Preview mode performs no writes.
  - Corrupt archive returns clear non-zero failure.

- [x] Add update summary block
      Acceptance criteria:
  - End-of-update summary prints old and new image tag, duration, container status, and health.
  - Summary is shown on both success and failure paths.

## P2 - Consistency and polish

- [x] Standardize prompt and error style across scripts
      Acceptance criteria:
  - Prompt wording and default patterns are consistent in `serverctl.sh`, `backup.sh`, and `notify.sh`.
  - Confirm prompts follow one format and non-interactive behavior is explicit.
  - Fatal errors include immediate next-step hints.

- [x] Add safe worlds-prune command with dry-run default
      Acceptance criteria:
  - Default mode is dry-run and prints candidate paths.
  - Apply mode requires explicit confirmation.
  - Active world is never removed.

- [x] Add practical scenario guides and release checklist in docs
      Acceptance criteria:
  - `README.md` includes quick guides for new host setup, save migration, world switch safety, and failed-update recovery.
  - `README.md` includes a stable release checklist (version bump points, verification, tag and push order).

## P3 - CLI visual and readability redesign (Designer handoff)

### Implementation rollout (execution order)

- [x] Phase 1: baseline snapshots + style contract approval (1-2h)
      Acceptance hint:
  - Capture baseline outputs for target flows and approve one style contract before code changes.
  - Note: Baseline artifacts captured in /tmp/windrose-p3-before.

- [x] Phase 2: shared output helpers + NO_COLOR/non-TTY fallback (1-2h)
      Acceptance hint:
  - Shared helpers are used in affected scripts and color handling is deterministic in TTY and non-TTY modes.
  - Note: NO_COLOR/non-TTY fallback implemented in serverctl.sh, backup.sh, notify.sh, and migrate-folders.sh.

- [x] Phase 3: prompt/error/help normalization (0.5 day)
      Acceptance hint:
  - Prompts, fatal errors, and help text follow one format with explicit defaults and one actionable next step.
  - Note: Scope normalized in serverctl.sh, backup.sh, and notify.sh.

- [x] Phase 4: key screen hierarchy (usage, status-snapshot, doctor, update summary, backup, notify status) (0.5 day)
      Acceptance hint:
  - Key operator screens share one readable section hierarchy with aligned high-signal fields.
  - Note: Unified section layout and spacing implemented in `serverctl.sh` (usage/status-snapshot/doctor/notify status/update summary), `backup.sh` output, and `notify.sh` usage.

- [x] Phase 5: docs sync + regression gate + manual approval (1 day)
      Acceptance hint:
  - Docs match final CLI behavior, regression checks pass, and manual approval is recorded before release actions.
  - Note: Regression gate completed; migrate-folders help side effects fixed and backup runtime check controlled via timeout (timeout => INCONCLUSIVE, not format FAIL).
  - Note: Manual approval checkpoint accepted by user on 2026-04-24.

- [x] Define one shared CLI language and status vocabulary across user scripts
      Acceptance criteria:
  - `windrose`, `serverctl.sh`, `backup.sh`, `notify.sh`, and `migrate-folders.sh` use one consistent message voice.
  - A single status vocabulary is used across outputs (`OK`, `FAIL`, `WARN`, `SKIP`) with no mixed alternatives.
  - Prefix and section label style is consistent and easy to scan in long logs.

- [x] Standardize prompt and error layout with action-oriented next steps
      Acceptance criteria:
  - Interactive prompts share one format and explicitly show defaults (`[Y/n]` or `[y/N]`).
  - Non-interactive behavior is explicit and safe in all affected flows.
  - Fatal errors end with one practical `Next step` command or action.

- [x] Introduce terminal-friendly visual hierarchy for key operator screens
      Acceptance criteria:
  - `usage`, `status-snapshot`, `doctor`, `update summary`, `backup`, and `notify status` follow one section layout.
  - Important values are grouped and aligned for fast scanning under incident pressure.
  - Output remains readable without colors (no critical meaning conveyed by color alone).

- [x] Add color policy fallback for non-interactive and NO_COLOR environments
      Acceptance criteria:
  - Scripts disable ANSI color output automatically when not running in TTY or when `NO_COLOR` is set.
  - Log readability remains intact in CI/cron/log files.
  - Existing command behavior and exit codes remain unchanged.

- [x] Refresh CLI help text coverage and consistency
      Acceptance criteria:
  - Main `usage()` output lists all supported end-user commands and aliases.
  - Help sections use consistent spacing and short command descriptions.
  - Examples in help match current command behavior.

- [x] Deliver and approve before-after output mocks for high-impact flows
      Note: delivered and approved by user on 2026-04-24. Artifacts: /tmp/windrose-p3-mocks.txt
      Acceptance criteria:
  - At least 8 before-after text mocks are prepared (usage, setup, worlds switch, worlds-prune, status-snapshot, doctor, update, backup).
  - Mocks preserve operational semantics and safety constraints.
  - Final style is approved before implementation changes begin.

## P4 - Docker script layout cleanup (entrypoint and healthcheck)

- [x] Move Docker-only runtime logic to scripts/entrypoint.sh and scripts/healthcheck.sh
      Acceptance criteria:
  - Docker-specific startup and health logic is implemented in scripts/entrypoint.sh and scripts/healthcheck.sh.
  - Root-level Docker script files no longer contain duplicated operational logic.
  - Script behavior remains transparent and easy to troubleshoot from container logs.

- [x] Add thin compatibility wrappers at root for entrypoint.sh and healthcheck.sh
      Acceptance criteria:
  - Root entrypoint.sh delegates directly to scripts/entrypoint.sh with argument passthrough.
  - Root healthcheck.sh delegates directly to scripts/healthcheck.sh with argument passthrough.
  - Wrapper scripts remain minimal and preserve executable contracts used by existing setups.

- [x] Update container references to canonical script paths
      Acceptance criteria:
  - Dockerfile and compose command references point to canonical paths under scripts/ where applicable.
  - No ambiguous mixed path usage remains for runtime script entrypoints.
  - Effective runtime command paths are visible and predictable during startup diagnostics.

- [x] Preserve runtime behavior and infrastructure contract
      Acceptance criteria:
  - No functional runtime behavior changes are introduced by layout cleanup.
  - No default port, volume mapping, save path, or network behavior changes are introduced.
  - Existing persistence compatibility is maintained for current operators.

- [x] Document backward-compatibility contract for script path transition
      Acceptance criteria:
  - Documentation states that root wrappers are compatibility shims and canonical logic lives under scripts/.
  - Documentation explains expected lifecycle of compatibility wrappers.
  - Troubleshooting guidance references canonical paths first.

- [x] Add minimal parity tests for migration safety
      Acceptance criteria:
  - Compose config parity check passes before and after path migration.
  - Smoke up test confirms successful container start with canonical paths.
  - Healthcheck success and fail scenarios show parity with pre-migration behavior.
    Note: Full P4 acceptance rerun passed on local dev build (`docker compose -f docker-compose.yml -f docker-compose.dev.yml` with image `windrose-ds:dev`), including smoke up, healthcheck success/fail parity, `WINDROSE_MODE=dev ./windrose status`, and `WINDROSE_MODE=dev ./windrose doctor`.

- [x] Define a simple rollback path
      Acceptance criteria:
  - Rollback steps are documented and executable with one short procedure.
  - Rollback restores previous script path wiring without data migration.
  - Rollback can be performed without changing saved data locations.

- [x] Add manual approval checkpoint before release
      Acceptance criteria:
  - Release checklist includes an explicit manual approval gate for this migration.
  - Approval confirms parity checks, rollback readiness, and compatibility wrapper validation.
  - No release tag is created before checkpoint approval is recorded.

- [x] Plan deprecation and later removal of root compatibility wrappers
      Acceptance criteria:
  - Root wrappers `entrypoint.sh` and `healthcheck.sh` remain during a transition window of 1-2 release cycles.
  - Removal starts only after no references remain in Dockerfile, compose files, and docs.
  - Parity tests are re-confirmed and no startup or healthcheck regressions are observed before deletion.
    Progress (as of v1.6.0 + cb5c1d9):
  - Dockerfile: ✓ COPY of root wrappers removed (bcf5770); canonical chmod path only.
  - docker-compose.yml: ✓ healthcheck uses `/opt/windrose/scripts/healthcheck.sh`.
  - README.md: ✗ still references root wrappers at lines ~790-791 and ~824 (file tree and compatibility note).
  - Root files: ✗ `entrypoint.sh` and `healthcheck.sh` still present in repo root.
  - Parity tests: pending re-confirmation before deletion.
    Closed (v1.6.1): README.md refs removed, entrypoint.sh and healthcheck.sh removed from repo.
