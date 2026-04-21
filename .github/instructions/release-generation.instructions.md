When writing GitHub release notes for a tag:
- Provide output in two separate markdown code blocks:
	- First block: release title only.
	- Second block: release body only.
- Do not include literal labels like "TOP:" or "DESCRIPTION:" in the output.
- TOP title style must be: `vX.Y.Z — Short headline` (example: `v1.2.3 — Safer waters ahead`).
- The title may be playful and funny in pirate style, as long as it stays clear and readable.
- Keep both blocks copy-paste friendly.
- Output exactly two fenced markdown code blocks, with no extra text before, between, or after them.
- Write in English.
- Use a playful pirate tone, but keep it readable and professional.
- Start with the release name and version.
- Add a short one-sentence summary.
- Use sections like Changes, Notes, Captain's note, and Upgrade.
- Keep technical facts accurate and concrete.
- Add light pirate flavor only to headings, transitions, and short commentary.
- Do not affect code, identifiers, commands, or environment variables.
- Keep the release note short enough to scan quickly.
- Description starts with "## ⚓ Windrose Dedicated Server Docker" and the version number

Before creating or publishing a new tag:
- Update `IMAGE_TAG` in `.env.example` to the new version.
- Update all stable tag references in `README.md` to the new version (quick start image example, `IMAGE_TAG` default value in config table, `IMAGE_TAG` in the quick start code block, update/stable guidance lines).
- Validate that old stable version references are gone from `.env.example` and `README.md`.
- Commit and push these documentation changes to `main` first.
- Only then create and push the release tag.
- If a tag was created too early, move it to the latest `main` commit before publishing release notes.