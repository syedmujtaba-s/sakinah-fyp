"""
Regression runner for Sakinah RAG.

Phase A — retrieval-only: calls rag.search_stories() directly per case.
Phase B — full pipeline: calls /api/guidance via FastAPI TestClient.

Reads: tests/regression_cases.jsonl, tests/dataset_audit.json
Writes: tests/report.md, tests/report.jsonl

Usage:
    cd sakinah/backend
    .venv\\Scripts\\activate
    python tests/run_regression.py                 # Phase A + B (sampled)
    python tests/run_regression.py --phase A       # retrieval only
    python tests/run_regression.py --phase B       # full pipeline only
    python tests/run_regression.py --full-b        # Phase B on ALL cases (slow, burns Groq)
"""

import os
import sys
import json
import time
import argparse
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
from bson import ObjectId

from rag import search_stories, SCORE_THRESHOLD, embedder_encode
from database import stories_collection, story_index_collection

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
CASES_PATH = os.path.join(TESTS_DIR, "regression_cases.jsonl")
AUDIT_PATH = os.path.join(TESTS_DIR, "dataset_audit.json")
REPORT_MD = os.path.join(TESTS_DIR, "report.md")
REPORT_JSONL = os.path.join(TESTS_DIR, "report.jsonl")

RESPONSE_FIELDS = [
    "story_title", "story_period", "story_summary",
    "seerah_connection", "lessons", "practical_advice",
    "dua", "emotion", "ai_fallback",
]

LATENCY_SLOW_MS = 30000


def load_cases():
    cases = []
    with open(CASES_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            cases.append(json.loads(line))
    return cases


def load_audit():
    try:
        with open(AUDIT_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


# ============================================================
#  FAST LOCAL SEARCH — preload chunks once, cosine locally
# ============================================================

_CHUNKS_CACHE = None
_STORIES_CACHE = None


def _load_chunks_once():
    global _CHUNKS_CACHE, _STORIES_CACHE
    if _CHUNKS_CACHE is not None:
        return
    print("Preloading chunks + stories into memory...")
    chunks = list(story_index_collection.find(
        {}, {"story_id": 1, "embedding": 1, "emotions": 1}
    ))
    embs = []
    meta = []
    for c in chunks:
        emb = c.get("embedding") or []
        if not emb:
            continue
        embs.append(emb)
        meta.append({
            "story_id": c.get("story_id"),
            "emotions": [e.lower() for e in (c.get("emotions") or [])],
        })
    mat = np.array(embs, dtype=np.float32)
    norms = np.linalg.norm(mat, axis=1, keepdims=True) + 1e-10
    mat_normed = mat / norms

    _CHUNKS_CACHE = {"mat": mat_normed, "meta": meta}

    stories = {}
    for s in stories_collection.find({}):
        s["_id_str"] = str(s["_id"])
        stories[s["_id_str"]] = s
    _STORIES_CACHE = stories
    print(f"  loaded {len(meta)} chunks, {len(stories)} stories")


def _fast_search(journal_entry: str, emotion: str, limit: int = 3) -> list:
    _load_chunks_once()
    enriched = f"Emotion: {emotion}. {journal_entry}"
    q = np.array(embedder_encode(enriched), dtype=np.float32)
    q = q / (np.linalg.norm(q) + 1e-10)

    scores = _CHUNKS_CACHE["mat"] @ q  # cosine since both normed
    meta = _CHUNKS_CACHE["meta"]

    # Emotion hard filter first; fall back to no-filter if empty
    emotion_lc = emotion.lower()
    filtered_idx = [i for i, m in enumerate(meta) if emotion_lc in m["emotions"]]
    if not filtered_idx:
        filtered_idx = list(range(len(meta)))

    best_per_story = {}
    best_all_per_story = {}
    for i in filtered_idx:
        sid = meta[i]["story_id"]
        s = float(scores[i])
        if sid not in best_all_per_story or s > best_all_per_story[sid]:
            best_all_per_story[sid] = s
        if s >= SCORE_THRESHOLD:
            if sid not in best_per_story or s > best_per_story[sid]:
                best_per_story[sid] = s

    if not best_per_story and best_all_per_story:
        top_sid = max(best_all_per_story, key=best_all_per_story.get)
        best_per_story = {top_sid: best_all_per_story[top_sid]}

    ranked = sorted(best_per_story.items(), key=lambda x: x[1], reverse=True)[:limit]

    out = []
    for sid, s in ranked:
        story = _STORIES_CACHE.get(str(sid))
        if not story:
            continue
        copy = dict(story)
        copy["_id"] = copy.get("_id_str")
        copy["search_score"] = s
        out.append(copy)
    return out


# ============================================================
#  PHASE A — retrieval-only
# ============================================================

def run_phase_a(cases, use_atlas=False):
    print("\n=== PHASE A — retrieval-only ===\n")
    results = []
    for i, case in enumerate(cases, 1):
        expect = case.get("expect", {})
        # Skip cases that are meant to fail at the API layer (400)
        if expect.get("expect_400"):
            results.append({
                "id": case["id"], "phase": "A", "skipped": True,
                "reason": "expect_400 — not applicable to raw search_stories",
            })
            continue

        entry = case.get("journal_entry", "")
        emotion = case.get("emotion", "")

        t0 = time.time()
        error = None
        stories = []
        try:
            if use_atlas:
                stories = search_stories(entry, emotion, limit=3) or []
            else:
                stories = _fast_search(entry, emotion, limit=3) or []
        except Exception as e:
            error = f"{type(e).__name__}: {e}"
        latency_ms = int((time.time() - t0) * 1000)

        top = stories[0] if stories else None
        top_score = float(top["search_score"]) if top and "search_score" in top else None
        top_title = top.get("title") if top else None
        top_emotions = top.get("emotions", []) if top else []
        emotion_match = emotion in [e.lower() for e in top_emotions] if top_emotions else False

        checks = {}
        min_score = expect.get("min_top_score")
        if min_score is not None:
            checks["min_top_score"] = {
                "expected": min_score,
                "actual": top_score,
                "pass": top_score is not None and top_score >= min_score,
            }
        if expect.get("emotion_in_story") is True:
            checks["emotion_in_story"] = {
                "expected": True,
                "actual": emotion_match,
                "pass": emotion_match,
            }
        if expect.get("no_500"):
            checks["no_500"] = {
                "expected": "no exception",
                "actual": "ok" if error is None else error,
                "pass": error is None,
            }
        if expect.get("allow_fallback"):
            checks["allow_fallback"] = {
                "expected": "at least one story",
                "actual": f"{len(stories)} stories",
                "pass": len(stories) > 0,
            }

        passed = all(c["pass"] for c in checks.values()) if checks else (error is None)

        results.append({
            "id": case["id"],
            "phase": "A",
            "persona": case.get("persona"),
            "emotion": emotion,
            "journal_entry": entry[:140],
            "latency_ms": latency_ms,
            "error": error,
            "num_stories": len(stories),
            "top_title": top_title,
            "top_score": top_score,
            "top_emotions": top_emotions,
            "emotion_match": emotion_match,
            "checks": checks,
            "pass": passed,
        })
        status = "PASS" if passed else "FAIL"
        score_str = f"{top_score:.3f}" if top_score is not None else "n/a"
        print(f"  [{i:3d}/{len(cases)}] {status}  {case['id']:<35} score={score_str} lat={latency_ms}ms")
    return results


# ============================================================
#  PHASE B — full pipeline via TestClient
# ============================================================

def select_phase_b_cases(cases, full_b=False):
    if full_b:
        return cases
    selected = []
    per_emotion = defaultdict(int)
    for c in cases:
        cid = c["id"]
        # Always include crisis, false-positive, and edge cases
        if cid.startswith("crisis_") or cid.startswith("edge_"):
            selected.append(c)
            continue
        # Sample 2 per emotion for baseline
        em = c.get("emotion", "")
        if per_emotion[em] < 2:
            selected.append(c)
            per_emotion[em] += 1
    return selected


def run_phase_b(cases, use_atlas=False):
    print("\n=== PHASE B — full pipeline (/api/guidance) ===\n")

    # Monkey-patch search_stories to use fast local cosine before main.app is imported
    if not use_atlas:
        import rag as _rag
        _rag.search_stories = _fast_search
        # Also patch guidance_router's already-imported reference
        import guidance_router as _gr
        _gr.search_stories = _fast_search
        print("  (using fast local search; Atlas is bypassed for this Phase B run)")

    from fastapi.testclient import TestClient
    from main import app

    # Patch guidance_router in app too (in case it was already imported)
    if not use_atlas:
        import guidance_router as _gr2
        _gr2.search_stories = _fast_search

    client = TestClient(app)
    results = []

    for i, case in enumerate(cases, 1):
        expect = case.get("expect", {})
        entry = case.get("journal_entry", "")
        emotion = case.get("emotion", "")

        t0 = time.time()
        status_code = None
        body = None
        error = None
        try:
            resp = client.post("/api/guidance", json={
                "journal_entry": entry, "emotion": emotion
            })
            status_code = resp.status_code
            try:
                body = resp.json()
            except Exception:
                body = {"_raw": resp.text[:500]}
        except Exception as e:
            error = f"{type(e).__name__}: {e}"
        latency_ms = int((time.time() - t0) * 1000)

        checks = {}

        # 400 expected (unsupported emotion)
        if expect.get("expect_400"):
            checks["status_400"] = {
                "expected": 400, "actual": status_code,
                "pass": status_code == 400,
            }

        # Crisis flag
        if "crisis" in expect:
            want_crisis = bool(expect["crisis"])
            got_crisis = bool(body.get("crisis")) if isinstance(body, dict) else False
            checks["crisis"] = {
                "expected": want_crisis, "actual": got_crisis,
                "pass": got_crisis == want_crisis,
            }

        # No 500
        if expect.get("no_500"):
            checks["no_500"] = {
                "expected": "< 500", "actual": status_code,
                "pass": status_code is not None and status_code < 500 and error is None,
            }

        # Response completeness — only for success cases (200 + no expect_400)
        if status_code == 200 and not expect.get("expect_400") and isinstance(body, dict):
            missing = [f for f in RESPONSE_FIELDS if f not in body]
            checks["response_complete"] = {
                "expected": "all fields present",
                "actual": f"missing: {missing}" if missing else "all present",
                "pass": not missing,
            }

        # Latency flag (soft — warn, don't fail)
        slow = latency_ms > LATENCY_SLOW_MS
        if slow:
            checks["latency"] = {
                "expected": f"< {LATENCY_SLOW_MS} ms",
                "actual": f"{latency_ms} ms",
                "pass": False,
            }

        # Overall pass
        if checks:
            passed = all(c["pass"] for c in checks.values())
        else:
            passed = status_code == 200 and error is None

        # Strip huge body fields to keep report compact
        compact_body = None
        if isinstance(body, dict):
            compact_body = {
                "story_title": body.get("story_title"),
                "ai_fallback": body.get("ai_fallback"),
                "crisis": body.get("crisis", False),
                "dua_preview": (body.get("dua") or "")[:80],
            }

        results.append({
            "id": case["id"],
            "phase": "B",
            "persona": case.get("persona"),
            "emotion": emotion,
            "journal_entry": entry[:140],
            "status_code": status_code,
            "latency_ms": latency_ms,
            "error": error,
            "body_preview": compact_body,
            "checks": checks,
            "pass": passed,
        })
        status = "PASS" if passed else "FAIL"
        print(f"  [{i:3d}/{len(cases)}] {status}  {case['id']:<35} http={status_code} lat={latency_ms}ms")
    return results


# ============================================================
#  REPORT
# ============================================================

def summarize(results_a, results_b, audit):
    lines = []
    lines.append("# Regression Report")
    lines.append("")
    lines.append(f"- Threshold: `SCORE_THRESHOLD = {SCORE_THRESHOLD}`")
    lines.append(f"- Total cases: {len(load_cases())}")
    if audit:
        lines.append(f"- Dataset: {audit['total_stories']} stories / {audit['total_chunks']} chunks")
        if audit.get("thin"):
            lines.append(f"- Thin emotions: {', '.join(audit['thin'])}")
        if audit.get("empty"):
            lines.append(f"- Empty emotions: {', '.join(audit['empty'])}")
    lines.append("")

    # ---- Phase A summary ----
    if results_a:
        active_a = [r for r in results_a if not r.get("skipped")]
        passed = sum(1 for r in active_a if r["pass"])
        total = len(active_a)
        pct = (passed / total * 100) if total else 0
        lines.append("## Phase A — retrieval-only")
        lines.append("")
        lines.append(f"Pass rate: **{passed}/{total} ({pct:.1f}%)**")
        lines.append("")

        # Per-emotion pass rate
        per_emotion = defaultdict(lambda: [0, 0])
        for r in active_a:
            per_emotion[r["emotion"]][1] += 1
            if r["pass"]:
                per_emotion[r["emotion"]][0] += 1
        lines.append("### Phase A pass rate by emotion")
        lines.append("")
        lines.append("| Emotion | Passed | Total | % |")
        lines.append("|---|---:|---:|---:|")
        for em in sorted(per_emotion, key=lambda k: per_emotion[k][0] / per_emotion[k][1] if per_emotion[k][1] else 0):
            p, t = per_emotion[em]
            ratio = (p / t * 100) if t else 0
            lines.append(f"| {em} | {p} | {t} | {ratio:.0f}% |")
        lines.append("")

        # Score distribution
        scores = [r["top_score"] for r in active_a if r.get("top_score") is not None]
        if scores:
            scores_sorted = sorted(scores)
            def pct_of(p):
                idx = int(len(scores_sorted) * p)
                idx = min(idx, len(scores_sorted) - 1)
                return scores_sorted[idx]
            lines.append("### Top-1 score distribution (Phase A)")
            lines.append("")
            lines.append(f"- min: {min(scores):.3f}")
            lines.append(f"- p25: {pct_of(0.25):.3f}")
            lines.append(f"- p50: {pct_of(0.50):.3f}")
            lines.append(f"- p75: {pct_of(0.75):.3f}")
            lines.append(f"- max: {max(scores):.3f}")
            lines.append("")

        # Failures
        failures = [r for r in active_a if not r["pass"]]
        if failures:
            lines.append(f"### Phase A failures ({len(failures)})")
            lines.append("")
            for r in failures[:30]:
                lines.append(f"- **{r['id']}** ({r['emotion']}) — score `{r.get('top_score')}` → `{r.get('top_title')}`")
                lines.append(f"  - entry: _{r['journal_entry']}_")
                for name, c in r["checks"].items():
                    if not c["pass"]:
                        lines.append(f"  - FAIL `{name}`: expected {c['expected']} got {c['actual']}")
                lines.append("")

    # ---- Phase B summary ----
    if results_b:
        passed = sum(1 for r in results_b if r["pass"])
        total = len(results_b)
        pct = (passed / total * 100) if total else 0
        lines.append("## Phase B — full pipeline")
        lines.append("")
        lines.append(f"Pass rate: **{passed}/{total} ({pct:.1f}%)**")
        lines.append("")

        # Crisis detection summary
        crisis_cases = [r for r in results_b if r["id"].startswith("crisis_") and not r["id"].startswith("crisis_fp")]
        crisis_fp = [r for r in results_b if r["id"].startswith("crisis_fp")]
        if crisis_cases:
            got = sum(1 for r in crisis_cases if r["checks"].get("crisis", {}).get("pass"))
            lines.append(f"### Crisis detection")
            lines.append("")
            lines.append(f"- True positives: **{got}/{len(crisis_cases)}** crisis phrases triggered `crisis=true`")
            if crisis_fp:
                fp_correct = sum(1 for r in crisis_fp if r["checks"].get("crisis", {}).get("pass"))
                lines.append(f"- False-positive guards: **{fp_correct}/{len(crisis_fp)}** benign phrases correctly NOT flagged")
            lines.append("")
            # List failed crisis cases
            failed_crisis = [r for r in crisis_cases if not r["checks"].get("crisis", {}).get("pass")]
            if failed_crisis:
                lines.append("**Crisis phrases that did NOT trigger (keyword gap):**")
                for r in failed_crisis:
                    lines.append(f"- `{r['id']}` — _{r['journal_entry']}_")
                lines.append("")

        # Latency
        lats = [r["latency_ms"] for r in results_b if r["latency_ms"]]
        if lats:
            lats_sorted = sorted(lats)
            p95 = lats_sorted[int(len(lats_sorted) * 0.95)] if lats_sorted else 0
            lines.append("### Latency")
            lines.append("")
            lines.append(f"- median: {lats_sorted[len(lats_sorted) // 2]} ms")
            lines.append(f"- p95: {p95} ms")
            lines.append(f"- max: {max(lats)} ms")
            lines.append("")

        # Failures (non-crisis)
        failures = [r for r in results_b if not r["pass"] and not r["id"].startswith("crisis_")]
        if failures:
            lines.append(f"### Phase B failures ({len(failures)})")
            lines.append("")
            for r in failures[:30]:
                lines.append(f"- **{r['id']}** ({r['emotion']}) — http `{r['status_code']}`")
                for name, c in r["checks"].items():
                    if not c["pass"]:
                        lines.append(f"  - FAIL `{name}`: expected {c['expected']} got {c['actual']}")
                lines.append("")

    with open(REPORT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    with open(REPORT_JSONL, "w", encoding="utf-8") as f:
        for r in (results_a or []) + (results_b or []):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"\nWrote: {REPORT_MD}")
    print(f"Wrote: {REPORT_JSONL}")


# ============================================================
#  MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=["A", "B", "AB"], default="AB")
    parser.add_argument("--full-b", action="store_true", help="Run Phase B on all cases (slow)")
    parser.add_argument("--atlas", action="store_true", help="Phase A via Atlas Vector Search (slow, goes over network). Default is local preloaded cosine.")
    args = parser.parse_args()

    cases = load_cases()
    audit = load_audit()
    print(f"Loaded {len(cases)} cases.")
    if audit:
        print(f"Audit loaded: {audit['total_stories']} stories.")

    results_a = None
    results_b = None

    if "A" in args.phase:
        results_a = run_phase_a(cases, use_atlas=args.atlas)

    if "B" in args.phase:
        b_cases = select_phase_b_cases(cases, full_b=args.full_b)
        print(f"\nPhase B will run {len(b_cases)} cases ({'ALL' if args.full_b else 'sampled'})")
        results_b = run_phase_b(b_cases, use_atlas=args.atlas)

    summarize(results_a, results_b, audit)

    # Exit code
    a_fail = sum(1 for r in (results_a or []) if not r.get("skipped") and not r["pass"])
    b_fail = sum(1 for r in (results_b or []) if not r["pass"])
    print(f"\nTotal failures: Phase A = {a_fail}, Phase B = {b_fail}")


if __name__ == "__main__":
    main()
