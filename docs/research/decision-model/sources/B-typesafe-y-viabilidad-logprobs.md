# TypeSafe/Jev decision-model pattern: origin, claims, and feasibility with your providers

Research date: 2026-09-22. Every claim is tagged **[verified from source]** (fetched/read the primary or a directly-quoting secondary source) or **[inferred]** (my synthesis/reasoning, not a direct quote). Where a secondary source paraphrases a primary doc I could not fetch directly, I mark it **[verified from source, secondary]**.

---

## 1. TypeSafe / Jev / System One

### 1.1 What it is

TypeSafe AI is a startup (reportedly founded by Diogo Almeida, described as a former OpenAI researcher/ChatGPT contributor) that launched **Jev**, described as the first "System One Model," in early access on **September 15, 2026** — one week before this report. [verified from source, secondary] via MarkTechPost: https://www.marktechpost.com/2026/09/19/typesafe-ai-releases-jev/

Official definition, from `docs.typesafe.ai/concepts/system-one` [verified from source]:
> "System One models are a class of AI models built to make fast, structured decisions that software can use directly."

The name is an explicit Kahneman reference [verified from source, docs.typesafe.ai/concepts/system-one]:
> "The System One name comes from the concept Daniel Kahneman popularized in his book *Thinking, Fast and Slow*. System 1 thinking is fast and intuitive. System 2 is slower and more deliberate."

Core mechanism, from `docs.typesafe.ai/introduction` [verified from source]:
> "Jev evaluates typed *questions* against a *state* and returns structured results directly. No text generation, no parsing."
> "Each question is evaluated independently, so adding more questions does not create context-rot."
> "Every *question*... [is] evaluated in parallel and in isolation against the same *state* in one go."

Sources: https://docs.typesafe.ai/introduction · https://docs.typesafe.ai/concepts/system-one · https://typesafe.ai/

### 1.2 Question types

Confirmed **three** primitive question types, not just the two your context mentions (choice, noul) — there is also **score**. [verified from source, docs.typesafe.ai/introduction and docs.typesafe.ai/api]

- **Choice** — "Choose an option from a list," returns `choice`, `probabilities`, `confidence`. Max **255 options per Choice** [verified from source, docs.typesafe.ai/api: *"You can have a maximum of 255 options per Choice."*].
- **Score** — "Score the state on a rubric," returns `score`, `probabilities`, `confidence`, over ordered/descriptive levels. Max **10 levels per Score** [verified from source, docs.typesafe.ai/api].
- **Noul** — "Is this statement true?" (a yes/no question), returns a single scalar `noul` value 0–1 (probability the answer is "yes"). No separate `confidence` field is emitted for Noul in the example response (see 1.3) — confidence appears to be a Choice/Score-only field. [inferred from the example response schema below]

No `ranking` or `numeric` question type is documented. [inferred — absence of evidence across `docs.typesafe.ai/introduction`, `/api`, and `/llms.txt`]

Sources: https://docs.typesafe.ai/introduction · https://docs.typesafe.ai/api

### 1.3 Request/response schema

Endpoint: `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer <API_KEY>`, `Content-Type: application/json`. [verified from source, docs.typesafe.ai/api]

Full example request, quoted verbatim from `docs.typesafe.ai/api` [verified from source]:
```json
{
  "state": "Help! My payouts have been failing for 3 days.",
  "model": "jev-latest",
  "questions": {
    "is_urgent": {
      "type": "noul",
      "instructions": "Does this convey urgency?",
      "criteria": {
        "true": "Explicitly time-sensitive",
        "false": "No urgency expressed"
      }
    },
    "department": {
      "type": "choice",
      "instructions": "Which team should handle this?",
      "criteria": {
        "billing": "Payments, invoicing, refunds",
        "technical": "Bugs, outages, integrations",
        "sales": "Pricing, upgrades, new accounts"
      }
    }
  }
}
```

Full example response, quoted verbatim [verified from source]:
```json
{
  "model": "jev-1.13.0",
  "answers": {
    "is_urgent": { "type": "noul", "noul": 0.95 },
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": { "billing": 0.88, "technical": 0.12, "sales": 0.0 },
      "confidence": 0.81
    }
  },
  "usage": { "input_tokens": 318, "output_tokens": 34 }
}
```
This confirms the pattern your context describes: `probabilities` covers exactly the offered option ids and (per the example) sums to 1.00 (0.88+0.12+0.0). [verified from source — arithmetic on the quoted example]

`state` accepts "a plain string for text, or structured data (object/array)" [verified from source, secondary via search summary of docs.typesafe.ai/api]. Per `docs.typesafe.ai/models`, input is "Text only. String, JSON object, or array of text values. No image, audio, or video input." [verified from source]

### 1.4 Limits

From `docs.typesafe.ai/models` [verified from source]:
- **Context**: "64k tokens per request; 32k tokens for `state` plus the longest question."
- **Throughput**: "250,000 tokens per second / 1,200 requests per minute" (account-level, not per-request latency).
- Model: **Jev 1.13** (`jev-1.13.0`); aliases `jev-latest` → `jev-1.13.0`, `jev-preview` → `jev-1.13.0` (currently identical).
- Language: English primary; other languages "supported with lower accuracy."

From `docs.typesafe.ai/api` [verified from source]:
- Max 255 options per Choice question.
- Max 10 levels per Score question.
- `429` for rate limits, `529` for overload.

**Not found / not documented**: an explicit maximum number of *questions* per request. jev-voice fans out ~15 questions per utterance in one call [verified from source, jev-voice README] and jev-ultrafast documents "two decisions, one round trip" (op head + target head) [verified from source] — neither implies a hard cap; I could not find a stated ceiling on question count. **[not verified]**

### 1.5 Latency and price claims

From the launch blog post `typesafe.ai/blog/introducing-system-one-models-and-jev` [verified from source]:
> "End-to-end response time is 70ms-500ms" vs "3 to 329 seconds" for frontier LLMs on comparable tasks — "40x-200x faster."
> Homepage cites "193.6x faster" gains from workflow evaluations, and elsewhere "193.6x Faster, 244.6x Cheaper," "238x Lower input price than Claude Fable 5.1."
> Worked example: "Cost $0.000081, Completed in 0.114s" vs LLM alternative "Cost $0.013880, Completed in 8.566s."

Pricing, confirmed on both the blog and `docs.typesafe.ai/models` [verified from source]:
> Input: "$0.042 / MTok ($42 per billion tokens)." Output tokens: **free** — "too cheap to meter," because the model returns structured decisions, not long text.

Real-world (not TypeSafe-reported) numbers from jev-voice's own measurements on a Mac mini M4 [verified from source, jev-voice README]: Jev fan-out (~15 questions) took **170–420 ms**. This is consistent with, if at the higher end of, TypeSafe's own 70–500 ms range.

Caveat TypeSafe itself states about its benchmark suite [verified from source, secondary via blog fetch]: published workflow evaluations "are on the higher end of real world gains," and Jev "own[s] the Pareto frontier for almost 2 orders of magnitude" on curated tasks — i.e., their own framing flags the headline multiples as best-case, not typical.

### 1.6 How it claims to produce calibrated probabilities

TypeSafe states a custom training method, not "just logprobs off a base model": [verified from source, blog]
> "TypeSafe built a new stack with a new model architecture, parallel sampler for maximum efficiency, and a training method called Reinforcement Learning for Calibrated Decisions (RLCD)."

`docs.typesafe.ai/concepts/system-one` adds a calibration caveat that matters for your gating logic [verified from source]:
> "trained for calibrated decisions: their probabilities are optimized against outcomes to reflect uncertainty... Calibration is measured across groups of predictions; it does not guarantee that an individual answer is correct."

No public architecture paper was found describing whether Jev is a classifier head, a generative model read via logprobs, or something else; TypeSafe does not disclose model architecture. **[not verified]** — the closed nature of the model is exactly why third parties (openjev, qwen-rlcd — see 1.8) are trying to reverse-engineer the *interface* rather than the model.

### 1.7 `docs.typesafe.ai/confidence`

This page exists and is substantive [verified from source]. Key points:
- `probabilities` is the raw distribution; `confidence` is *derived* from it, not a separate model output: *"`confidence` is a statistic computed from the probability distribution the answer already gives you."*
- For **3 options** the formula is explicitly given: **`confidence = (3 × largest_probability − 1) / 2`**. (This generalizes to `(n·p_max − 1)/(n−1)` for n options, though only the n=3 case is quoted verbatim on the page — the general form is **[inferred]**.)
- Usage guidance: high confidence → act automatically; medium → confirm with user or gather more info; low → don't act, route to humans/fallback. A worked example uses a 0.5 floor for "genuinely uncertain" and >0.9 for high-stakes actions (financial transfers) vs. lower thresholds for read-only actions.
- Framing line: *"If an intelligent system cannot express honest uncertainty, the system cannot be trusted."*

### 1.8 Current availability

Your context says "closed to new signups ('Whoops, we're full')." As of **this** research (2026-09-22), that status has **changed**: [verified from source, secondary via multiple search-result summaries, most explicitly explainx.ai]
> TypeSafe removed the Jev waitlist on **September 21, 2026** — "Jev is now available to everyone. No waitlist," instant signup at `console.typesafe.ai` with **$5 free credit**. They reportedly cleared ~140,000 waitlist signups in the first 36 hours after the Sept 15 launch.

I could not independently re-verify this via a direct fetch of `console.typesafe.ai` (sign-up flows are typically behind auth/JS and WebFetch cannot complete a signup), so treat "open now" as **[verified from source, secondary — convergent but not primary-fetched]**. It is plausible the "we're full" message the reader saw was from the Sept 15–21 window and is now stale. Recommend she just try `console.typesafe.ai` directly.

### 1.9 Reception / criticism (for calibrating trust in the claims)

Hacker News, Sept 15 launch thread reportedly hit "1,655 points and 456 comments... within a day"; the thread was retitled from an editorializing "New frontier model 40-400x cheaper and 20-200x faster" within the hour, i.e. HN pushed back on the framing. [verified from source, secondary, via search summary]

Documented HN pushback: Jev "cannot produce an answer outside the schema you define... [but] can still be wrong. It can pick the wrong intent out of the five, with high confidence." I.e., type-safety ≠ correctness — matches TypeSafe's own confidence caveat in 1.7. [verified from source, secondary]

Reddit skepticism (r/singularity, r/LocalLLaMA), reported: "the industry rediscovering classification models" and comparisons to zero-shot classifier encoders (e.g., "gliformer"); a question whether Jev is "just a logprobs wrapper on a fine-tuned open model." Founder's reported response on X: the bottleneck is calibration training data, not architecture. [verified from source, secondary]

**Sources for section 1**: https://docs.typesafe.ai/introduction · https://docs.typesafe.ai/concepts/system-one · https://docs.typesafe.ai/api · https://docs.typesafe.ai/models · https://docs.typesafe.ai/confidence · https://docs.typesafe.ai/llms.txt · https://typesafe.ai/ · https://typesafe.ai/blog/introducing-system-one-models-and-jev · https://www.marktechpost.com/2026/09/19/typesafe-ai-releases-jev/ · https://www.explainx.ai/blog/jev-general-availability-no-waitlist-2026 · https://www.datacamp.com/blog/system-one-models-jev

---

## 2. jev-ultrafast (browser-use)

Repo: https://github.com/browser-use/jev-ultrafast — "Fastest and cheapest web agent," shipped mid-September 2026. [verified from source, README]

### 2.1 Core claim
> "Give it one goal. TypeSafe's Jev picks an operation and an element." The system rejects generating prose about the page and instead "builds a fresh indexed element table for every observation—buttons, comboboxes, textboxes, with roles, labels, and current values." [verified from source]

### 2.2 The "heads" design
- **Operation head**: `CLICK, TYPE_TEXT, SELECT, SCROLL, WAIT, DONE, BLOCKED` — a Choice question over a fixed small vocabulary.
- **Target head(s)**: per operation type, "only compatible elements [are] offered" — i.e., the candidate set for the Choice is filtered by what the chosen (or candidate) operation can legally act on.
- Design goal stated verbatim: **"Two decisions, one network round trip."** [verified from source] — this is the "one Jev call answers multiple correlated questions" pattern your context describes generalized to op+target.

### 2.3 Text-helper model
For `TYPE_TEXT`, since Jev only selects (it doesn't generate free text), a separate small text-generation model fills in the actual string to type — the README's example uses **`inception/mercury-2.5` via OpenRouter**. [verified from source] This is architecturally important: Jev's "no text generation" purity is preserved by delegating the one genuinely generative sub-task (what to type) to a different, conventional model.

### 2.4 Measured numbers
> "Zürich → London on Google Flights in 7.1 seconds" — detailed as **7,073 ms** total including model calls, text generation, browser work, and loading waits.
> Comparative benchmark: "Median task time went from 9.450s → 7.092s, a 25% reduction," and "median browser protocol calls went from 1,092 → 101."
> Explicit honesty caveat, quoted: **"three repeats of one task on one browser profile, not a general reliability benchmark."** [verified from source]

### 2.5 Failure modes / stated limitations
Verbatim: "Shadow roots, frames, canvas, uploads, pop-up tabs, nested scrolling, and arbitrary keyboard widgets remain outside this MVP." Success still requires "independent outcome verification" — i.e., the authors do not claim the selection mechanism alone guarantees task success; a verifier layer is still needed. [verified from source]

I did not find a separate "browser-use ultrafast" blog post distinct from the repo README itself — the repo appears to be the primary artifact; no dedicated browser-use.com blog post was surfaced by search. **[not verified — may exist but wasn't found]**

**Sources for section 2**: https://github.com/browser-use/jev-ultrafast · https://agentbreaking.com/blog/browser-use-jev-ultrafast-guide/

---

## 3. jev-voice (kevinbadi) — how it actually uses the pattern

Repo: https://github.com/kevinbadi/jev-voice — "Talk to your Mac. Local whisper.cpp + one Jev (TypeSafe) call per command + macOS automation." MIT license. [verified from source, README]

### 3.1 Pipeline
> "mic ─► energy VAD ─► whisper.cpp (Metal, ~100 ms) ─► Jev (1 request, ~250 ms) ─► macOS actions ─► `say`" [verified from source]

### 3.2 The "brain" (`jev_voice/brain.py`)
- One request per utterance, **~15 speculative questions evaluated in parallel** in that single request.
- Question keys/types include: `action` (13 action kinds), `app` (installed apps), `site`, `engine`, `folder`, `shortcut`, `scroll_dir`, `volume_op`, `media_op`, `system_op` — all Choice-shaped over code-enumerated candidate sets — plus Noul-typed fields `submit`, `compound`.
- `text` is notably **not** free-generated: it's "Choice over candidate spans cut from the transcript by regex" — i.e., even "extracting the text argument" is turned into a selection problem over regex-derived candidate substrings, not generation. [verified from source] This is a concrete instance of the "decision model" discipline applied to what would normally be a generation task.
- `ACTION_MIN_CONFIDENCE = 0.35` gates a "not sure" fallback response — a direct application of the confidence-gating pattern from docs.typesafe.ai/confidence.

### 3.3 Measured latency (Mac mini M4)
| Stage | Duration |
|---|---|
| End-of-speech detection | 550 ms of silence |
| whisper.cpp base.en | 80–130 ms |
| Jev fan-out (~15 questions) | 170–420 ms |
| Execute + `say` | ~50–100 ms |
[verified from source]

### 3.4 Multi-step / computer-use loop
For complex goals: "AX tree of the frontmost window ─► indexed element table ─► one Jev request ─► executor," operation types `CLICK, TYPE_TEXT, OPEN_APP, PRESS_KEY, SCROLL_UP, SCROLL_DOWN, WAIT, DONE, BLOCKED`. Bounds: **40 actions, 80 Jev calls max per task.** This mirrors jev-ultrafast's op-head/target-head design but reads macOS Accessibility (AX) tree elements instead of DOM elements — i.e., it's the same pattern applied to native macOS UI instead of a browser. [verified from source]

Optional `ANTHROPIC_API_KEY` env var for "Claude planner" — suggesting a hybrid design where a System-2-style LLM (Claude) can be used for higher-level planning while Jev handles the fast per-step selection. [verified from source — the env var and its stated purpose]

**Sources for section 3**: https://github.com/kevinbadi/jev-voice/blob/main/README.md

---

## 4. Reproducing "choice with a real distribution" — provider capability matrix

**Bottom line up front [inferred, synthesized from 4a–4e below]:** you cannot get Jev's exact behavior (a closed, RLCD-trained, purpose-built calibration model) from any of your providers. What you *can* get, with real work, is a mechanically similar primitive — "ask for one of N labeled options, read `logprobs`/`top_logprobs` over the label tokens, renormalize" — on OpenAI (best supported), on some OpenRouter-routed models, and on your own Ollama/llama.cpp/MLX models locally. Anthropic and Groq are currently dead ends for this specific technique.

### 4a. OpenAI Chat Completions

- `logprobs: true` + `top_logprobs: <int>` — **max value 20** ("integer between 0 and 20 specifying the number of most likely tokens to return at each token position"). [verified from source, secondary via OpenAI API reference search summary — direct fetch of `platform.openai.com/docs/api-reference/chat/create` returned HTTP 403]
- **Reasoning models do not support logprobs**: "Reasoning models other than [current flagship] don't support logprobs parameters, including o3-mini, o1, and related reasoning models." Non-reasoning models (the GPT-4o/4.1/GPT-5-non-reasoning family) are expected to support it as a standard Chat Completions feature, but I could not find an explicit current allow-list naming gpt-4o-mini or gpt-4.1-nano by name with logprobs confirmed. **[largely inferred from the reasoning-model exclusion + legacy behavior; not a positive confirmation for every specific 2026 model name]**
- **Structured outputs**: compatible. `response_format: {type: "json_schema", ...}` can be combined with `logprobs: true` in the same request; a community library (`structured-logprobs`) exists specifically to post-process logprobs against a structured-output schema. [verified from source, secondary]
- **Tool/function calls**: **logprobs are NOT supported together with function calling** per community-documented behavior — "Logprobs are not supported with function calls." [verified from source, secondary] This matters: if you're tempted to use OpenAI tool-calling with an enum argument to force a choice, you lose the probability distribution; you'd need plain Chat Completions with a raw single-token answer instead.
- **Responses API**: logprobs support is a documented gap. From the OpenAI developer community: "the create model response API doesn't have the logprobs parameter" and a named current flagship reasoning model "does not support custom temperature or top_p values or log probabilities (logprobs)." [verified from source, secondary] **Practical implication for you: use Chat Completions, not Responses API, if you need logprobs today.**
- Legacy Completions API (`/v1/completions`, non-chat) historically capped `logprobs` at **5**, distinct from Chat Completions' `top_logprobs` max of 20 — don't confuse the two when reading older blog posts/cookbooks. [verified from source, secondary]

Sources: https://developers.openai.com/api/docs/guides/prompt-caching (for adjacent context) · https://community.openai.com/t/why-doesnt-the-responses-api-support-logprobs/1148097 · https://community.openai.com/t/are-logprobs-not-yet-supported-in-the-reponses-api/1359018 · https://github.com/arena-ai/structured-logprobs · https://developers.openai.com/cookbook/examples/using_logprobs

### 4b. OpenRouter

Passthrough is real but partial and provider-dependent. [verified from source, secondary]
> "If the chosen model doesn't support a request parameter... then the parameter is ignored. The rest are forwarded to the underlying model API."
> "23% of reachable endpoints on OpenRouter support returning between 5 and 20 logprobs," including "all available models from xAI, multiple models from OpenAI including the GPT-4.1 series, and multiple open-weight models such as Qwen, Gemma, Llama, Deepseek, or Mistral." "Fireworks AI and Azure return 5 logprobs, xAI 8 logprobs, and other providers return 20 logprobs."

Practical implication: with OpenRouter you must check per-model/per-upstream-provider whether `logprobs`/`top_logprobs` actually comes back non-null — silently-ignored parameters are the documented failure mode, not an error. **[inferred practical guidance from the quoted behavior]**

Source: https://arxiv.org/html/2512.03816v1 ("Log Probability Tracking of LLM APIs" — this looks like a relevant empirical measurement paper; worth her reading directly for the per-provider table) · https://openrouter.ai/docs/guides/community/typesafe-sdk (OpenRouter even documents a community TypeSafe/Jev SDK, evidence Jev-style usage is being explicitly discussed in the OpenRouter ecosystem)

### 4c. Local: Ollama, llama.cpp, MLX, Apple Foundation Models

**Ollama** — this is the important negative finding for a Swift/macOS app defaulting to local-first:
- Native `/api/generate` **does** compute and return logprobs (referenced issue #13497). [verified from source, via GitHub issue #16117 body]
- The **OpenAI-compatible `/v1/chat/completions` layer currently does NOT expose them** — issue https://github.com/ollama/ollama/issues/16117, filed to request wiring `logprobs`/`top_logprobs` through to match OpenAI's shape, is **closed as "not planned"**, with no merged PR. [verified from source — I fetched the issue directly] Maintainer disposition ("not planned") means: don't wait for this: if you need logprobs from Ollama, you must use the **native** `/api/generate` endpoint, not the OpenAI-compat `/v1` endpoint, and you must parse Ollama's own (non-OpenAI-shaped) logprobs format.
- A separate open report says Ollama Cloud's hosted API accepts `logprobs: true` but returns `null` — i.e., even where the parameter is accepted, it may be silently non-functional. [verified from source, secondary, issue #13638]
- I did not find the exact response field name/shape Ollama uses on `/api/generate` for logprobs in the material fetched — **[not verified, needs a direct read of Ollama's `/api/generate` docs at `docs.ollama.com` if she needs the exact JSON shape]**.

**llama.cpp server** — this is your best-supported *local* path:
- Already supports `n_probs` (legacy) and `logprobs` on `/completion`, including "full logits" on that endpoint. [verified from source, secondary via search of llama.cpp PR/issue tracker]
- `/v1/chat/completions` (OpenAI-compat) has had logprobs bugs historically; PR https://github.com/ggml-org/llama.cpp/pull/10783 ("server: fix logprobs, make it OAI-compatible") indicates active work to align it. Current caveat reported: "Integer `logprobs=N` is not honored (only legacy `n_probs`, or boolean `logprobs: true` + `top_logprobs`; the response logprobs format is the non-OAI `{"content": [...]}` shape)" — i.e., **use the boolean `logprobs`+`top_logprobs` combo, not an integer `logprobs=N`, and expect a llama.cpp-specific response shape, not exactly OpenAI's.** [verified from source, secondary]
- Grammar-constrained decoding (GBNF) is separate from logprobs but composable with it — see section 6.

**MLX / mlx-lm** (most native path on Apple Silicon, which matters given her M-series Mac target):
- `mlx_lm.server` is described as supporting "streaming, tools with schema-driven auto-repair, JSON-schema constrained decoding, logprobs, vision, thinking as reasoning_content" — i.e., logprobs are a documented server feature. [verified from source, secondary] I could not fetch the mlx-lm docs directly to confirm exact request/response field names or a `top_logprobs`-equivalent cap — **[not fully verified, worth a direct check of `mlx-lm`'s README/server docs before building on it]**.
- Related third-party servers exist (`mlx-omni-server`, `mlx-openai-server`, `mlx-serve`) that wrap MLX models behind OpenAI-compatible endpoints; several explicitly advertise logprobs support, but these are community projects, not Apple-official, and quality/parity with OpenAI's exact schema is unverified per-project. **[not verified]**

**Apple Foundation Models framework (macOS 26)** — negative finding, and an important one for a native Swift app:
- The framework's headline feature is **guided generation via `@Generable`** — Swift macros that compile a type into a constrained-decoding schema, so the on-device model is "strictly limited to tokens that are valid for its current position in the schema." This **guarantees a well-typed answer**, exactly like Jev's "structured output error rate: 0%" claim — but it is a *constraint*, not a *probability distribution*. [verified from source, Apple ML research / WWDC25 materials]
- **No logprobs API is exposed to developers.** An independent audit is quoted directly: "There is no logprob API available in Apple's Foundation Models framework... Verbalized confidence is the only uncertainty signal the framework hands developers." And, more damningly for calibration: that audit found the on-device model's self-reported (verbalized) confidence "separates its correct answers from its wrong ones at **AUROC 0.47** — statistically below a coin flip." [verified from source, secondary — quoted from https://www.beri.net/article/apple-on-device-foundation-model-audit-confabulation-consistency-sampling] **This is the single most important caveat for her if she was hoping to get "free" calibrated confidence from Apple's on-device model: as of this audit, its verbalized confidence is reported as worse than useless for discriminating correct vs. incorrect answers.**

Sources for 4c: https://github.com/ollama/ollama/issues/16117 · https://github.com/ollama/ollama/issues/13638 · https://github.com/ggml-org/llama.cpp/pull/10783 · https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md · https://developer.apple.com/videos/play/wwdc2025/301/ · https://www.beri.net/article/apple-on-device-foundation-model-audit-confabulation-consistency-sampling · https://machinelearning.apple.com/research/apple-foundation-models-2025-updates

### 4d. Anthropic Messages API

**Confirmed: no logprobs.** [verified from source, secondary] "Anthropic's Messages API doesn't expose logprobs at all (Bedrock/Vertex variants included)... this is a hard limitation of the upstream API, not something that can be worked around." There are community proposals for what an eventual Anthropic logprobs API might look like (mirroring OpenAI's `logprobs`/`top_logprobs 0-20`), but nothing shipped as of this research. Anthropic prompt caching (relevant to section 5) does work and is documented (see 5b) — that's a separate feature from logprobs.

Source: community summary citing Anthropic API docs; no first-party Anthropic page claims logprobs support (absence-of-evidence corroborated by two independent searches).

### 4e. Groq / Cerebras / Together / Fireworks

- **Groq: NOT supported**, contrary to what OpenRouter's aggregate "xAI, OpenAI, open-weight" list might suggest for other providers. Explicit: "The `top_logprobs` parameter is not yet supported by any of Groq's models," and it's listed as an unsupported parameter in Groq's own OpenAI-compatibility docs, despite the field existing in their API reference schema. [verified from source, secondary] Given latency is the whole reason to reach for Groq, this is a real gap for her use case.
- Also relevant: **Groq deprecated `llama-3.1-8b-instant` on August 16, 2026**, recommending `openai/gpt-oss-20b`, `openai/gpt-oss-120b`, or `qwen/qwen3.6-27b` as replacements — so any latency numbers you see for "Groq + Llama-3.1-8B" (including in older blog posts) describe a model no longer served there. [verified from source, secondary]
- **Cerebras: supported.** "Cerebras supports returning log probabilities for generated tokens" (default false); notably, "logprobs are now computed from the model's raw output before applying temperature scaling, and logprob values remain consistent regardless of the temperature used" — a useful property if you want temperature-independent probabilities. [verified from source, secondary]
- **Fireworks AI: supported** — logprobs parameter present, corroborated by a LiteLLM integration PR adding Fireworks logprobs pass-through. [verified from source, secondary]
- **Together AI: supported**, with the caveat that "not all Together AI models support logprobs; if you use an unsupported model, the API will return an error" — i.e., check per-model, don't assume account-wide support. [verified from source, secondary]

Sources: https://console.groq.com/docs/api-reference.md · https://console.groq.com/docs/openai · https://inference-docs.cerebras.ai/support/change-log · https://github.com/BerriAI/litellm/pull/6915 · https://theneuralbase.com/together-ai/learn/intermediate/logprobs-access/

---

## 5. Techniques for "single-token choice via logprobs"

### 5a. The technique itself
Standard recipe, corroborated across multiple sources: label each option with a **single token** (a letter A/B/C… or a digit), set `max_tokens: 1`, request `logprobs: true, top_logprobs: N`, read the returned distribution over the label tokens, **renormalize** over just the offered labels (since the model's raw top-k may include other tokens, and softmax over the full vocabulary spreads mass elsewhere). [verified from source, secondary, multiple corroborating summaries incl. https://www.sciencedirect.com/science/article/pii/S2666920X26000408]

### 5b. Known pitfalls
- **Tokenization**: the label must be a genuinely single token in the target model's vocabulary. Confirmed for MMLU-style A–D/A–J letters on common tokenizers: "every primary tokenizer represents each single-letter option A-J as exactly one token, so the top-k logprob window returns letter probabilities directly" — but this is tokenizer-specific and should be checked, not assumed, for any new model. [verified from source, secondary] A dedicated paper exists specifically on this failure mode: "Mind the Gap: A Closer Look at Tokenization for Multiple-Choice Question Answering with LLMs" (https://arxiv.org/pdf/2509.15020).
- **Position/selection bias**: documented and significant. "LLMs often exhibit a preference for certain answer options, such as the first option 'A'... LLMs tend to excel when correct answers are placed in preferred positions, but degrade substantially otherwise." "The probabilistic mass on a single token is sensitive to its context and is biased towards a certain token ('A') which leads to selection bias." A debiasing method (**PriDe**) exists specifically to disentangle first-token position bias from the semantic probability. [verified from source, secondary] Practical implication for her Swift app: if she rotates/shuffles candidate order between calls (or duplicates the query with shuffled order and averages), she reduces this bias; a fixed canonical order will silently favor whichever slot the model likes. **[inferred practical mitigation, standard in the literature]**
- **Renormalization is mandatory**, not optional, per the base technique description above.
- Related paper specifically on how models "assemble" MCQ answers, relevant to why this works at all: "Answer, Assemble, Ace: Understanding How LMs Answer Multiple Choice Questions" (https://arxiv.org/html/2407.15018v2).

### 5c. Verbalized confidence vs. token probability — the calibration literature
- **Kadavath et al. 2022, "Language Models (Mostly) Know What They Know"** (arXiv:2207.05221): "Larger models are well-calibrated on diverse multiple choice and true/false questions when they are provided in the right format." Introduces the "P(True)" self-evaluation technique. [verified from source, secondary]
- **Lin, Hilton, Evans 2022, "Teaching Models to Express Their Uncertainty in Words"** (arXiv:2205.14334): shows GPT-3 can be fine-tuned to emit a verbalized confidence (e.g., "90% confidence") **without using model logits at all**, and those verbalized numbers can be well-calibrated. This is the "verbalized confidence" alternative to reading logprobs. [verified from source, secondary]
- **Tian et al. 2023, "Just Ask for Calibration"** (arXiv:2305.14975): for **RLHF-tuned** models specifically (ChatGPT/GPT-4/Claude-class), **verbalized confidence beats raw conditional (token) probability** for calibration — "often reducing the expected calibration error by a relative 50%," and improves further if the model is first prompted to enumerate multiple candidate answers before stating confidence. **This is directly relevant and somewhat counter-intuitive for her plan**: for instruction-tuned/RLHF models, the raw logprob-over-label-token approach (section 5a) may be *less* calibrated than just asking the model to say a confidence number in words. [verified from source, secondary]
- **GPT-4 Technical Report** (arXiv:2303.08774), Figure 8, is the canonical citation for the RLHF-degrades-calibration finding you asked me to confirm: "The pre-trained model is highly calibrated... However, after the post-training process, the calibration is reduced (Figure 8)." [verified from source, secondary]
- **2025–2026 follow-ups** worth her attention, found but not deeply read:
  - "Trained on Tokens, Calibrated on Concepts: The Emergence of Semantic Calibration in LLMs" (ICLR 2026, arXiv:2511.04869) — argues base (pretraining-only) models are well-calibrated *at the semantic/concept level*, and this is "systematically broken by instruction tuning and chain-of-thought reasoning." Directly supports avoiding heavily-RLHF'd/CoT-tuned models if she wants raw-logprob calibration, or favoring base-ish models.
  - "Semantic Calibration Prevails Where Token Confidence Fails" (arXiv:2602.00279) — reports token probabilities *and* verbalized uncertainty are both poorly calibrated under "increasing reasoning complexity," with only semantic-consistency (self-consistency/sampling-based) methods holding up.
  - "Reinforcement Learning with Verbalized Probabilities for LLM Classification" (ACM Web Conf 2026) — a training-time fix (RLVP) specifically targeting "calibrated multi-class probability distributions" — i.e., independent confirmation that this is an active, unsolved research problem in 2026, which is consistent with TypeSafe's RLCD claim being a real (if proprietary) research direction rather than marketing vapor. [verified from source, secondary, for all three]

**Net read for her [inferred synthesis]:** raw single-token logprobs (5a) are the mechanically simplest way to reproduce "a real distribution," and work reasonably on base/lightly-tuned or open-weight models; but for the RLHF-heavy hosted models she's most likely to reach for by default (GPT-4o/4.1-class, Claude), the calibration literature says **verbalized confidence may out-calibrate raw logprobs**, which is the opposite of what the Jev pattern (probabilities as the primary signal) assumes. If calibration quality matters to her (not just getting *a* number), she should empirically compare both on her own task before committing to either.

### 5d. Constrained decoding — guarantees validity, not a distribution
- **llama.cpp GBNF grammars**: work by zeroing out (masking) the probability of any token that would violate the grammar, "with no impact on scoring for valid outputs" — i.e., the relative probabilities among *valid* tokens are preserved (not redistributed), so in principle you could combine grammar-constraining with reading logprobs over the constrained set. [verified from source, secondary] This is a meaningfully different (and better) property than a naive "always guarantees validity but throws away probabilities" assumption.
- **Outlines / guidance-style constrained decoding**: same masking principle at a conceptual level, though these tools historically had "boundary mismatch problems" reconciling character-level and token-level grammars (cited: SynCode paper). [verified from source, secondary]
- **OpenAI structured outputs with `enum`**: guarantees the returned value is one of the enum members (validity), and per 4a, you *can* combine `response_format: json_schema` with `logprobs: true` in the same Chat Completions call — but the returned logprobs are then per output *token* of the JSON (e.g., over each character/subword of the field value), not a clean single distribution over your enum options the way Jev's `probabilities` field is. Getting a clean enum-level distribution out of that still requires the single-token-label trick from 5a, or post-processing (this is exactly what the `structured-logprobs` library exists to do). [inferred, combining 4a facts with the schema mechanics]

**Conclusion for section 5**: constrained decoding (grammars, enums, `@Generable`) solves "never get an invalid answer" — the same guarantee Jev advertises ("mathematically impossible" to violate schema) — but it does **not**, by itself, give you Jev's `probabilities` dict. For that you still need either (a) the single-token-label + logprobs trick, layered under a grammar/enum constraint if you want both guarantees, or (b) verbalized confidence per 5c.

---

## 6. Speculative fan-out — answering ~20 questions in one request

### 6a. The core problem
Jev answers ~15–20 independent Choice/Noul questions against one `state` in a single ~250 ms request (section 1.3, 3.2). A standard chat completions call either (a) needs N separate requests, one per question, or (b) can ask for one JSON blob with N fields in one request — but (b) gives you, at best, per-*token* logprobs over the JSON output, not a clean isolated probability distribution per logical question, and the questions can interfere with each other through the model's own generation order (later fields conditioned on earlier ones, unlike Jev's stated "evaluated independently... in isolation"). **[inferred, following directly from the schema facts already verified in sections 1 and 4]**

### 6b. Prompt caching as the mitigation for N-separate-requests
Both major hosted providers cache automatically and share a fixed, sizeable state (your `state` object, if reused across N questions, is exactly the kind of shared prefix caching rewards):
- **OpenAI**: automatic, no code changes needed, once a prompt exceeds **1,024 tokens**, with additional cache hits in **128-token increments** beyond that; "if you reuse prompts with common prefixes, the system will automatically apply the Prompt Caching discount." [verified from source, secondary] — **Caveat: your `state` (e.g., a screen/AX-tree dump or a transcript) needs to be ≥1,024 tokens for this to trigger at all**; short voice-command states, like jev-voice's, likely fall under this floor, so OpenAI's automatic caching may not help a small-state, many-questions workload as much as it helps a large-state one. **[inferred]**
- **Anthropic**: minimum cacheable prefix is **1,024 tokens for Sonnet/Opus, 2,048 tokens for Haiku**; requires explicit `cache_control` breakpoints (not fully automatic like OpenAI, though "top-level automatic caching places the breakpoint on the last cacheable block for you"). [verified from source, secondary]
- Neither of these actually reduces round trips — they reduce the **cost and, to a lesser extent, latency** of the N requests you still have to make, by not re-paying full prefill cost/time on the shared prefix each time. They do not give you Jev's single-request multi-question fan-out.

### 6c. The `n` parameter — does it help?
OpenAI's `n` parameter generates **N independent completions from the same prompt** in one request, and can be combined with `logprobs`/`max_tokens: 1`. [verified from source, secondary] **This does not solve her problem as stated**, because `n` samples the *same* question N times (useful for self-consistency/variance estimation), not N *different* questions — Jev's fan-out is over distinct questions against a shared state, not repeated sampling of one question. **[inferred — this is the key limitation to flag for her]** If she wants Jev-style "N different questions, one round trip," `n` is the wrong tool; she needs either N separate requests (mitigated by caching, 6b) or a single request whose output is structured as N fields (accepting the isolation/interference caveat from 6a).

### 6d. Local models: shared-KV-cache branching is the closest real analog
The **openjev** project (an open, unaffiliated reproduction of Jev's *interface*, not its model — explicitly stated: "This project reproduces that interface pattern with open models; it does not reproduce Jev's undisclosed model or training") gives concrete, measured numbers for exactly this fan-out pattern on a local GPU, using a frozen Qwen3.5-4B: [verified from source, README of https://github.com/2bbb/openjev]

| Strategy | Throughput | Total time (37 states × 21 criteria) |
|---|---|---|
| Fresh direct scoring (no cache reuse) | 2.33 decisions/s | 333.1 s |
| Serial prefix reuse (shared KV cache) | 10.75 decisions/s | 72.3 s |
| Parallel suffixes (branching) | 20.03 decisions/s | 38.8 s |

That's roughly an **8.6× speedup** from prefetching the shared `state` once into a KV cache and branching per-question off that cache, vs. re-encoding the full state fresh for every question. [verified from source — arithmetic on the quoted numbers, 20.03/2.33 ≈ 8.6] Single-question logit readout (no generation) on the same 4B model: **1.023 s median** vs. **5.332 s** for autoregressive JSON generation of the same answer — a **5.21× speedup** just from not generating text. [verified from source]

This is the closest thing to a "recipe" for reproducing Jev's fan-out locally on Apple Silicon: (1) run a small open model via MLX or llama.cpp, (2) encode the shared `state` once, (3) branch N single-forward-pass, no-sampling logit reads off that cached prefix, one per question — mechanically identical to what openjev demonstrates on a 3090, and (given llama.cpp/MLX both support KV-cache reuse) architecturally portable to Metal. **[inferred — the openjev numbers are on CUDA/3090, not verified on Apple Silicon, but the underlying KV-cache-prefix-reuse technique is a standard llama.cpp/MLX capability, not CUDA-specific]**

### 6e. Realistic latency expectations for 20 parallel single-token calls

Given data gathered, and being explicit about what's measured vs. estimated:

- **OpenAI gpt-4o-mini / gpt-4.1-nano**: no directly measured "20 single-token calls" benchmark was found in this research. Single Chat Completions calls with `max_tokens=1` on small/fast OpenAI models typically report time-to-first-token in the **low hundreds of ms** range in general benchmarking (not specific to this exact config) — **[largely inferred/estimated, not a verified benchmark for this specific parameter combination]**. With 20 requests fired concurrently (not serially) and shared-prefix caching (6b) covering the repeated `state`, wall-clock for the batch should be dominated by the single slowest concurrent request rather than 20× a single request's latency, if her client issues them in parallel. **[inferred]**
- **Groq**: not usable for this technique today per 4e (`top_logprobs` unsupported), so latency is moot for the logprobs approach specifically — though Groq remains relevant for the *text-helper* sub-task (as jev-ultrafast uses via OpenRouter/Mercury) where you don't need logprobs, just fast generation.
- **Local Ollama/llama.cpp 3–8B on an M-series Mac**: no direct Apple Silicon benchmark for "20 parallel single-token logprob reads" was found. The openjev CUDA numbers (6d) — ~1 s per single-question logit read *without* prefix caching, dropping sharply with prefix reuse — are the best available proxy, but 3090 (CUDA, ~936 GB/s+ memory bandwidth) is not directly comparable to M-series unified memory bandwidth (roughly 100–800 GB/s depending on chip tier), so treat any specific millisecond number here as **[not verified for Apple Silicon]**. jev-voice's own measured 170–420 ms for a **~15-question fan-out through the hosted Jev API** (not local) is the most concrete real number in this whole report for "what does a ~15-20 question single-call fan-out feel like in practice" — but that's TypeSafe's own optimized closed model, not a reproducible local baseline.

**Honest summary for 6e [inferred]**: I could not find a verified apples-to-apples "20 single-token logprob calls, M-series Mac, local model" latency benchmark. The strongest available anchor points are (a) jev-voice's ~170-420ms for the *real* hosted Jev fan-out, and (b) openjev's CUDA numbers showing prefix-caching yields ~5-8x speedups over naive per-question scoring. She should expect local Apple Silicon performance for a well-implemented (shared-prefix, no-sampling, single-forward-pass) 8B-class model fan-out of ~15-20 questions to plausibly land in the same rough ballpark (hundreds of ms to low seconds) as the hosted numbers reported here, but this needs her own benchmarking to confirm — I flag it as an estimate, not a citation.

**Sources for section 6**: https://developers.openai.com/api/docs/guides/prompt-caching · https://platform.claude.com/docs/en/build-with-claude/prompt-caching · https://community.openai.com/t/why-does-prompt-caching-requires-at-least-1024-tokens/1363167 · https://github.com/2bbb/openjev · https://github.com/kevinbadi/jev-voice/blob/main/README.md

---

## 7. Prior art — action selection over enumerated candidates

- **Set-of-Mark (SoM) prompting** (Yang et al., arXiv:2310.11441, Microsoft) — overlays numbered marks on segmented image regions so GPT-4V can *refer to* regions by ID instead of generating pixel coordinates; "outperforms the state-of-the-art fully-finetuned referring expression comprehension... model on RefCOCOg in a zero-shot setting." Direct ancestor of "index the candidates, let the model pick an ID." https://arxiv.org/abs/2310.11441 · code: https://github.com/microsoft/SoM
- **WebVoyager** (arXiv:2401.13919, ACL 2024) — applies SoM to live websites: a JS tool (not a vision model) extracts interactive elements and overlays numbered bounding boxes; agent picks by number. "Combining screenshot observation with text input nearly doubles success rates... vs. text-only." Direct architectural sibling of jev-ultrafast's indexed-element-table approach, minus the calibrated-probability layer. https://arxiv.org/html/2401.13919v3
- **browser-use (base project)** — the framework jev-ultrafast is built on top of; builds an indexed DOM element list every step so a generative LLM can *select* an element index rather than emit a selector/XPath. jev-ultrafast's contribution is swapping the generative selection step for Jev's typed Choice. https://github.com/browser-use/jev-ultrafast (references parent project browser-use/browser-use)
- **OSWorld** (arXiv:2404.07972, NeurIPS 2024 D&B track) — real-OS benchmark; notably uses **pyautogui-style continuous coordinates** (`click(x,y)`, `moveTo(x,y)`), i.e., action space is *not* enumerated/indexed — a useful contrast case showing the field hasn't universally converged on "select, don't generate coordinates." https://arxiv.org/pdf/2404.07972
- **Anthropic computer-use** — explicit **contrast case** requested: Claude looks at raw screenshots and *generates* pixel coordinates ("click at coordinates (450, 320)"), not a selection over an indexed/enumerated candidate set; coordinate system is "always in the pixel space of the screenshots you return." This is the generation-based approach the whole Jev/SoM/browser-use lineage is reacting against. https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool
- **Ferret-UI / Ferret-UI 2** (Apple, arXiv:2410.18967 for v2) — mobile/cross-platform UI-understanding MLLM with explicit "referring, grounding, and reasoning" over UI elements; Ferret-UI 2 uses GPT-4o **with Set-of-Mark** to generate its own training data — i.e., SoM is now used recursively to bootstrap training sets for UI models. https://machinelearning.apple.com/research/ferret-ui-2
- **UI-JEPA** (Apple ML research) — self-supervised (JEPA-style masking) embedding of UI screens + an LLM decoder for user-*intent* prediction (not element selection per se, but the same "structured perception before language" philosophy). https://machinelearning.apple.com/research/ui-intent
- **ScreenAI** (Google, arXiv:2402.04615) — introduces a unified "Screen Schema": UI elements as a structured string (type, OCR text, quantized bounding box 0-999, hierarchical parentheses) — i.e., turning screen perception into a structured/typed representation *before* handing it to a (possibly text-only) LLM, conceptually parallel to how jev-voice turns an AX tree into an indexed element table before querying Jev. https://arxiv.org/html/2402.04615v3
- **Tool selection via classification/routing** (industry practice, not one paper) — production agent-routing systems increasingly replace "ask the LLM to pick a tool by generating its name" with embedding-based nearest-neighbor routing or small fine-tuned classifiers (SetFit/DistilBERT/ModernBERT), reporting "16-100ms" routing latency vs multi-second LLM-routing calls, and citing one deployment's "5,000ms → 100ms" reduction. This is the same "select, don't generate" philosophy applied to tool/route selection rather than UI elements, and is the most directly comparable *production pattern* (as opposed to research paper) to what Jev is commercializing as a hosted API. https://tianpan.co/blog/2026/04/09/tool-selection-problem-agent-tool-routing-at-scale

All items in this section: **[verified from source, secondary]** unless noted — i.e., I read search-engine-summarized quotations of these papers/docs/blogs rather than fetching each primary PDF in full; the arXiv IDs and URLs are correct and independently checkable.

---

## What I could not verify

1. **A hard cap on the number of *questions* per single `/v1/systemone` request.** Only per-question limits (255 Choice options, 10 Score levels) and a 64k-token/32k-state context budget were documented; no explicit "max N questions" was found despite checking `docs.typesafe.ai/api`, `/models`, `/introduction`, and `/llms.txt`.
2. **Jev's actual model architecture** (classifier head vs. decoder-with-logprobs vs. something bespoke). TypeSafe discloses only the training-method name (RLCD) and speed/parallel-sampler claims, not architecture. Third-party speculation (r/LocalLLaMA) is unconfirmed.
3. **Whether `console.typesafe.ai` signup is actually open right now, first-hand.** I could not complete a live signup flow with WebFetch; the "waitlist removed Sept 21" claim is well-corroborated across several secondary sources but not confirmed by directly loading the console/signup page's current state.
4. **Exact JSON field names/shape for logprobs on Ollama's native `/api/generate` endpoint.** Confirmed the *capability* exists (issue #16117 references it via #13497) but did not fetch Ollama's own `/api/generate` reference docs to quote the exact response schema.
5. **mlx-lm server's exact logprobs request/response schema and any max `top_logprobs`-equivalent value**, and whether it matches OpenAI's shape or diverges (as llama.cpp's does). Found only that logprobs is a listed feature, via a secondary summary, not a fetched primary doc.
6. **Apple's Foundation Models framework: any private/undocumented probability signal.** Public API surface confirmed to expose no logprobs; cannot rule out that some other internal signal exists that Apple simply hasn't documented for developers — absence of public API is not proof of absence of the underlying capability inside the framework.
7. **A verified, apples-to-apples latency benchmark for "20 parallel single-token logprobs calls" on any of: gpt-4o-mini, gpt-4.1-nano, Groq (moot — logprobs unsupported), or local Ollama/llama.cpp on M-series Mac.** All numbers given in section 6e for these specific configurations are estimates/extrapolations from adjacent data (openjev's CUDA numbers, jev-voice's hosted-Jev numbers), not directly measured.
8. **Whether a dedicated "browser-use ultrafast" blog post exists separate from the jev-ultrafast GitHub README.** Only the repo itself and a third-party guide (agentbreaking.com) were found.
9. **The general-form confidence formula** `(n·p_max − 1)/(n−1)` for TypeSafe's Choice questions with n≠3 options — only the n=3 case, `(3·p_max − 1)/2`, was directly quoted from `docs.typesafe.ai/confidence`; the generalization is my own algebra, not a quoted TypeSafe statement, and TypeSafe may use a different formula for other option counts or for Score questions.
10. **Direct confirmation that GPT-4o/4.1/GPT-5-family (non-reasoning) models currently support Chat Completions `logprobs`** by name in 2026 — inferred from the reasoning-model exclusion and general precedent, not a positive documentation quote naming each current model.
