"""Does Ollama reuse the shared system-prompt prefix when only the utterance changes?"""
import sys, time, httpx
sys.path.insert(0, "/private/tmp/claude-501/-Users-karenrebecaog/87b23e78-f790-4f67-b2a2-b3b6f041e501/scratchpad")
from probe_logprobs import SYSTEM, UTTS, dist_from_top
model = sys.argv[1]
print(f"model={model}")
for u in UTTS[:8]:
    body = {"model": model, "stream": False, "think": False,
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": f"utterance: {u}"}],
            "options": {"num_predict": 1, "temperature": 0}, "logprobs": True, "top_logprobs": 20}
    t0 = time.perf_counter(); r = httpx.post("http://127.0.0.1:11434/api/chat", json=body, timeout=300).json(); wall = int((time.perf_counter()-t0)*1000)
    lp = r.get("logprobs") or r["message"].get("logprobs") or []
    top = (lp[0] if lp else {}).get("top_logprobs", [])
    d, mass = dist_from_top(top)
    best = next(iter(d.items())) if d else ("?", 0)
    print(f"{u!r:52} wall={wall:5}ms prompt_eval={r.get('prompt_eval_count'):4}tok/{r.get('prompt_eval_duration',0)//1e6:5.0f}ms  -> {best[0]:12} p={best[1]:.2f} mass={mass:.2f}")
