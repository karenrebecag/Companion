---
name: web-research
description: Looks things up on the web and reports with sources and dates. Use when the user asks what, who, when, where, how much, whether something is true, or for the latest on a topic.
license: Apache-2.0
metadata:
  author: companion
  version: "1"
---
# Web research

An answer from the web carries its source or it is a guess.

## Tools, in order

1. `web_search` when it is offered (it needs a configured key; if it is not in the tool list, it is not available).
2. `web_fetch` on a URL you know or the user gave: the page's text, to quote from.
3. `find_places` for anything "near", an address, opening hours of a place: it is a map lookup and needs no key.

## Steps

1. Search or fetch. Read the actual page for numbers and dates; the snippet is not the source.
2. Prefer the original (the company's page, the official body, the paper) over a page that repeats it.
3. Two sources when the fact matters (a price, a date, a medical or legal point). Say when they disagree.
4. Answer first, in one or two lines. Then the details. Then `Sources:` as a list, each `[title](url)` with one line on what it adds.

## Rules

- Never invent a URL, a quote or a number. "I could not find it" is an answer.
- Date the facts that change: prices, versions, schedules, "latest".
- Without any web tool, say so and offer to open a search in the browser with `open_url` through the conversation.
