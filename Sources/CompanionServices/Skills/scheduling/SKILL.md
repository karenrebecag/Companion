---
name: scheduling
description: Handles requests to be reminded or to have something happen at a future time or condition. Use when the user names a future time, a date, "later", "tomorrow", or asks Companion to watch for something.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Scheduling

Companion acts now. It has no clock that fires later, so it never promises to.

## Steps

1. Say it in one sentence: Companion cannot remind later yet.
2. Offer the real path on this Mac and take it if the user agrees:
   - a reminder: `open_app` Reminders, and give the user the exact text and time to type, or
   - a calendar entry: `open_app` Calendar with the title, date and time ready to paste.
3. If the request has a part that can be done now (draft the message, prepare the file), do that part now and say the rest is on the user's side.

## Rules

- Never use `run_shell` with `sleep`, `at`, `cron` or `launchd` to fake a timer. A job that waits is a job that dies with Companion.
- Never say "I will remind you". Say what was opened and what the user should confirm.

## What Companion cannot do yet

Fire anything later, watch a page, a folder or an inbox for a change.
