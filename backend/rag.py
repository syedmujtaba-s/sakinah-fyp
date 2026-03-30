import numpy as np
from sentence_transformers import SentenceTransformer
from bson import ObjectId

# Import shared DB collections — single connection via database.py
from database import stories_collection, story_index_collection

# Minimum cosine similarity to consider a match useful
SCORE_THRESHOLD = 0.25

# --- AI MODEL SETUP (lazy-loaded on first use) ---
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


def _build_embed_text(story: dict) -> str:
    """
    Build a focused, ~100-word string for embedding.
    Avoids diluting the vector with full narrative text.
    """
    emotions_text = ", ".join(story.get("emotions", []))
    lessons_text = ". ".join(story.get("lessons", []))
    return (
        f"{story.get('title', '')}. "
        f"{story.get('summary', '')} "
        f"Emotions: {emotions_text}. "
        f"Lessons: {lessons_text}"
    )


# =========================================================
#  FUNCTION 1: SYNC STORIES TO MONGODB ATLAS
# =========================================================
def sync_new_stories():
    """Embed new/unindexed Seerah stories into story_index collection."""
    print("Checking for new stories to index...")

    all_stories = list(stories_collection.find({}))

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
        if s_id not in indexed_ids:
            text_to_embed = _build_embed_text(story)
            embedding = embedder.encode(text_to_embed).tolist()

            new_entries.append({
                "story_id": s_id,
                "text": text_to_embed,
                "embedding": embedding,
                "emotions": story.get("emotions", []),
                "metadata": {
                    "title": story.get("title", ""),
                    "period": story.get("period", ""),
                    "emotions": story.get("emotions", []),
                }
            })

    if new_entries:
        print(f"Indexing {len(new_entries)} new stories...")
        story_index_collection.insert_many(new_entries)
        print("Done indexing.")
    else:
        print("Index is up to date.")


# =========================================================
#  FUNCTION 2: SEARCH STORIES
# =========================================================
def search_stories(journal_entry: str, emotion: str, limit: int = 3) -> list:
    """
    Search for relevant Seerah stories based on journal entry and emotion.
    Uses MongoDB Atlas Vector Search with emotion pre-filtering.
    Falls back to local cosine similarity if Atlas index is unavailable.
    Results below SCORE_THRESHOLD are discarded.
    """
    enriched_query = f"Emotion: {emotion}. {journal_entry}"
    query_embedding = embedder_encode(enriched_query)

    print(f"Searching for emotion '{emotion}': {journal_entry[:80]}...")

    pipeline_with_filter = [
        {
            "$vectorSearch": {
                "index": "story_vector_index",
                "path": "embedding",
                "queryVector": query_embedding,
                "numCandidates": 50,
                "limit": limit,
                "filter": {"emotions": emotion.lower()}
            }
        },
        {"$project": {"_id": 0, "story_id": 1, "metadata": 1, "emotions": 1,
                       "score": {"$meta": "vectorSearchScore"}}}
    ]

    pipeline_no_filter = [
        {
            "$vectorSearch": {
                "index": "story_vector_index",
                "path": "embedding",
                "queryVector": query_embedding,
                "numCandidates": 50,
                "limit": limit
            }
        },
        {"$project": {"_id": 0, "story_id": 1, "metadata": 1, "emotions": 1,
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

    # Apply score threshold
    results = [r for r in results if r.get("score", 0) >= SCORE_THRESHOLD]
    print(f"Atlas found {len(results)} matches above threshold.")

    matched_stories = []
    for res in results:
        story_id = res.get("story_id")
        try:
            full_story = stories_collection.find_one({"_id": ObjectId(story_id)})
            if full_story:
                full_story["_id"] = str(full_story["_id"])
                full_story["search_score"] = res.get("score", 0)
                matched_stories.append(full_story)
        except Exception as e:
            print(f"Error fetching story {story_id}: {e}")

    return matched_stories


def embedder_encode(text: str) -> list:
    return get_embedder().encode(text).tolist()


def _local_search(query_embedding: list, emotion: str, limit: int = 3) -> list:
    """
    Fallback cosine similarity search when Atlas Vector Search is unavailable.
    Only returns results above SCORE_THRESHOLD.
    """
    docs = list(story_index_collection.find({"emotions": emotion.lower()}))
    if not docs:
        docs = list(story_index_collection.find({}))

    if not docs:
        return []

    query_vec = np.array(query_embedding)
    scored = []
    for doc in docs:
        emb = np.array(doc.get("embedding", []))
        if emb.size == 0:
            continue
        cos_sim = float(
            np.dot(query_vec, emb) / (np.linalg.norm(query_vec) * np.linalg.norm(emb) + 1e-10)
        )
        if cos_sim >= SCORE_THRESHOLD:
            scored.append((doc, cos_sim))

    scored.sort(key=lambda x: x[1], reverse=True)
    top = scored[:limit]
    print(f"Local search: {len(top)} matches above threshold {SCORE_THRESHOLD}.")

    matched_stories = []
    for doc, score in top:
        story_id = doc.get("story_id")
        try:
            full_story = stories_collection.find_one({"_id": ObjectId(story_id)})
            if full_story:
                full_story["_id"] = str(full_story["_id"])
                full_story["search_score"] = score
                matched_stories.append(full_story)
        except Exception as e:
            print(f"Error fetching story {story_id}: {e}")

    return matched_stories


# =========================================================
#  UTILITY: RESET AND REBUILD INDEX
# =========================================================
def index_all_stories():
    """Drop and rebuild the entire story index. Run manually when needed."""
    print("Rebuilding story index from scratch...")
    story_index_collection.drop()
    sync_new_stories()
