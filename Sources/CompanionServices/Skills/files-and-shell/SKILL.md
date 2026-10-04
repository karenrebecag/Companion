---
name: files-and-shell
description: Works with files and commands on this Mac safely, listing before guessing a path, reading before editing, one command per step, nothing destructive without the user's word. Use for any job that touches files, folders or the terminal.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Files and shell

The specialist's discipline. Every job that touches the disk follows it.

## Paths

- The name the user says and the name on disk rarely match. `list_directory` the folder first; never write a path you have not seen listed.
- Only the working folder and Companion's own folders are reachable. A refused path is refused: say so, do not route around it with a command.
- Absolute paths in every tool call.

## Reading and editing

- `read_file` before `edit_file`. `old_string` must be exact; take it from what you read.
- Prefer `edit_file` for a change and `write_file` for a new file. Rewriting a whole file to change one line loses what you did not read.
- Every write and every command asks the user once. Explain in the same turn what the write does, in one line.

## Commands

- One command per `run_shell`, short, with its output read before the next.
- To delete a file or folder use `delete_file`, not `rm`: it asks first and sends it to the Trash. Other destructive commands (`mv` over an existing file, `git reset`, anything with `--force`) need the user's words in this conversation naming the target. Otherwise propose it and stop.
- Never `sudo`, never install packages, never change shell configuration files.
- A command that hangs is stopped by Companion after a minute; keep them short.

## Reporting

Start with a one-line summary of what changed and where. Then the details for the screen: files touched with their paths, commands run, anything skipped and why.
