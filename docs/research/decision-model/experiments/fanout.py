"""A local stand-in for api.typesafe.ai/v1/systemone, driven by jev-voice's REAL questions.

For every question: single-token labels + assistant prefill + logprobs -> a distribution over
the offered ids. Answers are returned in Jev's wire shape and fed to brain._to_plan to get a
full Plan with min-confidence composition. Measures the 20-question fan-out sequential vs
concurrent. Confidence = (n*p_max - 1)/(n - 1), the generalisation of docs.typesafe.ai/confidence.
"""
import math, string, sys, time, json
from concurrent.futures import ThreadPoolExecutor
import httpx
sys.path.insert(0, "/Users/karenrebecaog/Desktop/SoftwareDevProjects/jev-voice")
from jev_voice import brain, actions  # noqa: E402

LABELS = list(string.ascii_uppercase + string.ascii_lowercase)  # 52 single-token labels
OLLAMA = "http://127.0.0.1:11434/api/chat"
CLIENT = httpx.Client(timeout=300)

def render_state(state: dict) -> str:
    return "State:\n" + json.dumps(state, ensure_ascii=False, indent=0)

def render_question(q: dict, ids: list[str]) -> str:
    lines = [f"Question: {q['instructions']}", "Options:"]
    for lab, i in zip(LABELS, ids):
        desc = q["criteria"][i]
        lines.append(f"{lab}. {i}" + (f": {desc}" if isinstance(desc, str) else ""))
    lines.append("Answer with the single letter of the best option.")
    return "\n".join(lines)

def ask(model: str, state_txt: str, q: dict, order: list[str] | None = None) -> dict:
    ids = order or list(q["criteria"])
    if q["type"] == "noul":
        ids = ["true", "false"]
    ids = ids[: len(LABELS)]
    msgs = [{"role": "system", "content": state_txt},
            {"role": "user", "content": render_question(q, ids)},
            {"role": "assistant", "content": "Letter:"}]
    body = {"model": model, "stream": False, "think": False, "messages": msgs,
            "options": {"num_predict": 1, "temperature": 0}, "logprobs": True, "top_logprobs": 20}
    t0 = time.perf_counter()
    r = CLIENT.post(OLLAMA, json=body).json()
    ms = (time.perf_counter() - t0) * 1000
    lp = r.get("logprobs") or r["message"].get("logprobs") or []
    top = (lp[0] if lp else {}).get("top_logprobs", [])
    raw = {}
    for t in top:
        tok = t["token"].strip()
        if tok in LABELS[: len(ids)]:
            raw[ids[LABELS.index(tok)]] = raw.get(ids[LABELS.index(tok)], 0.0) + math.exp(t["logprob"])
    mass = sum(raw.values())
    probs = {i: raw.get(i, 0.0) / mass if mass else 1.0 / len(ids) for i in ids}
    if q["type"] == "noul":
        return {"noul": probs["true"], "_ms": ms, "_mass": mass}
    choice = max(probs, key=probs.get)
    n = len(ids)
    conf = (n * probs[choice] - 1) / (n - 1) if n > 1 else 1.0
    return {"choice": choice, "confidence": max(0.0, conf), "probabilities": probs, "_ms": ms, "_mass": mass}

def systemone(model: str, state: dict, questions: dict, concurrent: bool) -> tuple[dict, float]:
    st = render_state(state)
    t0 = time.perf_counter()
    if concurrent:
        with ThreadPoolExecutor(max_workers=8) as ex:
            answers = dict(zip(questions, ex.map(lambda k: ask(model, st, questions[k]), questions)))
    else:
        answers = {k: ask(model, st, q) for k, q in questions.items()}
    return answers, (time.perf_counter() - t0) * 1000

UTTS = ["open chrome", "search youtube for lofi hip hop", "type hello world and hit enter",
        "scroll down a lot", "turn it up", "what time is dinner tonight",
        "find the cheapest flight to london on google flights", "close this tab", "empty the trash",
        "open notes and type buy milk and press enter",
        "abre safari", "sube el volumen", "busca en youtube lofi hip hop",
        "escribe hola mundo y dale enter", "a que hora es la cena"]

if __name__ == "__main__":
    model = sys.argv[1]
    apps = actions.installed_apps()[:48]
    print(f"model={model}  apps offered={len(apps)}")
    print("\n== full 20-question fan-out per utterance -> real brain._to_plan ==")
    for u in UTTS:
        cands = brain.text_candidates(u)
        state = {"utterance": u, "frontmost_app": "Finder", "apps": apps, "candidates": cands}
        qs = brain.Brain._questions(None, cands, apps)
        answers, wall = systemone(model, state, qs, concurrent=True)
        plan = brain.Brain._to_plan(None, u, answers, cands, int(wall))
        addressed = answers["addressed"]["noul"]
        mass = min(a["_mass"] for a in answers.values())
        print(f"{u!r:52} {wall:6.0f}ms  {plan}  addressed={addressed:.2f} min_mass={mass:.2f}")
    print("\n== fan-out timing, same utterance: sequential vs concurrent (3 runs each) ==")
    u = UTTS[1]; cands = brain.text_candidates(u)
    state = {"utterance": u, "frontmost_app": "Finder", "apps": apps, "candidates": cands}
    qs = brain.Brain._questions(None, cands, apps)
    for conc in (False, True, False, True, False, True):
        _, wall = systemone(model, state, qs, concurrent=conc)
        print(f"  {'concurrent' if conc else 'sequential':10} {len(qs)} questions: {wall:6.0f} ms")
    print("\n== position bias: 'action' with reversed option order ==")
    for u in ["open chrome", "what time is dinner tonight", "close this tab", "turn it up"]:
        st = render_state({"utterance": u}); q = brain.Brain._questions(None, {}, apps)["action"]
        a = ask(model, st, q); b = ask(model, st, q, order=list(reversed(list(q["criteria"]))))
        print(f"  {u!r:32} fwd={a['choice']}({a['probabilities'][a['choice']]:.2f})  rev={b['choice']}({b['probabilities'][b['choice']]:.2f})")
