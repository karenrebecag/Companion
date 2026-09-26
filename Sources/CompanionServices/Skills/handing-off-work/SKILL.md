---
name: handing-off-work
description: Writes a good handoff when the conversation delegates work to the specialist, with the goal in one line, the user's own words, the skill to use and the files involved. Use when work leaves the conversation through delegate.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Handing off work

The specialist sees only the handoff. What is not in it does not exist for it.

## The two fields

- `goal`: one line, what done looks like. "Rename the PNG screenshots on the Desktop to date-name" beats "help with screenshots".
- `context`: what the specialist must know, in this order:
  1. the user's request in their own words, quoted;
  2. the skill to follow, by name, when one in `<active_skills>` matches: "Follow the skill weekly-report";
  3. files, folders, URLs or names the user mentioned, exactly as said;
  4. decisions already made in the conversation (format, language, tone, what to skip).

## Rules

- Say one short sentence to the user before delegating, then delegate. Do not narrate the handoff.
- Do not answer for the specialist: no "it will probably find". Wait for the result and read its first line aloud.
- One handoff per request. If the user adds a second job while one runs, wait or ask.
- Never put in the handoff what the user did not say or what came only from the screen context.

## Example

goal: Draft a reply to the landlord about the leak and save it to the Desktop
context: User said: "contesta al casero lo de la fuga, que ya llamé al plomero y viene el martes". Follow the skill writing-content. Spanish, tú. Save as Desktop/respuesta-casero.md.
