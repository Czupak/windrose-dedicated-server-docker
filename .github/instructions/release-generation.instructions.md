When writing GitHub release notes for a tag:
- Use this exact wrapper format:
	- TOP: <release title>
	- DESCRIPTION: <release body in markdown>
- Write in English.
- Use a playful pirate tone, but keep it readable and professional.
- Start with the release name and version.
- Add a short one-sentence summary.
- Use sections like Changes, Notes, Captain's note, and Upgrade.
- Keep technical facts accurate and concrete.
- Add light pirate flavor only to headings, transitions, and short commentary.
- Do not affect code, identifiers, commands, or environment variables.
- Keep the release note short enough to scan quickly.
- Description starts with "##⚓ Windrose Dedicated Server Docker" and the version number

Before creating or publishing a new tag:
- Update `IMAGE_TAG` in `.env.example` to the new version.
- Update all stable tag references in `README.md` to the new version (quick start image example, `IMAGE_TAG` default value in config table, `IMAGE_TAG` in the quick start code block, update/stable guidance lines).
- Commit and push these documentation changes to `main` before pushing the tag.