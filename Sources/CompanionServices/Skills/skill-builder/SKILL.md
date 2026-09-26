---
name: skill-builder
description: Creates or improves a custom skill in the Agent Skills format. Use when the user asks to teach Companion a repeatable procedure, or after a job when something reusable was learned and the user agrees to keep it.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Skill builder

A skill is a folder with a `SKILL.md`: instructions a later session reads when its description matches the task. Companion follows the Agent Skills format.

## Where

```
skills/custom/<name>/SKILL.md      the instructions (required)
skills/custom/<name>/references/   optional, files the skill points to
skills/custom/<name>/NOTES.md      optional, technical details kept out of SKILL.md
```

The absolute path of the skills folder is in `<active_skills>`. `skills/default/` is Companion's and is read-only: a write there is refused with `denied_path`. Improve a default skill by writing a custom one with a different name.

## The file

```markdown
---
name: weekly-report
description: Builds the weekly status report from the team's notes. Use when the user asks for the weekly report or says "Friday report".
---
# Weekly report

## Steps
1. ...
```

- `name`: 1 to 64 characters, lowercase letters, digits and single hyphens; equal to the folder name; not containing "anthropic" or "claude".
- `description`: third person, what it does and when to use it, with the words the user actually says. Under 240 characters so it fits the catalog whole.
- Body: steps, an example of input and output, the edge cases. Under 120 lines. Move long reference material to `references/`, linked one level deep.

## Steps

1. Ask the user for the name if it is not obvious. Check `<active_skills>` so it does not collide.
2. Write the procedure the way the user does it, in their words, with the tools Companion has (`read_file`, `write_file`, `edit_file`, `list_directory`, `run_shell`, `web_fetch`, `web_search`).
3. Per-user facts (names, emails, paths) go to a knowledge entry (knowledge-builder skill), and the skill links it: `[knowledge: <subject>]`.
4. `write_file` the `SKILL.md`. Read the `Skill sync:` line at the end of the result: `saved` means it is in the catalog next turn; `failed` names what to fix.
5. Tell the user the name and that it is available from the next request.

## Rules

- Do not put scripts in the skill yet: `scripts/` is not executed by Companion.
- Do not write secrets into a skill.
- One skill, one job. Two procedures are two skills.
