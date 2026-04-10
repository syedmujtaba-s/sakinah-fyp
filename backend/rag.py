"""
RAG (Retrieval-Augmented Generation) module for Sakinah.

Handles:
- Embedding stories with chunking for better retrieval precision
- MongoDB Atlas Vector Search (with local cosine similarity fallback)
- Auto-ingesting .jsonl files from data/stories/ folder
"""

import os
import json
import numpy as np
from sentence_transformers import SentenceTransformer
from bson import ObjectId

from database import stories_collection, story_index_collection

# --- CONFIG ---
SCORE_THRESHOLD = 0.40          # Minimum cosine similarity (raised from 0.25)
CHUNK_MAX_WORDS = 150           # Max words per chunk
CHUNK_OVERLAP_WORDS = 30        # Overlap between chunks for context continuity
DATA_DIR = os.path.join(os.path.dirname(__file__), "data", "stories")

# --- AI MODEL (lazy-loaded) ---
_embedder = None


def get_embedder():
    global _embedder
    if _embedder is None:
        print("Loading AI Embedding Model...")
        _embedder = SentenceTransformer(
            "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
        )
        print("AI Model Ready!")
    return _embedder


def embedder_encode(text: str) -> list:
    return get_embedder().encode(text).tolist()


# =========================================================
#  CHUNKING — split stories into overlapping pieces
# =========================================================
def _chunk_text(text: str, max_words: int = CHUNK_MAX_WORDS,
                overlap: int = CHUNK_OVERLAP_WORDS) -> list[str]:
    """
    Split text into overlapping word-based chunks.
    Short text (< max_words) returns as a single chunk.
    """
    words = text.split()
    if len(words) <= max_words:
        return [text]

    chunks = []
    start = 0
    while start < len(words):
        end = start + max_words
        chunk = " ".join(words[start:end])
        chunks.append(chunk)
        start += max_words - overlap

    return chunks


def _build_chunks(story: dict) -> list[dict]:
    """
    Build embedding chunks for a single story.

    Returns a list of dicts, each with:
      - text: the text to embed
      - chunk_type: "summary" or "story_chunk"
      - chunk_index: ordering within the story

    Strategy:
    1. One "summary" chunk = title + summary + emotions + lessons (metadata-rich)
    2. Multiple "story_chunk" chunks from the actual story text (content-rich)
    """
    # Chunk 1: metadata-rich summary (always one chunk)
    emotions_text = ", ".join(story.get("emotions", []))
    lessons_text = ". ".join(story.get("lessons", []))
    advice_text = ". ".join(story.get("practical_advice", []))
    summary_chunk = (
        f"{story.get('title', '')}. "
        f"{story.get('summary', '')} "
        f"Emotions: {emotions_text}. "
        f"Lessons: {lessons_text}. "
        f"Advice: {advice_text}"
    )

    chunks = [{"text": summary_chunk, "chunk_type": "summary", "chunk_index": 0}]

    # Chunks 2+: the actual story narrative, split into overlapping pieces
    story_text = story.get("story", "")
    if story_text:
        story_pieces = _chunk_text(story_text)
        for i, piece in enumerate(story_pieces):
            # Prepend title for context in each chunk
            chunk_text = f"{story.get('title', '')}: {piece}"
            chunks.append({
                "text": chunk_text,
                "chunk_type": "story_chunk",
                "chunk_index": i + 1
            })

    return chunks


# =========================================================
#  SYNC — embed & index stories (with chunking)
# =========================================================
def sync_new_stories():
    """Embed new/unindexed stories into story_index with per-chunk embeddings."""
    print("Checking for new stories to index...")

    all_stories = list(stories_collection.find({}))

    # Get story IDs that already have at least one chunk indexed
    indexed_ids = set()
    try:
        for doc in story_index_collection.find({}, {"story_id": 1}):
            indexed_ids.add(str(doc["story_id"]))
    except Exception as e:
        print(f"Index check error: {e}")

    print(f"Total Stories: {len(all_stories)} | Already Indexed: {len(indexed_ids)}")

    new_entries = []
    embedder = get_embedder()

    for story in all_stories:
        s_id = str(story["_id"])
        if s_id in indexed_ids:
            continue

        chunks = _build_chunks(story)
        for chunk in chunks:
            embedding = embedder.encode(chunk["text"]).tolist()
            new_entries.append({
                "story_id": s_id,
                "text": chunk["text"],
                "chunk_type": chunk["chunk_type"],
                "chunk_index": chunk["chunk_index"],
                "embedding": embedding,
                "emotions": story.get("emotions", []),
                "metadata": {
                    "title": story.get("title", ""),
                    "period": story.get("period", ""),
                    "emotions": story.get("emotions", []),
                }
            })

    if new_entries:
        print(f"Indexing {len(new_entries)} chunks from {len(new_entries)} new entries...")
        story_index_collection.insert_many(new_entries)
        print("Done indexing.")
    else:
        print("Index is up to date.")


# =========================================================
#  SEARCH — find relevant stories via chunks
# =========================================================
def search_stories(journal_entry: str, emotion: str, limit: int = 3) -> list:
    """
    Search for relevant stories using chunk-level matching.

    1. Embeds the query (emotion + journal text)
    2. Searches chunks via Atlas Vector Search (falls back to local cosine)
    3. Deduplicates by story_id, keeping the best chunk score per story
    4. Returns full story documents sorted by best match
    """
    enriched_query = f"Emotion: {emotion}. {journal_entry}"
    query_embedding = embedder_encode(enriched_query)

    print(f"Searching for emotion '{emotion}': {journal_entry[:80]}...")

    # We fetch more chunks than needed since multiple chunks may be from the same story
    chunk_limit = limit * 4

    pipeline_with_filter = [
        {
            "$vectorSearch": {
                "index": "story_vector_index",
                "path": "embedding",
                "queryVector": query_embedding,
                "numCandidates": 100,
                "limit": chunk_limit,
                "filter": {"emotions": emotion.lower()}
            }
        },
        {"$project": {"_id": 0, "story_id": 1, "metadata": 1, "emotions": 1,
                       "chunk_type": 1, "chunk_index": 1,
                       "score": {"$meta": "vectorSearchScore"}}}
    ]

    pipeline_no_filter = [
        {
            "$vectorSearch": {
                "index": "story_vector_index",
                "path": "embedding",
                "queryVector": query_embedding,
                "numCandidates": 100,
                "limit": chunk_limit
            }
        },
        {"$project": {"_id": 0, "story_id": 1, "metadata": 1, "emotions": 1,
                       "chunk_type": 1, "chunk_index": 1,
                       "score": {"$meta": "vectorSearchScore"}}}
    ]

    results = []
    atlas_available = True

    try:
        results = list(story_index_collection.aggregate(pipeline_with_filter))
    except Exception as e:
        print(f"Atlas search with filter failed: {e}")
        if "index not found" in str(e).lower() or "PlanExecutor" in str(e):
            atlas_available = False

    if not results and atlas_available:
        try:
            results = list(story_index_collection.aggregate(pipeline_no_filter))
        except Exception as e:
            print(f"Atlas search failed: {e}")
            atlas_available = False

    if not atlas_available or not results:
        return _local_search(query_embedding, emotion, limit)

    # Deduplicate: keep the best score per story_id
    return _dedupe_and_fetch(results, limit)


def _dedupe_and_fetch(chunk_results: list, limit: int) -> list:
    """
    Given scored chunk results, deduplicate by story_id (keep best score),
    apply threshold, fetch full story documents.
    If nothing passes threshold, return the single best match as a fallback.
    """
    best_per_story = {}
    all_best_per_story = {}
    for res in chunk_results:
        sid = res.get("story_id")
        score = res.get("score", 0)
        # Track all scores (for fallback)
        if sid not in all_best_per_story or score > all_best_per_story[sid]:
            all_best_per_story[sid] = score
        # Track only above threshold
        if score < SCORE_THRESHOLD:
            continue
        if sid not in best_per_story or score > best_per_story[sid]:
            best_per_story[sid] = score

    # If nothing passed threshold, return the single best match anyway
    if not best_per_story and all_best_per_story:
        top_sid = max(all_best_per_story, key=all_best_per_story.get)
        best_per_story = {top_sid: all_best_per_story[top_sid]}
        print(f"No results above threshold {SCORE_THRESHOLD}. Returning best match as fallback.")

    # Sort by score descending, take top N
    ranked = sorted(best_per_story.items(), key=lambda x: x[1], reverse=True)[:limit]
    print(f"Found {len(ranked)} unique stories (threshold {SCORE_THRESHOLD}).")

    matched_stories = []
    for story_id, score in ranked:
        try:
            full_story = stories_collection.find_one({"_id": ObjectId(story_id)})
            if full_story:
                full_story["_id"] = str(full_story["_id"])
                full_story["search_score"] = score
                matched_stories.append(full_story)
        except Exception as e:
            print(f"Error fetching story {story_id}: {e}")

    return matched_stories


def _local_search(query_embedding: list, emotion: str, limit: int = 3) -> list:
    """
    Fallback cosine similarity search when Atlas Vector Search is unavailable.
    Searches all chunks, deduplicates by story_id.
    """
    docs = list(story_index_collection.find({"emotions": emotion.lower()}))
    if not docs:
        docs = list(story_index_collection.find({}))

    if not docs:
        return []

    query_vec = np.array(query_embedding)

    # Score every chunk
    scored_chunks = []
    for doc in docs:
        emb = np.array(doc.get("embedding", []))
        if emb.size == 0:
            continue
        cos_sim = float(
            np.dot(query_vec, emb) / (np.linalg.norm(query_vec) * np.linalg.norm(emb) + 1e-10)
        )
        scored_chunks.append({"story_id": doc.get("story_id"), "score": cos_sim})

    # Deduplicate and fetch
    return _dedupe_and_fetch(scored_chunks, limit)


# =========================================================
#  AUTO-INGEST from data/stories/*.jsonl
# =========================================================
def ingest_from_data_folder():
    """
    Scan data/stories/ for .jsonl files. Each line is a story JSON object.
    Inserts stories that don't already exist (by title), then indexes them.
    """
    if not os.path.isdir(DATA_DIR):
        return

    jsonl_files = [f for f in os.listdir(DATA_DIR) if f.endswith(".jsonl")]
    if not jsonl_files:
        return

    print(f"Auto-ingest: found {len(jsonl_files)} .jsonl file(s) in {DATA_DIR}")

    total_added = 0
    for filename in jsonl_files:
        filepath = os.path.join(DATA_DIR, filename)
        with open(filepath, "r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    story = json.loads(line)
                except json.JSONDecodeError as e:
                    print(f"  {filename}:{line_num} — invalid JSON: {e}")
                    continue

                # Validate required fields
                required = {"title", "period", "emotions", "summary", "story", "lessons", "practical_advice"}
                missing = required - set(story.keys())
                if missing:
                    print(f"  {filename}:{line_num} — missing fields: {missing}")
                    continue

                # Skip duplicates
                if stories_collection.find_one({"title": story["title"]}):
                    continue

                # Normalize emotions to lowercase
                story["emotions"] = [e.lower().strip() for e in story["emotions"]]

                stories_collection.insert_one(story)
                total_added += 1

    if total_added:
        print(f"Auto-ingest: added {total_added} new stories. Indexing...")
        sync_new_stories()
    else:
        print("Auto-ingest: no new stories to add.")


# =========================================================
#  UTILITY: RESET AND REBUILD INDEX
# =========================================================
def index_all_stories():
    """Drop and rebuild the entire story index. Run manually when needed."""
    print("Rebuilding story index from scratch...")
    story_index_collection.drop()
    sync_new_stories()
