"""Layout B: every fixed menu lives in one cached system prefix; the per-request suffix is just
utterance + candidates + 'answer question K'. Also: app head with Chrome/Safari offered, and
fwd+rev order averaging for the action head."""
import pathlib
import math, string, sys, time, json
import httpx
sys.path.insert(0, str(pathlib.Path.home() / "Desktop/SoftwareDevProjects/jev-voice"))
sys.path.insert(0, "<scratchpad>")
from jev_voice import brain, actions  # noqa: E402
from fanout import LABELS, OLLAMA, CLIENT, UTTS, ask, render_state  # noqa: E402

def menu(key: str, q: dict, ids: list[str]) -> str:
    lines = [f"## question `{key}`", q["instructions"], "Options:"]
    for lab, i in zip(LABELS, ids):
        d = q["criteria"][i]
        lines.append(f"{lab}. {i}" + (f": {d}" if isinstance(d, str) else ""))
    return "\n".join(lines)

def build_prefix(qs: dict, apps: list[str]) -> tuple[str, dict]:
    ids_of = {}
    parts = ["You answer typed questions about a voice command spoken to a Mac. Each question has its own lettered options; answer with one letter only.",
             f"Installed apps: {json.dumps(apps)}"]
    for k, q in qs.items():
        if k == "text":
            continue
        ids = ["true", "false"] if q["type"] == "noul" else list(q["criteria"])[: len(LABELS)]
        ids_of[k] = ids
        parts.append(menu(k, q, ids))
    return "\n\n".join(parts), ids_of

def ask_b(model: str, prefix: str, ids: list[str], key: str, utt: str, cands: dict, text_q: dict | None) -> dict:
    user = f"utterance: {utt}\ncandidates: {json.dumps(cands, ensure_ascii=False)}\n"
    if text_q is not None:
        user += "\n" + menu("text", text_q, ids) + "\n"
    user += f"\nAnswer question `{key}` with the single letter of the best option."
    msgs = [{"role": "system", "content": prefix}, {"role": "user", "content": user}, {"role": "assistant", "content": "Letter:"}]
    body = {"model": model, "stream": False, "think": False, "messages": msgs,
            "options": {"num_predict": 1, "temperature": 0}, "logprobs": True, "top_logprobs": 20}
    t0 = time.perf_counter(); r = CLIENT.post(OLLAMA, json=body).json(); ms = (time.perf_counter() - t0) * 1000
    lp = r.get("logprobs") or r["message"].get("logprobs") or []
    top = (lp[0] if lp else {}).get("top_logprobs", [])
    raw = {}
    for t in top:
        tok = t["token"].strip()
        if tok in LABELS[: len(ids)]:
            raw[ids[LABELS.index(tok)]] = raw.get(ids[LABELS.index(tok)], 0.0) + math.exp(t["logprob"])
    mass = sum(raw.values()); probs = {i: (raw.get(i, 0.0) / mass if mass else 1 / len(ids)) for i in ids}
    return {"probs": probs, "ms": ms, "mass": mass, "prompt_eval": r.get("prompt_eval_count")}

if __name__ == "__main__":
    model = sys.argv[1]
    apps = actions.installed_apps()
    print(f"model={model}  installed apps={len(apps)}  Chrome in first 48? {'Google Chrome' in apps[:48]}  Safari? {'Safari' in apps[:48]}")
    apps48 = apps[:48]
    qs_all = brain.Brain._questions(None, {"c0": "x"}, apps48)
    prefix, ids_of = build_prefix(qs_all, apps48)
    print(f"prefix chars={len(prefix)}")
    print("\n== layout B: 20-question fan-out, sequential, per utterance ==")
    for u in UTTS[:6] + UTTS[10:12]:
        cands = brain.text_candidates(u)
        qs = brain.Brain._questions(None, cands, apps48)
        t0 = time.perf_counter(); out = {}; evals = []
        for k, q in qs.items():
            if k == "text":
                ids = list(q["criteria"]); r = ask_b(model, prefix, ids, k, u, cands, q)
            else:
                r = ask_b(model, prefix, ids_of[k], k, u, cands, None)
            out[k] = r; evals.append(r["prompt_eval"])
        wall = (time.perf_counter() - t0) * 1000
        act = max(out["action"]["probs"], key=out["action"]["probs"].get)
        print(f"{u!r:44} {wall:6.0f}ms  action={act}({out['action']['probs'][act]:.2f})  addressed={out['addressed']['probs']['true']:.2f}  prompt_eval/req={min(evals)}-{max(evals)}  min_mass={min(r['mass'] for r in out.values()):.2f}")

    print("\n== app head with Chrome and Safari actually offered ==")
    offered = [a for a in apps if a in ("Google Chrome", "Safari", "Notes", "Finder", "Slack", "Cursor")] + [a for a in apps if a not in ("Google Chrome", "Safari")][:42]
    qa = brain.Brain._questions(None, {}, offered)["app"]
    for u in ["open chrome", "abre safari", "switch to slack", "open notes"]:
        st = render_state({"utterance": u, "frontmost_app": "Finder"})
        a = ask(model, st, qa)
        top3 = sorted(a["probabilities"].items(), key=lambda kv: -kv[1])[:3]
        print(f"  {u!r:18} -> {[(k, round(v, 2)) for k, v in top3]}  mass={a['_mass']:.2f}")

    print("\n== action head: fwd, rev, and fwd+rev average ==")
    qact = brain.Brain._questions(None, {}, apps48)["action"]
    order = list(qact["criteria"]); rev = list(reversed(order)); ok = 0
    expect = {"open chrome": "open_app", "search youtube for lofi hip hop": "web_search", "type hello world and hit enter": "type_text",
              "scroll down a lot": "scroll", "turn it up": "volume", "what time is dinner tonight": "none",
              "find the cheapest flight to london on google flights": "task", "close this tab": "shortcut", "empty the trash": "system",
              "open notes and type buy milk and press enter": "open_app", "abre safari": "open_app", "sube el volumen": "volume",
              "busca en youtube lofi hip hop": "web_search", "escribe hola mundo y dale enter": "type_text", "a que hora es la cena": "none"}
    for u in UTTS:
        st = render_state({"utterance": u, "frontmost_app": "Finder"})
        a = ask(model, st, qact); b = ask(model, st, qact, order=rev)
        avg = {k: (a["probabilities"][k] + b["probabilities"][k]) / 2 for k in order}
        pick = max(avg, key=avg.get); ok += pick == expect[u]
        flag = "" if pick == expect[u] else f"  <- expected {expect[u]}"
        print(f"  {u!r:52} fwd={a['choice']:12} rev={b['choice']:12} avg={pick}({avg[pick]:.2f}){flag}")
    print(f"  avg accuracy: {ok}/{len(UTTS)}")
