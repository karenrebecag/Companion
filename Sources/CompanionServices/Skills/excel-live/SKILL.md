---
name: excel-live
description: Reads and edits .xlsx spreadsheets on this Mac when the tools for it are installed, and says so when they are not. Use when the user mentions a spreadsheet, workbook, Excel or an .xlsx file.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Excel files

Companion ships no spreadsheet engine. It uses what is installed on the Mac, and checks before promising.

## Steps

1. Check once per job with `run_shell`:
   ```
   python3 -c "import openpyxl" && echo ok
   ```
   `ok`: use Python with openpyxl (read cells, write values, add a sheet). Failure: stop here and say what is missing (see below).
2. Locate the file with `list_directory`; never guess the path.
3. Before writing, copy the file next to itself with a `-backup` suffix; every write asks the user once.
4. Read back the cells you changed and report them.

## Alternatives when nothing is installed

- Reading: `xlsx` files are zip archives; `run_shell` with `unzip -p file.xlsx xl/sharedStrings.xml` shows the text values for a quick look.
- Producing data: write a `.csv` with `write_file`; Excel and Numbers open it.
- Say clearly: "openpyxl is not installed; I can produce a CSV or you can install it with `pip3 install openpyxl`". Do not install it yourself.

## What Companion cannot do yet

Edit a workbook that Excel has open, run macros, or keep formulas and formatting intact without openpyxl.
