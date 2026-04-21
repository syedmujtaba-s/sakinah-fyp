"""
Phase C — Multilingual retrieval quality.

Compares retrieval quality between English and translated (Roman Urdu, Urdu script,
Hindi, mixed) versions of the SAME meaning. Measures:
- Score delta per language variant
- Whether the same top story is retrieved
- Emotion match

Uses the fast local cosine from run_regression.py (no Atlas, no Groq).

Usage:
    cd sakinah/backend
    .venv\\Scripts\\activate
    python tests/run_multilingual.py
"""

import os
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Reuse the fast local search from the main runner
from tests.run_regression import _fast_search, _load_chunks_once

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
CASES_PATH = os.path.join(TESTS_DIR, "multilingual_cases.jsonl")
REPORT_MD = os.path.join(TESTS_DIR, "multilingual_report.md")
REPORT_JSONL = os.path.join(TESTS_DIR, "multilingual_report.jsonl")

# Variant labels we recognize in cases
LANG_LABELS = {
    "en": "English",
    "roman_urdu": "Roman Urdu",
    "urdu_script": "Urdu (native)",
    "hindi": "Hindi (Roman)",
}


def load_cases():
    cases = []
    with open(CASES_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            cases.append(json.loads(line))
    return cases


def run_one(entry, emotion):
    if entry is None:
        return None
    stories = _fast_search(entry, emotion, limit=3) or []
    top = stories[0] if stories else None
    return {
        "top_title": top.get("title") if top else None,
        "top_score": float(top["search_score"]) if top and "search_score" in top else None,
        "top_emotions": top.get("emotions", []) if top else [],
        "emotion_match": emotion in [e.lower() for e in (top.get("emotions") or [])] if top else False,
        "num_stories": len(stories),
    }


def run_groups(cases):
    print("\n=== PHASE C — multilingual retrieval quality ===\n")
    _load_chunks_once()
    results = []
    for c in cases:
        group = c["group"]
        emotion = c["emotion"]
        variants = c.get("variants", {})
        per_lang = {}
        for lang, entry in variants.items():
            if entry is None:
                continue
            r = run_one(entry, emotion)
            per_lang[lang] = r
            if r:
                print(f"  {group:<28} {lang:<12} score={r['top_score']:.3f}  story={r['top_title']}")

        # Compute deltas vs English
        en = per_lang.get("en")
        deltas = {}
        same_story = {}
        if en and en["top_score"] is not None:
            for lang, r in per_lang.items():
                if lang == "en" or r is None or r["top_score"] is None:
                    continue
                deltas[lang] = round(en["top_score"] - r["top_score"], 4)
                same_story[lang] = (en["top_title"] == r["top_title"])

        results.append({
            "group": group,
            "emotion": emotion,
            "per_lang": per_lang,
            "deltas_vs_en": deltas,
            "same_story_as_en": same_story,
        })
    return results


def write_report(results):
    lines = []
    lines.append("# Phase C — Multilingual Retrieval Quality Report")
    lines.append("")
    lines.append(f"- Total groups: **{len(results)}**")

    # Aggregate deltas per language
    per_lang_deltas = {}
    same_story_counts = {}
    for r in results:
        for lang, d in r["deltas_vs_en"].items():
            per_lang_deltas.setdefault(lang, []).append(d)
            if r["same_story_as_en"].get(lang):
                same_story_counts[lang] = same_story_counts.get(lang, 0) + 1

    lines.append("")
    lines.append("## Score delta vs English (English score minus variant score)")
    lines.append("")
    lines.append("Positive delta = English retrieves higher-scoring story than the variant.")
    lines.append("Large positive delta = meaningful degradation for that language.")
    lines.append("")
    lines.append("| Language | Groups | Avg delta | Max delta | Min delta | Same top story as EN |")
    lines.append("|---|---:|---:|---:|---:|---|")
    for lang, ds in per_lang_deltas.items():
        avg = sum(ds) / len(ds)
        label = LANG_LABELS.get(lang, lang)
        same_ct = same_story_counts.get(lang, 0)
        lines.append(f"| {label} | {len(ds)} | {avg:+.3f} | {max(ds):+.3f} | {min(ds):+.3f} | {same_ct}/{len(ds)} |")
    lines.append("")

    # Recommendation
    lines.append("## Recommendation")
    lines.append("")
    # Also compute emotion-match rate per language (quality independent of same-story)
    per_lang_emotion_match = {}
    for r in results:
        for lang, d in r["per_lang"].items():
            if lang == "en" or d is None:
                continue
            per_lang_emotion_match.setdefault(lang, []).append(d.get("emotion_match", False))

    if "roman_urdu" in per_lang_deltas:
        avg_ru = sum(per_lang_deltas["roman_urdu"]) / len(per_lang_deltas["roman_urdu"])
        same_ru_ct = same_story_counts.get("roman_urdu", 0)
        total_ru = len(per_lang_deltas["roman_urdu"])
        em_match_ru = per_lang_emotion_match.get("roman_urdu", [])
        em_match_pct = (sum(em_match_ru) / len(em_match_ru) * 100) if em_match_ru else 0

        # Verdict uses score delta + emotion-match rate (same-story is too strict — natural variance exists)
        if avg_ru < 0.05 and em_match_pct >= 90:
            verdict = "**ACCEPTABLE** — Roman Urdu scores are within noise of English and emotion-match rate is high. Current embedder handles it."
        elif avg_ru < 0.15 and em_match_pct >= 70:
            verdict = "**MARGINAL** — Roman Urdu is slightly degraded but usable; stories retrieved still match the declared emotion most of the time."
        else:
            verdict = "**DEGRADED** — Roman Urdu retrieval meaningfully worse. Options: (a) upgrade to `paraphrase-multilingual-mpnet-base-v2`, (b) add a Groq pre-translation step before embedding, (c) document limitation."
        lines.append(f"- Roman Urdu: avg delta **{avg_ru:+.3f}**, emotion-match rate **{em_match_pct:.0f}%**, same-story rate {same_ru_ct}/{total_ru} ({same_ru_ct / total_ru * 100:.0f}%, note: low same-story rate does NOT mean low quality — different-but-equally-relevant stories are normal) → {verdict}")
        lines.append("")

    # Per-group detail
    lines.append("## Per-group detail")
    lines.append("")
    for r in results:
        lines.append(f"### `{r['group']}` — emotion: `{r['emotion']}`")
        lines.append("")
        lines.append("| Language | Top score | Top story | Emotion match |")
        lines.append("|---|---:|---|:---:|")
        for lang, d in r["per_lang"].items():
            if d is None:
                continue
            score = f"{d['top_score']:.3f}" if d["top_score"] is not None else "—"
            match = "Y" if d["emotion_match"] else "N"
            title = d["top_title"] or "—"
            lines.append(f"| {LANG_LABELS.get(lang, lang)} | {score} | {title} | {match} |")
        if r["deltas_vs_en"]:
            deltas_str = ", ".join(f"{LANG_LABELS.get(k, k)}: {v:+.3f}" for k, v in r["deltas_vs_en"].items())
            lines.append(f"")
            lines.append(f"Delta vs EN: {deltas_str}")
        lines.append("")

    with open(REPORT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    with open(REPORT_JSONL, "w", encoding="utf-8") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"\nWrote: {REPORT_MD}")
    print(f"Wrote: {REPORT_JSONL}")


if __name__ == "__main__":
    cases = load_cases()
    print(f"Loaded {len(cases)} multilingual groups.")
    results = run_groups(cases)
    write_report(results)
