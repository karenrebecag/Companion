---
name: premium-documents
description: Produces a finished PDF report, one-pager or receipt, or an .xlsx workbook, for the user to open. Use when the user asks for a document, a report, a one-pager, a PDF, or a table they can take away.
license: Apache-2.0
metadata:
  author: companion
  version: "2"
---
# Documents

Always deliver a file the user can open. `create_document` writes it natively: no pandoc, no Python, nothing to install.

## Steps

1. Ask nothing that a sensible default answers. Title from the request, today's date, the user's name from the profile.
2. Gather the facts first (files, the web, what the user pasted). Only figures you looked up or were given go in; never invent a number to fill a chart.
3. Call `create_document` with a path ending in `.pdf` (a report to read) or `.xlsx` (tables to work with), in the working folder. The `document` argument is JSON text: `{"title","subtitle","blocks":[...]}`.
4. Build it from blocks, never from HTML or styling; the template owns the look:
   - `cover` for a report with a first page; skip it for a one-pager.
   - `stats` for the three to six figures that matter, with `delta` when there is a change.
   - `table` for anything repeated; `chart` when the shape of the numbers is the point (`bar` to compare, `line` or `area` over time, `pie`/`donut` for parts of a whole).
   - `heading`, `paragraph`, `bullets` for the argument; `callout` for the one thing not to miss.
5. The tool checks the file on disk before answering. Report the absolute path and the page count it returns.

## Writing rules

- Lead with the summary; the voice reads only the first line.
- Numbers in tables and stats, not in prose.
- Sources at the end when the web was used.
- For an .xlsx, every stats, table and chart block becomes its own sheet; name them with `title`.

## What Companion cannot do yet

Word (.docx) and PowerPoint (.pptx) files, editing an existing PDF, and pictures inside the document. If the user needs Word, offer the PDF, or Markdown with `write_file`.
