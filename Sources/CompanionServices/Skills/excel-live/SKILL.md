---
name: excel-live
description: Reads and edits the spreadsheet open right now in Excel or Numbers, and creates new .xlsx workbooks. Use when the user mentions a spreadsheet, workbook, Excel, Numbers or an .xlsx file.
license: Apache-2.0
metadata:
  author: companion
  version: "2"
---
# Spreadsheets

Companion talks to Excel and Numbers directly, on the sheet the user is looking at. Nothing to install.

## Steps

1. `sheet_read` the area first (A1 range, e.g. `A1:F30`). Never write into cells you have not read.
2. `sheet_write` one rectangle at a time: the `values` argument is JSON rows that match the range exactly. Formulas start with `=`; only plain functions over the sheet's own cells (no web fetches, external references or commands).
3. Every write asks the user once, keeps a version of the saved workbook in Companion's private store (nothing is created next to the file), and reads the cells back. Report what was written, and whether a previous version was kept; never invent a path for it.
4. A new workbook from scratch is `create_document` with a path ending in `.xlsx` (see premium-documents).

## When it answers with a code

- `no_open_document`: ask the user to open the workbook.
- `unsaved_document`: ask them to save it once, so Companion can identify the file and keep a version of it.
- `permission_required`: they turn on the spreadsheet app under Companion in System Settings > Privacy & Security > Automation.
- `invalid_args`: fix the range or the shape of `values` and try once more.

## What Companion cannot do yet

Pivot tables, conditional formatting and macros (macOS exposes none of them), Google Sheets, and any sheet other than the active one (in Numbers, its first table).
