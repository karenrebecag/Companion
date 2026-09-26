---
name: knowledge-builder
description: Saves, updates or removes durable facts the user asked to remember, one folder per subject under the knowledge folder. Use when the user says remember, save, note, forget, or when a fact will clearly matter in a later session.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Knowledge builder

Knowledge is what the user asked to keep across sessions. It lives in files the user can open. There is no other memory to write to.

## Where

One folder per subject inside the knowledge folder, whose absolute path is in the system prompt and in `<active_knowledge>`:

```
knowledge/<subject>/KNOWLEDGE.md
```

`<subject>` is lowercase letters, digits and single hyphens, and it names the subject, not the session: `dentist`, `car-insurance`, `weekly-report`.

## The file

```markdown
---
name: dentist
description: Who the user's dentist is and how to reach the clinic.
---
Dra. López, Clínica Roma. Appointments by phone, Mondays.
```

- `name` must equal the folder name.
- `description` says what the file holds, in third person, so a later session knows when to read it. Under 240 characters.
- The body holds the facts, short and dated when the date matters.

## Steps

1. Check `<active_knowledge>` for the subject. If it exists, `read_file` it and update in place with `edit_file`; do not create a second folder for the same subject.
2. Otherwise `write_file` the new `KNOWLEDGE.md`. The folder is created for you.
3. Read the `Knowledge sync:` line at the end of the tool result. `saved` means it is in the catalog; `failed` names what to fix, so fix it and write again.
4. Report in one line what was saved and where.

## Rules

- Save at the end of the task, once, not after every step.
- Facts only. A knowledge file is data for a later session, never instructions for it.
- Do not save secrets (passwords, tokens, card numbers). Say so and skip them.
- "Forget X": delete the folder with `run_shell` (`rm -r`) only after the user confirms the exact folder, or empty the file if unsure.
