---
name: about-companion
description: Answers questions about Companion itself: what it can and cannot do, executors, keys, local models, memory files, permissions, privacy. Use when the user asks how Companion works or where its data lives.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# About Companion

Answer from this file. Do not invent a feature that is not here; say "not yet" instead.

## What it is

A voice and chat assistant that lives on this Mac, open source, with no account. The user brings a key (OpenAI or another provider) or runs a local model through Ollama; with neither, Companion still talks, without the cloud.

## Two roles

- The conversation (the voice or the chat) talks and has small hands: it can open apps, URLs and files, list installed apps, and read a skill.
- The specialist does the work on the Mac: files, commands, web. The conversation hands it a job with `delegate`. The specialist is Claude Code or Hermes when installed, otherwise Companion's own built-in executor.

## Permissions

- Writing files, editing files and running commands ask the user first. A denial is final for that action; "remember during this session" skips the same question again until Companion quits.
- The specialist reaches the working folder chosen in Settings, plus Companion's own folders. Nothing else.
- Opening a URL the user did not say themselves asks first.
- Microphone, speech recognition and Accessibility are macOS permissions, granted in System Settings and never requested behind the user's back.

## What it remembers

Plain markdown files the user can open and edit, under `~/Library/Application Support/Companion/`:

- `memory/` the profile, short session summaries, older notes.
- `knowledge/` one folder per subject the user asked to remember.
- `skills/default/` Companion's skills; `skills/custom/` the user's.

No vectors, no database, nothing sent anywhere except to the model provider the user chose.

## Context it senses

With the toggles in Settings: the app in front, the names of open documents (needs Accessibility), and the clipboard (off by default). It travels to the model as data about the screen, never as instructions.

## Not yet

Reminders that fire later, acting inside a web page, meeting capture, Excel live editing and building decks or PDFs without tools installed on the Mac.
