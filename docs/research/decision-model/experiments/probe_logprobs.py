"""Can a local model give a real distribution over an offered closed set, jev-style?
Uses brain.py's real ACTIONS criteria. Single-token labels, max_tokens=1, read logprobs."""
import pathlib
import json, sys, time, string
import httpx
sys.path.insert(0, str(pathlib.Path.home() / "Desktop/SoftwareDevProjects/jev-voice"))
from jev_voice.brain import ACTIONS  # noqa: E402

LABELS = list(string.ascii_uppercase[: len(ACTIONS)])
KEYS = list(ACTIONS)
MENU = "\n".join(f"{l}. {k}: {ACTIONS[k]}" for l, k in zip(LABELS, KEYS))
SYSTEM = ("You classify a voice command spoken to a Mac. Answer with exactly one capital letter "
          "from the menu and nothing else.\n\n" + MENU)

UTTS = [
    "open chrome",
    "search youtube for lofi hip hop",
    "type hello world and hit enter",
    "scroll down a lot",
    "turn it up",
    "what time is dinner tonight",
    "find the cheapest flight to london on google flights",
    "close this tab",
    "empty the trash",
    "abre safari",
]

def ask_ollama_native(utt: str, model: str):
    body = {"model": model, "stream": False, "think": False,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": f"utterance: {utt}"}],
            "options": {"num_predict": 1, "temperature": 0, "top_k": 100, "top_p": 1, "min_p": 0},
            "logprobs": True, "top_logprobs": 20}
    t0 = time.perf_counter()
    r = httpx.post("http://127.0.0.1:11434/api/chat", json=body, timeout=180)
    ms = int((time.perf_counter() - t0) * 1000)
    r.raise_for_status()
    return r.json(), ms

def ask_openai_compat(utt: str, model: str, base="http://127.0.0.1:11434/v1"):
    body = {"model": model, "max_tokens": 1, "temperature": 0, "logprobs": True, "top_logprobs": 20,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": f"utterance: {utt}"}],
            "chat_template_kwargs": {"enable_thinking": False}}
    t0 = time.perf_counter()
    r = httpx.post(f"{base}/chat/completions", json=body, timeout=180)
    ms = int((time.perf_counter() - t0) * 1000)
    r.raise_for_status()
    return r.json(), ms

def dist_from_top(top: list[dict]) -> dict[str, float]:
    import math
    raw = {}
    for t in top:
        tok = (t.get("token") or "").strip()
        if tok in LABELS:
            raw[tok] = raw.get(tok, 0.0) + math.exp(t["logprob"])
    z = sum(raw.values()) or 1.0
    return {KEYS[LABELS.index(k)]: v / z for k, v in sorted(raw.items(), key=lambda kv: -kv[1])}, sum(raw.values())

if __name__ == "__main__":
    mode, model = sys.argv[1], sys.argv[2]
    base = sys.argv[3] if len(sys.argv) > 3 else None
    for u in UTTS:
        try:
            if mode == "native":
                data, ms = ask_ollama_native(u, model)
                msg = data["message"]
                top = None
                # ollama native: logprobs may live in message.logprobs or top-level
                lp = data.get("logprobs") or msg.get("logprobs")
                if lp:
                    first = lp[0] if isinstance(lp, list) else lp
                    top = first.get("top_logprobs") or []
                content = msg.get("content")
            else:
                data, ms = ask_openai_compat(u, model, base) if base else ask_openai_compat(u, model)
                ch = data["choices"][0]
                content = ch["message"]["content"]
                lp = ch.get("logprobs")
                top = (lp["content"][0]["top_logprobs"] if lp and lp.get("content") else None)
            if top is None:
                print(f"{u!r:58} {ms:5}ms  content={content!r}  NO LOGPROBS IN RESPONSE"); continue
            d, mass = dist_from_top(top)
            best = next(iter(d.items())) if d else ("?", 0)
            rest = ", ".join(f"{k}={v:.2f}" for k, v in list(d.items())[1:4])
            print(f"{u!r:58} {ms:5}ms  -> {best[0]:13} p={best[1]:.2f}  mass_on_labels={mass:.2f}  next: {rest}")
        except Exception as e:
            print(f"{u!r:58} ERROR {type(e).__name__}: {str(e)[:200]}")
