---
name: meeting-transcripts
description: Summarises a meeting from a transcript file already on this Mac, pulls decisions, owners and dates, and drafts the follow-up. Use when the user mentions a transcript, minutes, meeting notes or a recording that was transcribed.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Meeting transcripts

Companion does not record meetings. It works from a transcript the user already has: `.txt`, `.md`, `.vtt`, `.srt` or a document exported by the meeting tool.

## Steps

1. Find the file. If the user named it loosely, `list_directory` the likely folder (Downloads, Desktop, Documents) and pick the one whose name and date match; ask if two match.
2. `read_file` the whole transcript. Do not summarise from the first screen.
3. Extract, with the speaker's words as evidence:
   - decisions (what was agreed),
   - actions (who does what by when),
   - open questions,
   - anything the user was asked for personally.
4. Write the summary for a screen: a one-line headline, then the four lists, each item ending with the timestamp or the speaker it comes from.
5. If asked for a follow-up message, use the writing-content skill and only include what the transcript supports.

## Rules

- Never attribute a decision to someone who did not say it in the transcript.
- Names in the transcript may be misspelled by the transcriber; keep the transcript's spelling and say so once.
- Long transcript: summarise per section, then merge; do not skip the end.
