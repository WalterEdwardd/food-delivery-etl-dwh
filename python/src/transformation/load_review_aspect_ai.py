"""
Module: load_review_aspect_ai.py
Purpose: AI-Powered Aspect-Based Sentiment Analysis (ABSA) ETL Pipeline.
         Extracts granular aspect sentiments from customer reviews using Google Gemini 2.5 Flash,
         caches results in ref.ref_review_aspect_cache, and loads dwh.fact_review_aspect.
"""

import os
import sys
import hashlib
import json
import time
import requests
from typing import List, Dict, Any

# Ensure project root / python directory is in sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from src.config import settings
from src.config.database import get_connection
from src.utils.logger import get_logger

logger = get_logger("load_review_aspect_ai")

SYSTEM_INSTRUCTION = """You are an expert Data Warehouse ABSA (Aspect-Based Sentiment Analysis) engine for food delivery platforms.
Your task is to analyze customer feedback and extract ALL mentioned service aspects along with their specific sentiment polarity.

Aspect Dimensions:
1: Food Quality (taste, temperature, freshness, cooking quality, texture)
2: Delivery Service (speed, arrival time, rider punctuality/transit, delivery handling)
3: Customer Support (service, agent responsiveness, refund, dispute resolution, staff behavior)
4: Packaging (spills, damaged containers, bag condition, sealing)
5: Portion & Value (serving size, food quantity, price, value for money)
6: Food Safety (hygiene, foreign objects, mold, contamination, food illness)
0: Unknown (general sentiment with no specific aspect mentioned, e.g., 'Loved it!', 'Worst order', 'Never again')

Sentiment Dimensions:
1: Positive
2: Neutral
3: Negative

Rules:
1. If a review mentions multiple aspects (e.g. 'Tasty but a bit late'), extract BOTH aspects as separate entries:
   - Food Quality -> Positive (phrase: 'Tasty')
   - Delivery Service -> Negative (phrase: 'a bit late')
2. For matched_phrase, return the exact word or sub-phrase from the review text representing that aspect.
3. Return a JSON object with a single key 'results' mapping to an array of objects:
   {"results": [{"review_text": "...", "aspects": [{"aspect_id": 1, "sentiment_type_id": 1, "matched_phrase": "..."}]}]}
"""


def compute_sha256(text: str) -> str:
    """Compute SHA-256 hash of normalized lowercase trimmed text."""
    return hashlib.sha256(text.strip().lower().encode("utf-8")).hexdigest()


def ensure_cache_table(conn) -> None:
    """Ensure the ref.ref_review_aspect_cache table exists in the database."""
    ddl = """
    IF NOT EXISTS (
        SELECT 1 FROM sys.tables t 
        JOIN sys.schemas s ON t.schema_id = s.schema_id 
        WHERE s.name = 'ref' AND t.name = 'ref_review_aspect_cache'
    )
    BEGIN
        CREATE TABLE ref.ref_review_aspect_cache
        (
            review_hash          CHAR(64)             NOT NULL,
            review_text          VARCHAR(2000)        NOT NULL,
            aspect_id            TINYINT              NOT NULL,
            sentiment_type_id    TINYINT              NOT NULL,
            matched_phrase       VARCHAR(200)         NULL,
            ai_model             VARCHAR(50)          NOT NULL,
            created_at           DATETIME2(3)         NOT NULL
                CONSTRAINT DF_ref_review_aspect_cache_created_at DEFAULT SYSUTCDATETIME(),

            CONSTRAINT PK_ref_review_aspect_cache
                PRIMARY KEY CLUSTERED (review_hash, aspect_id, sentiment_type_id)
        );
        CREATE NONCLUSTERED INDEX IX_ref_review_aspect_cache_hash
            ON ref.ref_review_aspect_cache (review_hash);
    END
    """
    with conn.cursor() as cur:
        cur.execute(ddl)
        conn.commit()


def call_gemini_absa(reviews: List[str], api_key: str, preferred_model: str = "gemini-2.5-flash") -> List[Dict[str, Any]]:
    """
    Send a batch of reviews to Gemini API requesting structured ABSA extraction.
    Supports smart fallback cascade across candidate models for maximum compatibility.
    """
    candidate_models = [preferred_model]
    for fallback in ["gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"]:
        if fallback not in candidate_models:
            candidate_models.append(fallback)

    last_error = None
    prompt = f"{SYSTEM_INSTRUCTION}\n\nReviews to analyze:\n"
    for idx, r in enumerate(reviews, 1):
        prompt += f"{idx}. \"{r}\"\n"

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "response_mime_type": "application/json"
        }
    }

    for current_model in candidate_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{current_model}:generateContent?key={api_key}"
        try:
            response = requests.post(url, json=payload, timeout=60)
            if response.status_code == 200:
                resp_json = response.json()
                part_text = resp_json["candidates"][0]["content"]["parts"][0]["text"]
                parsed = json.loads(part_text)
                if isinstance(parsed, dict) and "results" in parsed:
                    return parsed["results"]
                elif isinstance(parsed, list):
                    return parsed
                else:
                    return []
            else:
                logger.warning(
                    f"Model '{current_model}' returned status {response.status_code}. "
                    f"Attempting fallback to next model..."
                )
                last_error = f"Status {response.status_code}: {response.text[:200]}"
        except Exception as exc:
            logger.warning(f"Error calling model '{current_model}': {exc}. Attempting fallback...")
            last_error = str(exc)

    raise RuntimeError(f"All candidate Gemini models failed. Last error: {last_error}")


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE_FILE_PATH = os.path.join(PROJECT_ROOT, "data", "reference", "ai_review_aspect_cache.json")


def sync_disk_to_cache(conn) -> int:
    """
    Seed or synchronize ref.ref_review_aspect_cache from the JSON file on disk.
    Ensures zero external API dependency when running tests or in offline environments.
    """
    if not os.path.exists(CACHE_FILE_PATH):
        logger.warning(f"Cache file not found at: {CACHE_FILE_PATH}")
        return 0

    try:
        with open(CACHE_FILE_PATH, "r", encoding="utf-8") as f:
            cached_data = json.load(f)
    except Exception as exc:
        logger.error(f"Failed to read cache file {CACHE_FILE_PATH}: {exc}")
        return 0

    inserted_count = 0
    insert_sql = """
    IF NOT EXISTS (
        SELECT 1 FROM ref.ref_review_aspect_cache 
        WHERE review_hash = ? AND aspect_id = ? AND sentiment_type_id = ?
    )
    BEGIN
        INSERT INTO ref.ref_review_aspect_cache
        (review_hash, review_text, aspect_id, sentiment_type_id, matched_phrase, ai_model, created_at)
        VALUES (?, ?, ?, ?, ?, ?, SYSUTCDATETIME());
    END
    """
    with conn.cursor() as cur:
        for row in cached_data:
            h, txt, aid, sid, phrase, mdl = row
            cur.execute(insert_sql, (h, aid, sid, h, txt, aid, sid, phrase, mdl))
            inserted_count += cur.rowcount
        conn.commit()

    if inserted_count > 0:
        logger.info(f"Loaded {inserted_count} review aspect cache records from disk ({CACHE_FILE_PATH}).")
    return inserted_count


def sync_cache_to_disk(conn) -> int:
    """
    Export the current database cache table back to data/reference/ai_review_aspect_cache.json.
    Ensures the disk backup file remains the self-enriching Single Source of Truth as new reviews arrive.
    """
    query = """
    SELECT review_hash, review_text, aspect_id, sentiment_type_id, matched_phrase, ai_model
    FROM ref.ref_review_aspect_cache
    ORDER BY review_text, aspect_id, sentiment_type_id
    """
    with conn.cursor() as cur:
        cur.execute(query)
        rows = cur.fetchall()

    cache_list = [
        [
            r[0].strip() if r[0] else "",
            r[1],
            int(r[2]),
            int(r[3]),
            r[4] if r[4] else "",
            r[5] if r[5] else "gemini-2.5-flash",
        ]
        for r in rows
    ]

    os.makedirs(os.path.dirname(CACHE_FILE_PATH), exist_ok=True)
    with open(CACHE_FILE_PATH, "w", encoding="utf-8") as f:
        json.dump(cache_list, f, ensure_ascii=False, indent=2)

    logger.info(f"Synchronized {len(cache_list)} cache records to {CACHE_FILE_PATH}.")
    return len(cache_list)


def populate_ai_cache(conn, batch_id: int = 1) -> int:
    """
    Check for uncached distinct reviews and analyze them with Gemini (or fallback).
    Automatically maintains two-way sync between database cache and data/reference/ai_review_aspect_cache.json.
    """
    ensure_cache_table(conn)
    sync_disk_to_cache(conn)

    # 1. Fetch all distinct reviews currently in fact_rating
    with conn.cursor() as cur:
        cur.execute("SELECT DISTINCT review_text FROM dwh.fact_rating WHERE review_text IS NOT NULL AND LTRIM(RTRIM(review_text)) <> ''")
        all_reviews = [row[0].strip() for row in cur.fetchall()]

    logger.info(f"Found {len(all_reviews)} distinct review texts in dwh.fact_rating.")

    # 2. Check which reviews are already cached
    with conn.cursor() as cur:
        cur.execute("SELECT DISTINCT review_hash FROM ref.ref_review_aspect_cache")
        cached_hashes = set(row[0].strip() for row in cur.fetchall())

    uncached_reviews = [r for r in all_reviews if compute_sha256(r) not in cached_hashes]
    logger.info(f"Uncached reviews needing AI analysis: {len(uncached_reviews)}.")

    if not uncached_reviews:
        logger.info("All reviews already exist in ref.ref_review_aspect_cache. Zero API calls needed!")
        return 0

    api_key = settings.GEMINI_API_KEY
    model = settings.GEMINI_MODEL or "gemini-2.5-flash"
    new_cache_rows = []

    if api_key:
        # 3. Process uncached reviews in batches of 15 using Gemini
        batch_size = 15
        for i in range(0, len(uncached_reviews), batch_size):
            chunk = uncached_reviews[i : i + batch_size]
            logger.info(f"Sending batch of {len(chunk)} reviews to Gemini ({model})...")
            try:
                results = call_gemini_absa(chunk, api_key, model)
                norm_map = {compute_sha256(r): r for r in chunk}
                for item in results:
                    orig_text = item.get("review_text", "").strip()
                    item_hash = compute_sha256(orig_text)
                    matched_orig = norm_map.get(item_hash)
                    if not matched_orig:
                        for h, t in norm_map.items():
                            if t.lower() in orig_text.lower() or orig_text.lower() in t.lower():
                                matched_orig = t
                                item_hash = h
                                break
                    target_text = matched_orig if matched_orig else orig_text
                    aspects = item.get("aspects", [])
                    for asp in aspects:
                        new_cache_rows.append((
                            item_hash,
                            target_text,
                            int(asp.get("aspect_id", 0)),
                            int(asp.get("sentiment_type_id", 0)),
                            asp.get("matched_phrase", "")[:200],
                            model
                        ))
            except Exception as exc:
                logger.warning(f"Gemini API call failed: {exc}. Falling back to default aspect classification.")
                for r in chunk:
                    new_cache_rows.append((
                        compute_sha256(r),
                        r,
                        0,
                        2,
                        r[:200],
                        "offline-fallback"
                    ))
    else:
        logger.warning(f"GEMINI_API_KEY is not configured. Falling back to default aspect classification for {len(uncached_reviews)} reviews.")
        for r in uncached_reviews:
            new_cache_rows.append((
                compute_sha256(r),
                r,
                0,
                2,
                r[:200],
                "offline-fallback"
            ))

    # 4. Insert into ref.ref_review_aspect_cache
    if new_cache_rows:
        logger.info(f"Inserting {len(new_cache_rows)} aspect extractions into ref.ref_review_aspect_cache...")
        insert_sql = """
        IF NOT EXISTS (
            SELECT 1 FROM ref.ref_review_aspect_cache 
            WHERE review_hash = ? AND aspect_id = ? AND sentiment_type_id = ?
        )
        BEGIN
            INSERT INTO ref.ref_review_aspect_cache
            (review_hash, review_text, aspect_id, sentiment_type_id, matched_phrase, ai_model, created_at)
            VALUES (?, ?, ?, ?, ?, ?, SYSUTCDATETIME());
        END
        """
        with conn.cursor() as cur:
            for row in new_cache_rows:
                h, txt, aid, sid, phrase, mdl = row
                cur.execute(insert_sql, (h, aid, sid, h, txt, aid, sid, phrase, mdl))
            conn.commit()

        # 5. Automatically synchronize updated cache back to disk JSON file!
        sync_cache_to_disk(conn)

    return len(new_cache_rows)


def load_fact_review_aspect(batch_id: int = 1) -> Dict[str, Any]:
    """
    Main orchestrator for loading dwh.fact_review_aspect:
    1. Populates AI cache if new reviews are present (Gemini ABSA).
    2. Runs production stored procedure dwh.usp_load_fact_review_aspect.
    """
    start_time = time.time()
    conn = get_connection()
    try:
        # Step 1: Ensure AI Cache is up to date
        new_cached = populate_ai_cache(conn, batch_id)
        
        # Step 2: Execute DWH procedure
        logger.info(f"Calling dwh.usp_load_fact_review_aspect for batch {batch_id}...")
        with conn.cursor() as cur:
            cur.execute("SET NOCOUNT ON; EXEC dwh.usp_load_fact_review_aspect @batch_id = ?", (batch_id,))
            conn.commit()

        # Step 3: Count total rows in dwh.fact_review_aspect
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM dwh.fact_review_aspect")
            total_fact_rows = cur.fetchone()[0]

        duration = time.time() - start_time
        logger.info(
            f"Successfully executed load_fact_review_aspect in {duration:.2f}s: "
            f"NewCached={new_cached}, TotalFactRows={total_fact_rows}."
        )

        return {
            "status": "SUCCESS",
            "new_cached": new_cached,
            "total_fact_rows": total_fact_rows,
            "duration_sec": duration
        }

    except Exception as exc:
        logger.exception("Error in load_fact_review_aspect: %s", exc)
        if conn:
            conn.rollback()
        raise exc
    finally:
        if conn:
            conn.close()



if __name__ == "__main__":
    result = load_fact_review_aspect(batch_id=1)
    print("Execution Result:", json.dumps(result, indent=2))
