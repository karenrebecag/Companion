"""Cascade instead of speculative fan-out: action (fwd+rev averaged) -> only the heads that
action consumes. Apps are prefiltered in code (fuzzy) to <=6 before the model sees them."""
import difflib, re, sys, time
sys.path.insert(0, "/Users/karenrebecaog/Desktop/SoftwareDevProjects/jev-voice")
sys.path.insert(0, "/private/tmp/claude-501/-Users-karenrebecaog/87b23e78-f790-4f67-b2a2-b3b6f041e501/scratchpad")
from jev_voice import brain, actions  # noqa: E402
from fanout import UTTS, ask, render_state  # noqa: E402

NEEDS = {"open_app": ["app"], "open_website": ["site"], "web_search": ["engine", "text"], "type_text": ["text", "submit"],
         "new_item": ["new_kind", "has_title", "text"], "shortcut": ["shortcut"], "scroll": ["scroll_dir", "scroll_amount"],
         "volume": ["volume_op"], "media": ["media_op"], "open_folder": ["folder"], "system": ["system_op"], "task": [], "stop": [], "none": []}
IN_APP_ACTIONS = {"new_item", "shortcut", "type_text", "scroll"}

def app_candidates(utt: str, apps: list[str], k: int = 5) -> list[str]:
    words = re.findall(r"[a-záéíóúñ0-9]+", utt.lower())
    scored = []
    for a in apps:
        al = a.lower()
        s = max((difflib.SequenceMatcher(None, w, al).ratio() for w in words), default=0)
        if any(w in al for w in words if len(w) >= 3):
            s = max(s, 0.9)
        scored.append((s, a))
    return [a for s, a in sorted(scored, reverse=True)[:k] if s >= 0.5]

def averaged(model, st, q):
    order = list(q["criteria"]); a = ask(model, st, q); b = ask(model, st, q, order=list(reversed(order)))
    probs = {k: (a["probabilities"][k] + b["probabilities"][k]) / 2 for k in order}
    c = max(probs, key=probs.get); n = len(order)
    return {"choice": c, "confidence": max(0.0, (n * probs[c] - 1) / (n - 1)), "probabilities": probs, "_ms": a["_ms"] + b["_ms"], "_mass": min(a["_mass"], b["_mass"])}

def cascade(model: str, utt: str, apps: list[str]) -> tuple[brain.Plan, float, int, list[str]]:
    t0 = time.perf_counter(); calls = 0
    cands = brain.text_candidates(utt)
    apps_k = app_candidates(utt, apps)
    st = render_state({"utterance": utt, "frontmost_app": "Finder", "candidates": cands, "apps": apps_k})
    qs = brain.Brain._questions(None, cands, apps_k)
    answers = {}
    answers["action"] = averaged(model, st, qs["action"]); calls += 2
    act = answers["action"]["choice"]
    needed = list(NEEDS[act]) + (["in_app"] if act in IN_APP_ACTIONS else [])
    if act == "open_app" and not apps_k:
        answers["app"] = {"choice": "none", "confidence": 0.0, "probabilities": {"none": 1.0}}
        needed.remove("app")
    for k in needed:
        answers[k] = ask(model, st, qs[k]); calls += 1
    for k in qs:  # unused heads: neutral defaults so _to_plan can read them
        answers.setdefault(k, {"noul": 0.0} if qs[k]["type"] == "noul" else {"choice": "none", "confidence": 0.0, "probabilities": {}})
    wall = (time.perf_counter() - t0) * 1000
    return brain.Brain._to_plan(None, utt, answers, cands, int(wall)), wall, calls, apps_k

if __name__ == "__main__":
    model = sys.argv[1]; apps = actions.installed_apps()
    print(f"model={model}  installed apps={len(apps)}")
    tot = 0
    for u in UTTS + ["switch to slack", "open notes", "abre finder", "open my downloads folder", "mute"]:
        plan, wall, calls, apps_k = cascade(model, u, apps)
        tot += wall
        print(f"{u!r:52} {wall:5.0f}ms {calls}calls  {plan.action}({', '.join(f'{k}={v!r}' for k, v in plan.args.items() if k in ('app','site','engine','query','text','submit','shortcut','direction','op','folder','kind'))}) conf={plan.confidence:.2f}  apps={apps_k[:3]}")
    print(f"\nmean wall: {tot/ (len(UTTS)+5):.0f} ms")
