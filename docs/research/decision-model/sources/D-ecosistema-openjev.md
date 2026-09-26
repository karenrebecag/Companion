# OpenJev ecosystem survey — Sept 2026

Context: TypeSafe Jev (`POST api.typesafe.ai/v1/systemone`) launched 2026-09-15. Survey covers the six requested repos plus the wider ecosystem (Laya, typed-decisions benchmark, qwen-rlcd, jevmlx) for a Swift 6 / Apple Silicon (M4 Max, 36 GB) offline voice-app use case.

All GitHub metadata (stars/forks/license/dates) below is [verified] via `api.github.com/repos/<owner>/<repo>` on 2026-09-22. All technical/README content is [verified] via raw README fetch unless marked [inferred].

---

## 1. `2bbb/openjev` — "Can we run something like Jev on a 3090 at home?"

- **README**: https://raw.githubusercontent.com/2bbb/openjev/master/README.md
- **What it is**: a personal reproduction asking whether a 3090-class card can do Jev-style typed inference. [verified]
- **Technique**: prefill-only logit reading — "typed option probabilities directly from a model. No answer sentence, JSON repair, or decoding loop" — single forward pass, no autoregressive decode. [verified]
- **Base model**: Qwen3.5-4B, BF16 (4B params); browser build quantized to Q4_K_M GGUF, 3.01 GB download. [verified]
- **Probability production**: one forward pass reads logits at the declared option-token positions ("Unstructured state → 4B model ← Runtime criteria ← Typed options → native option logits → Probabilities"). [verified]
- **Calibration claims**: balanced accuracy 0.845 on a "TypeSafe subset" vs. published Jev 0.883; 0.813 on authored decisions; 0.637 on WANLI. **No ECE/Brier reported.** [verified] URL: https://raw.githubusercontent.com/2bbb/openjev/master/README.md
- **Wire protocol**: not documented as Jev-compatible; input is a custom JSON (`id`, `state`, `question`, `options` array). choice/noul/score support **not stated**. [verified — absence noted]
- **>N options / multi-token**: not addressed in README; single-token-per-option logit read implied by the "native option logits" design, so likely inherits the ~50-option single-token ceiling. [inferred]
- **Fan-out**: "serial prefix reuse" → 10.75 decisions/s; "parallel suffixes" → 20.03 decisions/s vs. 2.33 decisions/s for fresh (uncached) scoring. [verified]
- **Latency/hardware**: 1.023 s median for 21 binary criteria on an RTX 3090 (direct logits) vs. 5.332 s for an autoregressive baseline. [verified]
- **Runtime**: PyTorch, Python 3.10+, CUDA, GPU that can hold a 4B BF16 model; a browser build uses WebGPU. **No native Apple Silicon path** (WebGPU-in-browser could technically run on a Mac browser, but that's not MLX/Metal). [verified]
- **License**: MIT. [verified via API]
- **Maturity**: 0 stars, 0 forks, created 2026-09-18, pushed same day (single-day burst), open issues 0. [verified via API] — essentially a weekend proof-of-concept, not maintained.

---

## 2. `ekzhang/openjev-sglang` — "Jev-compatible API endpoint based on open models (prefill-only)"

- **README**: https://raw.githubusercontent.com/ekzhang/openjev-sglang/main/README.md
- **What it is**: a server that implements the TypeSafe/Jev HTTP API on top of SGLang. [verified]
- **Technique**: prefill-only, candidate-suffix scoring — "N+1 one-token calls" per request: tokenize the shared prefix once (cache warming), then concurrently evaluate each question's answer-label suffix with `max_new_tokens=1`, requesting only the label logprobs. [verified]
- **Base model**: `Qwen/Qwen3.6-35B-A3B` (35B, MoE-style "A3B" active-param naming), served via NVIDIA's `nvidia/Qwen3.6-35B-A3B-NVFP4` quantization. [verified]
- **Probability production**: renormalizes the requested label logprobs with a stable softmax, temperature default 1.0; confidence = `1 − H(p)/log(K)`, clamped [0,1]. [verified]
- **Calibration claims**: **explicitly none** — "Probabilities are conditioned on the supplied options, depend on prompt and label ordering, and are not calibrated estimates of correctness." [verified]
- **Wire protocol**: implements all three Jev types — **noul** (returns `P(yes)`), **choice** (argmax + full distribution), **score** (`sum(level_index * probability)`). [verified]
- **>N options / multi-token**: hard cap of **64 answers per question**, single-token labels `A`–`Z` then `AA`, `AB`… (i.e., a base-26 multi-char but still single-*token*-per-label scheme); "all 64 labels are checked against the actual tokenizer at startup" to guarantee one-token readout. No full-candidate-string scoring — it's the same single-token-label trick as your qwen3:4b test, just extended past 52 via two-letter labels. [verified]
- **Fan-out**: SGLang radix-cache reuse (opportunistic, non-pinned per-request KV); defaults 16 simultaneous evaluations, 64 concurrent backend calls. [verified]
- **Latency/hardware**: no explicit numbers in README; deployed "one B200 per container" on SGLang 0.5.19 with a Rust frontend and "breakable prefill CUDA graphs." [verified — absence of numbers noted]
- **Runtime**: SGLang 0.5.19 + FastAPI/uvloop, deployable on Modal with scale-to-zero after 5 idle minutes. **No Apple Silicon support mentioned** — SGLang has no Metal/MLX backend. [verified]
- **License**: not disclosed in README content fetched. [verified — absence noted] (GitHub API also returned `license: None`, i.e. no SPDX-detected license file.) [verified via API]
- **Maturity**: 266 stars, 33 forks, created 2026-09-17, last push 2026-09-21, 2 open issues. Actively watched, moderately active. [verified via API]

---

## 3. `razorback16/openjev` — "Open, Jev-compatible System One decision server on DiffusionGemma"

- **README**: https://raw.githubusercontent.com/razorback16/openjev/main/README.md
- **What it is**: "an open-source 'System One' decision server" — state + typed questions → probabilities + confidence. [verified]
- **Technique**: **not prefill-of-an-autoregressive-model** — it's a *discrete diffusion, masked-canvas, non-autoregressive* read: "It builds a canvas where the only masked tokens are the answer slots, one token per question... The model never writes into those slots. One read-only pass returns the probability distribution over each slot, and that distribution **is** the answer." [verified]
- **Base model**: DiffusionGemma 26B-A4B-it-NVFP4 (Apache-2.0, NVIDIA/Google), served via two backends (vLLM and MLX). [verified]
- **Probability production**: direct read of the logit distribution at each masked answer slot; confidence = `1 − H(p)/ln(K)`. [verified]
- **Calibration claims**: claims to be "calibrated" but **no ECE/Brier numbers given**. [verified — absence noted]
- **Wire protocol**: explicitly Jev-compatible — "OpenJev speaks the same wire API as TypeSafe's Jev, so their SDKs work against it unchanged." Implements noul/choice/score with the same field names TypeSafe uses. [verified]
- **>N options / multi-token**: choice capped at **128 options** ("Jev allows 255"); still single-token-per-answer-slot, so no full-string candidate scoring. On uncertainty (entropy > 0.1) it re-reads with fresh noise up to 4× and averages — a diffusion-specific self-consistency trick with no analog in autoregressive prefill scoring. Batches ~12 questions per read, in parallel. [verified]
- **Latency/hardware — vLLM (RTX PRO 6000, 38% GPU util, 3 Q/request, cache-busted states)**: concurrency 1 → 10.7 req/s, p50 94 ms, p95 94 ms; concurrency 64 → 57.4 req/s, p50 760 ms, p95 1109 ms. [verified]
- **Latency/hardware — MLX (Apple Silicon)**: "a 3-question request takes about 0.2–0.4 s on an M3 Ultra and about 0.39 s on an M4 Max"; 16 concurrent requests sustain ~4 req/s. [verified] — **This is the only repo of the six with a directly reported M4 Max number**, matching the reader's own hardware.
- **Runtime**: vLLM (NVIDIA, 24GB+ VRAM) or **MLX** (Apple Silicon, 16GB free memory needed); both serve an OpenAI-compatible `/v1/chat/completions` surface. `OPENJEV_BACKEND=mlx` runs the model in-process on a Mac with no vLLM/Docker. [verified]
- **License**: Apache-2.0 (project) + Apache-2.0 weights. [verified via API and README]
- **Maturity**: 305 stars, 24 forks, created 2026-09-18, pushed 2026-09-21, 3 open issues; README notes it depends on an unmerged upstream vLLM PR (`vllm-project/vllm#57250`), i.e. some functionality may require a patched vLLM. [verified via API + README]

---

## 4. `Heman10x-NGU/openJev-verdict-2.0` — "Calibrated 151M Non-Autoregressive Decision Engine beating TypeSafe Jev & Laya"

- **README**: https://raw.githubusercontent.com/Heman10x-NGU/openJev-verdict-2.0/main/README.md
- **What it is**: a **from-scratch trained** 149.6M-param model, not a wrapper around a chat LLM — the closest thing here to "a tiny dedicated decision model." [verified]
- **Technique**: **non-autoregressive, trained classifier head** on a ModernBERT-base backbone with "dual-channel calibration": a distribution head (soft-label matching) decoupled from a confidence head (binary-correctness-optimized), trained with "Symmetric Permutation-KL" to reduce option-order bias, and NLI-style templating ("It is {description}") for multi-token candidate descriptions — i.e. this is the one design that scores full candidate *strings*, not single tokens. [verified]
- **Base/size**: ModernBERT-base-derived, 149.6M params total. [verified]
- **Probability production**: marker-pointer logits from a single non-autoregressive forward pass; distribution head → soft probabilities, confidence head → separate calibrated confidence. [verified]
- **Calibration claims (on `LocalLLaMA/typed-decisions`, 2,000 held-out decisions across financial/security/support/agent-trace domains)**: **Top-1 accuracy 77.10%** (vs. Laya 76.60%, Jev 72.70%); **Brier (soft) 0.0636** (best of the three); **ECE (confidence head) 0.0144**; a separate figure of **0.1513 ECE on the distribution head** is also given (dual-head design trades these off). Also: on 2,918 perturbed test decisions, flip rate 4.76% vs. "Kev's" 7.41% (likely a typo for Jev). [verified] URL: https://raw.githubusercontent.com/Heman10x-NGU/openJev-verdict-2.0/main/README.md
- **Wire protocol**: inherits Jev's three schema types (Choice/Score/Noul) conceptually but **no explicit REST/gRPC wire-format spec given** in the README content fetched. [verified — absence noted]
- **>N options / multi-token**: README explicitly calls out fixing "the 5-option scope restriction" that "limited calibration exclusively to 5-candidate queries" — it now "scales across all supported candidate counts," and multi-token candidates are handled via the NLI-templating approach above, not single-token labels. [verified]
- **Latency**: ~20–25 ms per decision (single pass); training took 8.8 hours on a single GTX 1660 Ti (6 GB VRAM). [verified]
- **Runtime/hardware**: consumer-GPU trainable/runnable; also runs client-side in-browser via WebGPU at ~600 MB model size. **No explicit Apple Silicon (MLX/Metal) claim**, but a 150M encoder-style model is small enough that an MLX or Core ML port is plausible. [inferred]
- **License**: Apache 2.0 per README text, but GitHub API reports `license: NOASSERTION` (no machine-detected SPDX license file at repo root) — flag this **discrepancy** before relying on it. [verified via API, contradicts README text]
- **Maturity**: 264 stars, 38 forks, created 2026-09-19, pushed 2026-09-20 (short, intense burst), 2 open issues. [verified via API] — no test-suite/CI claims found in the fetched README content.

---

## 5. `SiliconLabAI/OpenJev`

- **Page fetched**: https://github.com/SiliconLabAI/OpenJev
- **What it is**: "Open source System One–style decision playground" — a UI + API offering **three interchangeable backends**, useful as a comparison harness more than a single technique. [verified]
- **Backends/techniques**:
  1. **Parallel**: "LLM micro-scorers (one tiny `{p}` call per option, then softmax)" — i.e. N separate short generations per option, not a shared-prefix logit read.
  2. **Oneshot**: single structured-JSON call to any OpenAI-compatible chat model (classic prompt-a-JSON-schema approach, most failure-prone of the three).
  3. **Decider**: wraps `Mapika/decider-2b`, described as "real System One weights (calibration-aware RL on v10)" — the only backend claiming actual RLCD-style training rather than being a scoring trick over a generic chat model. [verified]
- **Base model (decider backend)**: `Mapika/decider-2b`, a Qwen3.5 fine-tune, ~4 GB VRAM (CUDA). [verified]
- **Calibration claims**: "includes calibration-aware RL" for decider-2b v10; **no ECE/Brier numbers given**. [verified — absence noted]
- **Wire protocol**: implements TypeSafe's wire format, `POST /v1/systemone`, with choice/score/noul question types. [verified]
- **Latency**: **not given** in fetched content. [verified — absence noted]
- **Runtime**: Express.js + Vite server; decider backend needs CUDA (~4 GB VRAM); **no Apple Silicon mention** for any backend. [verified]
- **License**: MIT. [verified via API, matches README]
- **Maturity**: 92 stars, 21 forks, created 2026-09-20, pushed 2026-09-22 (still being pushed to today), 2 open issues, "6 commits on main" per fetched content. [verified via API + page] — youngest and least deeply built of the six, but still receiving commits as of today.

---

## 6. `zhihz/openjev` — "Local bilingual probability decisions from context, questions, and candidate answers"

- **README**: https://raw.githubusercontent.com/zhihz/openjev/main/README.md
- **What it is**: explicitly framed as independent, "not affiliated with, sponsored by, or endorsed by TypeSafe," and states it does **not** reproduce Jev's proprietary RLCD training — this is the most honest-about-its-limits of the six. [verified]
- **Technique**: prefill + single next-token logit read over the answer-label position, on a stock instruction-tuned autoregressive model — no candidate-suffix scoring, no trained classifier. Explicitly says "logit-derived scores are not automatically calibrated or superior to other scoring methods" and does **not** claim calibration. [verified]
- **Base model**: Qwen3-4B-Instruct-2507 (frozen, off-the-shelf — "not a newly trained Open JEV foundation model"). [verified]
- **Wire protocol**: custom, not stated as Jev-wire-compatible. Accepts `state`, `questions[]`, `type` ("Choice" and "Binary" only — **no explicit "score" type**), returns `choice`, `probabilities`, `elapsed_ms`, device info. Binary requires exactly 2 options + a `positive_id`. [verified]
- **Bilingual claim**: English ↔ 中文 without changing inputs/results; reading-evaluation cross-language accuracy: English→Chinese 32/32, Chinese→English 31/32, Chinese→Chinese 32/32 (small n, informal eval). [verified]
- **>N options / multi-token**: 2–8 candidates per question, hard limit 4,096 full prompt tokens per question including chat template. Multi-token candidates handled as natural-language descriptions (not single-token labels), but **no fan-out/shared-prefix optimization**: "Questions currently run sequentially and re-encode the context; shared-context computation is planned, not delivered." API cap 100 questions, UI cap 16. [verified]
- **Latency/hardware (Apple M3, 16 GB)**: median of 8 requests = 533 ms (MLX 8-bit) vs. 558 ms (FP16 earlier); first/cold request up to 8,007 ms, 657 ms after an idle period; peak memory 4.60 GB (MLX) vs 8.35 GB (MPS). [verified]
- **Accuracy**: Qwen3-4B-Instruct-2507 FP16 scored 212/236 (89.8%) on its own eval; MLX 8-bit matched at 212/236 (89.8%) — i.e. quantization was lossless on their eval set. [verified]
- **Runtime**: **MLX**, Python 3.14, tested on Apple M3/16GB. [verified]
- **Apple Silicon**: explicitly the primary target — "Tested locally on Apple M3, 16 GB unified memory." [verified]
- **License**: Apache-2.0 (project code) + Qwen's own Apache-2.0 model license. GitHub API shows `license: NOASSERTION` (no SPDX file detected), same discrepancy pattern as repo #4 — treat README's license claim as unverified at the repo-metadata level. [verified via API, contradicts README text]
- **Maturity**: 30 stars, 3 forks, created 2026-09-16, single push 2026-09-16 (one-day project, no further commits since), 1 open issue. Self-labeled "Research preview." [verified via API] — smallest, least active of the six, but its README is unusually candid about the sequential-only bottleneck and lack of calibration claims.

---

## Wider ecosystem (searched, not in the original 6)

### `LocalLLaMA/typed-decisions` — the benchmark named by repo #4
- HF dataset page: https://huggingface.co/datasets/LocalLLaMA/typed-decisions — [verified] the fetched dataset card reports **1.6k total rows, 300 train / 100 test, with a primary "agent_trace_observability" subset of 400 rows**, covering 4 domains (customer_service, invoice_processing, security_incidents, agent_trace_observability) and question types spanning Choice (continue/human_review/observe/stop), Noul (needs-review true/false), and Score (risk/urgency, 0–3 scale). License Apache 2.0. [verified]
- **Conflicting counts**: a separate web summary (via search, not directly re-fetched from HF) states "1,200 training cases (6,000 decisions)... official 400-case test set (2,000 decisions)" — source: https://github.com/Heman10x-NGU/openJev-verdict-2.0 and https://github.com/bnsd55/jevmlx/pull/57. [inferred / could not fully reconcile] — likely "cases" vs. "rows" vs. "decisions" (each case yields multiple typed decisions across Choice/Noul/Score), but the exact row-to-decision multiplier could not be verified from the HF card content fetched. **Flagging as unresolved — re-check the HF dataset viewer directly if exact N matters.**
- **Reported leaderboard on this benchmark** (accuracy / Brier / ECE), collated from repos #4 and Laya's own materials:
  - TypeSafe Jev 1.13.0: **72.70%** accuracy, ~150 ms/~140–276 ms latency (two slightly different figures appear across sources — see below). Source: https://github.com/Heman10x-NGU/openJev-verdict-2.0
  - Laya (421.3M / 421M params): **76.60%** (repo #4's citation) or **0.766 / 76.6%** (Laya's own card) accuracy, ~31–39.5 ms latency. Sources: https://github.com/Heman10x-NGU/openJev-verdict-2.0, https://github.com/NandhaKishorM/laya
  - openJev-verdict-2.0 (149.6M): **77.10%** accuracy, 0.0636 Brier, 0.0144 ECE, ~20–25 ms latency. Source: https://github.com/Heman10x-NGU/openJev-verdict-2.0
  - A web-search synthesis (not independently re-verified) additionally cites "Laya achieved 0.789 Accuracy... surpassing the benchmark's Teacher Self-Agreement ceiling (0.735)" — this 0.789 figure **conflicts** with Laya's own card figure of 0.766 cited elsewhere; both trace back to search-engine summaries rather than a single primary source re-fetched here. **Could not fully reconcile — treat the 76.6% figure (repeated in two independently fetched primary READMEs) as the better-supported one.**

### Laya — `NandhaKishorM/laya` (the named "Jev competitor")
- https://github.com/NandhaKishorM/laya — [verified via WebFetch + GitHub API]
- Non-autoregressive System-1 decision engine, RLCD-trained (reinforcement learning against strictly-proper scoring rules) with a language/script router dispatching to per-language checkpoints.
- Three checkpoints: `laya` (English, ModernBERT-large, 421M, 512 ctx), `laya-multilingual` (100+ languages, mmBERT-base, 322M, 1024 ctx), `laya-typed-decisions` (ModernBERT-large, 421M, 1024 ctx).
- Calibration: ECE 0.081 (English, post temperature-scaling), 0.106 (multilingual); Brier 0.062 (typed-decisions); accuracy 0.766 (typed-decisions), 0.783 (MASSIVE intent, English).
- Latency: 32.8–39.5 ms/question on a T4 GPU; 7.2 ms/question batched (10 Q).
- **No stated Jev wire-protocol compatibility** — different API/architecture; author's blog framing pitches it as "7.8× faster" (32.8 ms vs Jev's 236–276 ms) — note the latency-comparison numbers vary across sources (150 ms in repo #4's table vs 236–276 ms in the Laya-vs-Jev blog posts found by search). [verified for Laya's own numbers; Jev's own latency figure is inconsistent across secondary sources and **could not be pinned to one canonical number**]
- Key documented weakness: on Banking77 (77 intent labels), Jev scored 0.870 vs Laya's 0.425 — "Laya shares a fixed token budget across all candidate options, so past about 20 choices each option gets only a few tokens of representation" — i.e. Laya's architecture degrades hard on many-option problems, unlike single-token-logit approaches. [inferred from search-summarized blog content, not independently re-fetched from a primary blog URL]
- License Apache-2.0. **Maturity: 15,397 stars, 1,269 forks** (verified via GitHub API), created 2026-09-18 — extremely fast adoption, by far the most starred item in this whole survey.
- **No Apple Silicon / MLX / llama.cpp mention** in the fetched content — it's a BERT-style encoder classifier, so an MLX or Core ML port is architecturally straightforward but not shipped. [inferred]

### `qwen-rlcd` — `shamazharikh/qwen-rlcd`
- https://github.com/shamazharikh/qwen-rlcd — [verified via WebFetch + GitHub API]
- A **prototype**, not a finished tool: "Jev-style calibrated decision model (Choice/Score/Noul) on Qwen3.5-0.8B." Technique: prefill state once, cache KV, duplicate cache per branch, run each Q/A pair as an isolated right-padded sequence, read hidden states at branch end for logits — built specifically to handle Qwen3.5's **hybrid linear/full-attention architecture** (18 linear-attention + 6 full-attention layers) where naive tree-attention masking doesn't work cleanly.
- Three heads: Choice (softmax over final answer-branch token), Score (softmax over ordered levels, expected value = Σp_i·i), Noul (sigmoid).
- Calibration: post-hoc temperature scaling per (question_type, K-bucket); claims RLCD training would give calibration but this repo is **inference-only, no trained weights published**.
- Latency: benchmarks were run on Mac CPU (fp32/torch fallback) only — no GPU numbers (Colab OOM'd during kernel compilation). No Apple-Silicon-optimized (MLX/Metal) path — just generic CPU fallback on a Mac.
- License not specified. Maturity (verified via API): 4 stars, 1 fork, created 2026-09-16, pushed 2026-09-17 — early/stalled, "M0 complete, M1–M2 on hold."
- Separate GitHub issue thread exists comparing it to Laya: https://github.com/shamazharikh/qwen-rlcd/issues/3 (title only found via search, content not fetched). [could not verify contents]

### `jevmlx` — `bnsd55/jevmlx` (most directly relevant to the Swift/Apple-Silicon build)
- https://github.com/bnsd55/jevmlx — [verified via WebFetch + GitHub API]
- Not one of the 6 named repos but the closest thing found to "Jev on Apple Silicon as a reusable component": turns a field schema (booleans, enums, multi-selects) + context string into a single batched forward pass on a local **MLX** model, restricted softmax over each field's legal continuations — same core idea as the reader's own qwen3:4b prefill+logprobs test, generalized into a library/server.
- Models: MLX-Community quantized Qwen2.5 — `quality`=7B-Instruct-4bit (default), `fast`=3B-Instruct-4bit, `test`=1.5B-Instruct-4bit.
- Latency: ~0.6 s/decision (labeled scorer) on a Mac Studio M5 Max.
- Both a Python library (`decide()`) and an HTTP server (`jevmlx serve`, `/decide` endpoint); has a TypeScript client in-repo.
- License MIT. Maturity: 57 stars, 8 forks, 549 commits, created 2026-09-17, still pushed to today (2026-09-22) — by commit count, the most actively engineered of everything surveyed here, though it predates/parallels rather than directly imitates Jev's wire format.

### Hacker News threads (titles only, via search — not fetched individually)
- "What's a 'Jev'?" — https://news.ycombinator.com/item?id=49753358
- "Introducing System One Models and Jev" (original launch thread) — https://news.ycombinator.com/item?id=49717558
- "Open-jev: One-pass option scoring with Gemma 3 4B, similar to jev" — https://news.ycombinator.com/item?id=49737236 (note: this is a *different* Gemma-3-4B-based "open-jev" not in the 6 surveyed here — comment thread claims "Open-sourced jev architecture last year with model, paper and dataset," i.e. a claim of prior art predating TypeSafe's launch — https://news.ycombinator.com/item?id=49736660)
- "OpenJev" (likely discussing one of razorback16 or 2bbb's repos, ambiguous from title alone) — https://news.ycombinator.com/item?id=49752041
- "Reverse-engineered Jev-like model" — https://news.ycombinator.com/item?id=49731282
- [could not verify] — none of these threads' bodies/comments were individually fetched; titles and snippet text only, from search results.

---

## Synthesis

### (a) Most portable approach to a Swift 6 macOS app on Apple Silicon

Three real options surfaced, in order of directness for your setup:

1. **Do it yourself, in-process, exactly what you already prototyped** — single-token label + assistant prefill + logprobs on a small Qwen model via MLX-Swift (or llama.cpp's C API via a Swift wrapper). Two repos independently validate this exact pattern on Apple Silicon:
   - `zhihz/openjev` (repo #6) ran the *identical* trick — prefill + single next-token logit read, Qwen3-4B-Instruct-2507, MLX — and measured 533 ms median on an **M3, 16GB** for a full request (this includes their sequential/no-shared-prefix overhead, not just the per-question read — your own 30–60 ms/question with cached prefix is faster because you're not re-encoding context per call). https://raw.githubusercontent.com/zhihz/openjev/main/README.md
   - `bnsd55/jevmlx` generalizes the same idea into a reusable MLX library/server with a restricted-softmax scorer, ~0.6 s/decision on an M5 Max with a 7B model (larger model than yours, so slower per-call is expected). https://github.com/bnsd55/jevmlx
   - `razorback16/openjev` (repo #3) is the only one of the six with **native MLX + a reported M4 Max number**: ~0.39 s for a 3-question request — but that's a 26B diffusion model, an order of magnitude bigger than what you're running, and it's a sidecar HTTP server, not an in-process library. https://raw.githubusercontent.com/razorback16/openjev/main/README.md
   - **Conclusion**: nothing here beats what you've already built. MLX-Swift in-process (no sidecar, no HTTP round trip) is the most portable path for a native macOS voice app — you'd be porting your own qwen3:4b prefill+logprobs recipe to MLX-Swift or wrapping llama.cpp's logprobs API from Swift, not adopting any of these six repos wholesale. The one thing worth stealing from `razorback16` and `ekzhang/openjev-sglang` is the **wire-protocol shape** (noul/choice/score JSON with a confidence = `1 − H(p)/log K` field) if you want your local decision layer to be swappable with a future Jev-compatible server.
2. **A local sidecar server** (razorback16/openjev in MLX mode, or jevmlx) is viable if you want the decision engine as a separate process/language (e.g. to share it across multiple apps, or keep model-loading out of your Swift binary), but adds IPC latency and a second runtime to manage — not needed for a single voice app that already has Ollama/llama.cpp resident.
3. **A trained classifier head (Laya-style, or repo #4's 150M model)** would need a genuine Core ML / MLX port of a BERT-family encoder — architecturally easy (small, non-autoregressive, no KV cache/attention-mask tricks needed) but **no such port exists in anything surveyed here**; you'd be building it yourself. See (c).

### (b) What `typed-decisions` says about calibration of prefill+logprobs on small open models vs. Jev

- The benchmark (https://huggingface.co/datasets/LocalLLaMA/typed-decisions) is a 4-domain synthetic-labeled set (customer_service, invoice_processing, security_incidents, agent_trace_observability) with Choice/Noul/Score questions, Apache-2.0, with the exact row/decision count unresolved (see discrepancy note above — 1.6k rows per the HF card I fetched vs. "1,200 train cases / 6,000 decisions, 400 test cases / 2,000 decisions" per search-summarized secondary sources).
- On this benchmark, **generic prefill+logprobs on Jev itself (the closed baseline) only gets 72.70% accuracy** — i.e. even TypeSafe's own production RLCD-trained model isn't near-perfect on this set. https://github.com/Heman10x-NGU/openJev-verdict-2.0
- **A dedicated small trained model (Laya, 421M, or openJev-verdict-2.0, 150M) modestly beats plain-prefill Jev on accuracy (76.6–77.1% vs 72.7%) and clearly wins on calibration** — the 150M model reports ECE 0.0144 (confidence head) and Brier 0.0636, both explicitly "best of the three" per its own README, though note the dual-head design also reports a much worse 0.1513 ECE on the raw distribution head, so "which number is the real calibration score" depends on which head you read.
- **None of the six repos that just wrap a chat model in prefill-mode (2bbb, ekzhang, zhihz, SiliconLabAI's parallel/oneshot backends) report calibration numbers at all** — several explicitly disclaim calibration ("not calibrated estimates of correctness," `ekzhang/openjev-sglang`; "not automatically calibrated," `zhihz/openjev`). This is the load-bearing fact for your design: **raw prefill+logprobs on an off-the-shelf instruct model (what you're doing with qwen3:4b) gives you a probability-shaped number, but nobody in this ecosystem is claiming it's a calibrated probability** — only the two purpose-trained models (Laya, verdict-2.0) make that claim, and only against this one synthetic benchmark, which itself shows even the "gold standard" (Jev) topping out at 72.7%.
- Practically: your 0.95–0.99 mass on the correct single-token label for clean binary/small-enum choices is a *sharpness* measure (how peaked the distribution is), not evidence of *calibration* (whether 0.97 confidence corresponds to 97% correctness in the long run) — the ecosystem's ECE numbers are the thing you don't have for your own setup, and getting one would require building your own held-out labeled set of voice-command decisions and checking accuracy-vs-confidence buckets.

### (c) Is a tiny dedicated decision model (~150M) a credible path, and what would training one take?

Yes, and openJev-verdict-2.0 is a concrete existence proof: **149.6M params, ModernBERT-base backbone, trained in 8.8 hours on a single GTX 1660 Ti (6GB VRAM)**, beating a 4B-parameter-class autoregressive baseline (Jev) on accuracy and by a wide margin on calibration, on a real (if small/synthetic) benchmark. https://github.com/Heman10x-NGU/openJev-verdict-2.0

For a voice-command domain specifically, what it would take, based on what's documented across these repos:
1. **A backbone**: ModernBERT-base (149M, what repo #4 used) or a smaller/faster encoder if latency matters more than the ~20–25 ms it already reports — for voice commands with a small fixed vocabulary of intents, something even smaller (DistilBERT-scale, or a custom tiny transformer) is plausible, trading some accuracy for lower latency and easier MLX/Core ML porting.
2. **A dual-head design** (distribution head + separate confidence head, per repo #4) if you want both "which command" and "how sure am I" as independently calibrated signals — directly useful for a voice UI that needs to decide whether to act or ask for confirmation.
3. **Domain data**: you'd need a labeled set of (context/state, typed question, candidate answers, true answer, ideally soft/ensemble labels) for your actual voice-command space — the repos here all lean on either a shared benchmark (typed-decisions) or synthetic/ensemble-generated labels rather than large human-annotated sets, suggesting a bootstrap approach (generate candidate labels with your existing qwen3:4b or qwen3.6:27b, then train the tiny model to match/calibrate against that) is a realistic, low-cost path — not unlike what "Symmetric Permutation-KL" training and RLCD training are both doing (learning to match a stronger teacher's soft distribution rather than hard labels).
4. **Multi-token candidates**: repo #4's NLI-templating trick ("It is {description}") is the one documented way to score full candidate *strings* rather than being capped at single-token labels — relevant if your voice commands don't reduce cleanly to a short enum letter.
5. **Porting to Apple Silicon**: none of Laya or verdict-2.0 ship an MLX/Core ML build; both are small, non-autoregressive, encoder-only architectures, which is the *easiest* class of model to convert (via `coremltools` or MLX's `transformers` conversion path) compared to porting an autoregressive decoder with KV-cache logic — this is real but unstarted work in this ecosystem, and would be a genuine contribution, not a reproduction.
6. **Trade-off vs. your current approach**: your qwen3:4b prefill+logprobs setup already gets you 0.95–0.99 mass at 30–60 ms once cached, using models you already have installed, no training pipeline, no new artifact to maintain. A trained 150M model would only clearly beat that if you need (i) genuine calibration guarantees (not just sharp distributions), (ii) sub-20ms decisions without KV-cache-prefix tricks, or (iii) scoring full multi-token candidate phrases rather than single-token labels. For a first version, the existing recipe is very likely good enough; the trained-model path is the credible *next* step if calibration or full-string scoring becomes a real requirement.

---

## Could not verify

- Exact row/decision count for `LocalLLaMA/typed-decisions` — HF card fetch says 1.6k rows (300 train/100 test, 400-row primary subset); search-summarized secondary sources say 1,200 train cases (6,000 decisions) / 400 test cases (2,000 decisions). Not reconciled — recommend opening the HF dataset viewer directly if exact N is load-bearing.
- Laya's accuracy on typed-decisions: 0.766 (fetched from Laya's own GitHub README) vs. 0.789 (a web-search-engine synthesis claim, not independently re-fetched from a primary source) — treat 0.766 as better-supported since it's corroborated independently by `Heman10x-NGU/openJev-verdict-2.0`'s README (76.60%).
- TypeSafe Jev's own canonical latency figure — sources disagree: ~150 ms (repo #4's comparison table) vs. 236–276 ms (Laya-vs-Jev blog posts found via search, not fetched directly) vs. your own ~250ms figure given in the task context. Likely different measurement conditions (batch size, question count, network vs. local) across sources, not a single canonical number.
- `2bbb/openjev`'s and `SiliconLabAI/OpenJev`'s exact choice/noul/score wire-format support — README content fetched did not confirm or deny full three-type support explicitly for either.
- Content/comments of the Hacker News threads listed above — only titles/snippets came back from search; none were individually fetched.
- Content of `shamazharikh/qwen-rlcd`'s issue #3 ("Comparison with Laya and other open-weight Jev alternative?") — found via search title only, not fetched.
- Whether any repo here has an actual automated test suite — none of the fetched READMEs described CI/test coverage in detail beyond `razorback16`'s mention of pinning an unmerged vLLM PR and `bnsd55/jevmlx`'s mention of "CI/build pipelines" (not itself independently verified beyond the README's own claim).
- Full contents of `daseinlabs/open-jev` ("Open Jev implementation with custom finetuning") and the Gemma-3-4B-based "open-jev" referenced in HN thread 49737236 — surfaced by search but out of the requested scope, not fetched.
