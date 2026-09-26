---
name: premium-documents
description: Produces a document, report, deck or PDF on disk for the user to open, in the best format the tools on this Mac allow. Use when the user asks for a document, a report, slides, a one-pager or a PDF.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Documents and decks

Always deliver a file the user can open. The format follows what the Mac has.

## Steps

1. Ask nothing that a sensible default answers. Title from the request, today's date, the user's name from the profile.
2. Write the content first as Markdown with `write_file` into the working folder (or Desktop when none is set): headings, short paragraphs, tables for repeated data. This file is always delivered.
3. Convert only if the tool is present, checked with `run_shell`:
   - PDF or Word: `pandoc --version` then `pandoc file.md -o file.pdf` (or `.docx`).
   - Slides: `pandoc file.md -o file.pptx` with one `##` per slide.
   - Otherwise: leave the Markdown, say which tool would convert it, and do not install anything.
4. Verify the file exists with `list_directory` before reporting. Report the absolute path.

## Writing rules

- Lead with the summary; the voice reads only the first line.
- Numbers in tables, not in prose.
- Sources at the end when the web was used.

## What Companion cannot do yet

Layouts, themes, charts or images inside the document without pandoc or a Python toolchain installed on this Mac.
