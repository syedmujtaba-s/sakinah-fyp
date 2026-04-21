"""
Phase 0 — Dataset coverage audit.

Counts stories per emotion in the seerah_stories collection and flags
emotions with thin coverage. Output is read by run_regression.py so that
low retrieval scores can be framed as "data gap" vs "logic bug".

Usage:
    cd sakinah/backend
    .venv\\Scripts\\activate
    python tests/audit_dataset.py
"""

import os
import sys
import json
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import stories_collection, story_index_collection

SUPPORTED_EMOTIONS = [
    "happy", "sad", "anxious", "angry", "confused",
    "grateful", "lonely", "stressed", "fearful", "guilty",
    "hopeless", "overwhelmed", "rejected", "embarrassed", "lost",
]

THIN_THRESHOLD = 5
OUTPUT_MD = os.path.join(os.path.dirname(__file__), "dataset_audit.md")
OUTPUT_JSON = os.path.join(os.path.dirname(__file__), "dataset_audit.json")


def audit():
    total_stories = stories_collection.count_documents({})
    total_chunks = story_index_collection.count_documents({})

    counter = Counter()
    unknown_emotions = Counter()
    stories_without_emotions = 0

    for story in stories_collection.find({}, {"emotions": 1}):
        emotions = story.get("emotions") or []
        if not emotions:
            stories_without_emotions += 1
            continue
        for e in emotions:
            if not isinstance(e, str):
                continue
            key = e.strip().lower()
            if key in SUPPORTED_EMOTIONS:
                counter[key] += 1
            else:
                unknown_emotions[key] += 1

    per_emotion = {e: counter.get(e, 0) for e in SUPPORTED_EMOTIONS}
    sorted_emotions = sorted(per_emotion.items(), key=lambda kv: kv[1], reverse=True)

    thin = [e for e, c in per_emotion.items() if 0 < c < THIN_THRESHOLD]
    empty = [e for e, c in per_emotion.items() if c == 0]

    return {
        "total_stories": total_stories,
        "total_chunks": total_chunks,
        "per_emotion": per_emotion,
        "sorted_emotions": sorted_emotions,
        "thin": thin,
        "empty": empty,
        "unknown_emotions": dict(unknown_emotions),
        "stories_without_emotions": stories_without_emotions,
    }


def write_markdown(result):
    lines = []
    lines.append("# Dataset Coverage Audit")
    lines.append("")
    lines.append(f"- Total stories: **{result['total_stories']}**")
    lines.append(f"- Total chunks in vector index: **{result['total_chunks']}**")
    lines.append(f"- Stories without any emotions tag: **{result['stories_without_emotions']}**")
    lines.append("")
    lines.append("## Story count per emotion (sorted)")
    lines.append("")
    lines.append("| Emotion | Count | Status |")
    lines.append("|---|---:|---|")
    for emotion, count in result["sorted_emotions"]:
        if count == 0:
            status = "EMPTY — untestable"
        elif count < THIN_THRESHOLD:
            status = f"THIN (<{THIN_THRESHOLD}) — expect low scores"
        else:
            status = "OK"
        lines.append(f"| {emotion} | {count} | {status} |")
    lines.append("")

    if result["empty"]:
        lines.append(f"## Empty emotions ({len(result['empty'])})")
        lines.append("")
        lines.append("These have **zero** stories. Test cases for these emotions will always fall back to best-match — retrieval scores will be meaningless. Add stories before trusting results.")
        lines.append("")
        for e in result["empty"]:
            lines.append(f"- `{e}`")
        lines.append("")

    if result["thin"]:
        lines.append(f"## Thin emotions (<{THIN_THRESHOLD} stories)")
        lines.append("")
        lines.append("These have stories but not many — expect inconsistent retrieval quality.")
        lines.append("")
        for e in result["thin"]:
            lines.append(f"- `{e}` — {result['per_emotion'][e]} stories")
        lines.append("")

    if result["unknown_emotions"]:
        lines.append("## Unknown emotion tags (not in supported list)")
        lines.append("")
        lines.append("These appear in the dataset but are not part of the 15 supported emotions. They are silently ignored by the emotion filter.")
        lines.append("")
        for e, c in sorted(result["unknown_emotions"].items(), key=lambda kv: kv[1], reverse=True):
            lines.append(f"- `{e}` — {c} occurrences")
        lines.append("")

    with open(OUTPUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def write_json(result):
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    print("Running dataset coverage audit...")
    result = audit()
    write_markdown(result)
    write_json(result)
    print(f"  Total stories: {result['total_stories']}")
    print(f"  Total chunks: {result['total_chunks']}")
    print(f"  Empty emotions: {len(result['empty'])}")
    print(f"  Thin emotions: {len(result['thin'])}")
    print(f"  Unknown emotion tags: {len(result['unknown_emotions'])}")
    print(f"Wrote: {OUTPUT_MD}")
    print(f"Wrote: {OUTPUT_JSON}")
