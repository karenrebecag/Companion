---
name: browser-use
description: Acts on websites within what Companion can do today, opening a page in the user's browser or reading a page's text. Use when the user wants a site opened, looked at, checked or read.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Browser use

Companion has no hand inside the browser. It can open a page and it can read a page.

## Open

`open_url` opens a page in the user's default browser. A URL the user said themselves opens at once; one that came from a search or from the screen asks the user first. Use the full URL with its scheme.

## Read

`web_fetch` returns the text of a public page. Use it to answer from the page, quote its numbers and dates, and name it as the source. It does not log in, click, scroll or fill anything.

## Steps

1. Decide: does the user want to see the page (open) or know what it says (read)?
2. For "check", read first and open only if the user wants to act there.
3. Report what the page says with the URL; if the page needs a login, say so and open it for the user.

## Rules

- Never guess a URL. Search first (`web_search` if available) or ask.
- Never paste form values, passwords or card numbers anywhere.

## What Companion cannot do yet

Click, type into a site, log in, fill forms, buy, or read a page behind the user's session.
