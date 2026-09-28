"""
Database connection module for healthcare-sim app.
Uses kailash-dataflow for database operations.
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

from kailash_dataflow import DataFlowPool, NodeConfig

# Database URL from environment — .env is the single source of truth
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:password@localhost:5432/test"
)


@dataclass
class DatabaseConfig:
    """Database configuration loaded from environment."""
    url: str = DATABASE_URL
    pool_size: int = int(os.getenv("DB_POOL_SIZE", "5"))
    timeout: int = int(os.getenv("DB_TIMEOUT", "30"))


def create_pool(config: DatabaseConfig | None = None) -> DataFlowPool:
    """
    Create a DataFlowPool for database operations.

    Args:
        config: Optional DatabaseConfig. If None, loads from environment.

    Returns:
        DataFlowPool configured and ready for operations.
    """
    if config is None:
        config = DatabaseConfig()

    pool = DataFlowPool(
        url=config.url,
        min_size=1,
        max_size=config.pool_size,
        timeout=config.timeout,
    )
    return pool


# Singleton pool instance
_pool: DataFlowPool | None = None


def get_pool() -> DataFlowPool:
    """Get or create the singleton DataFlowPool instance."""
    global _pool
    if _pool is None:
        _pool = create_pool()
    return _pool


def close_pool() -> None:
    """Close the singleton pool if it exists."""
    global _pool
    if _pool is not None:
        _pool.close()
        _pool = None


class QuestionRepository:
    """
    Repository for question/scene CRUD operations using DataFlowPool.
    """

    def __init__(self, pool: DataFlowPool | None = None):
        self.pool = pool or get_pool()

    async def get_all_scenes(self) -> list[dict[str, Any]]:
        """
        Fetch all scenes with their questions from the database.

        Returns:
            List of scene dictionaries with nested questions.
        """
        query = """
            SELECT
                s.id as scene_id,
                s.title as scene_title,
                s.subtitle as scene_subtitle,
                s.description as scene_description,
                s.image_url as scene_image_url,
                s.image_description as scene_image_description,
                q.id as question_id,
                q.text as question_text,
                q.option_a,
                q.option_b,
                q.option_c,
                q.option_d,
                q.correct_answer,
                q.explanation as question_explanation,
                q.image_url as question_image_url,
                q.image_description as question_image_description
            FROM scenes s
            LEFT JOIN questions q ON q.scene_id = s.id
            ORDER BY s.id, q.id
        """

        node_config = NodeConfig(query=query, fetch_all=True)
        result = await self.pool.execute_node("query", node_config)

        if not result:
            return []

        return self._group_by_scene(result)

    def _group_by_scene(self, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Group question rows into scene objects."""
        scenes_map: dict[int, dict[str, Any]] = {}

        for row in rows:
            scene_id = row.get("scene_id")
            if scene_id is None:
                continue

            if scene_id not in scenes_map:
                scenes_map[scene_id] = {
                    "id": str(scene_id),
                    "title": row.get("scene_title") or "Untitled",
                    "subtitle": row.get("scene_subtitle") or "",
                    "description": row.get("scene_description") or "",
                    "imageUrl": row.get("scene_image_url") or "",
                    "imageDescription": row.get("scene_image_description") or "",
                    "questions": [],
                }

            if row.get("question_id"):
                scenes_map[scene_id]["questions"].append({
                    "id": row["question_id"],
                    "text": row.get("question_text") or "",
                    "options": [
                        {"id": "a", "text": row.get("option_a") or ""},
                        {"id": "b", "text": row.get("option_b") or ""},
                        {"id": "c", "text": row.get("option_c") or ""},
                        {"id": "d", "text": row.get("option_d") or ""},
                    ],
                    "correct": (row.get("correct_answer") or "a").lower(),
                    "explanation": row.get("question_explanation") or "",
                    "imageUrl": row.get("question_image_url") or "",
                    "imageDescription": row.get("question_image_description") or "",
                })

        return list(scenes_map.values())


class ScoreRepository:
    """
    Repository for saving/restoring learner scores using DataFlowPool.
    """

    def __init__(self, pool: DataFlowPool | None = None):
        self.pool = pool or get_pool()

    async def save_score(
        self,
        session_id: str,
        total_score: int,
        max_score: int,
        scene_scores: dict[str, int],
    ) -> str:
        """
        Save a learner's session score.

        Args:
            session_id: Unique session identifier.
            total_score: Total points earned.
            max_score: Maximum possible points.
            scene_scores: Per-scene score breakdown.

        Returns:
            The session_id of the saved record.
        """
        mutation = """
            INSERT INTO scores (session_id, total_score, max_score, scene_scores, completed_at)
            VALUES (:session_id, :total_score, :max_score, :scene_scores, NOW())
            ON CONFLICT (session_id) DO UPDATE
            SET total_score = EXCLUDED.total_score,
                max_score = EXCLUDED.max_score,
                scene_scores = EXCLUDED.scene_scores,
                completed_at = NOW()
        """

        node_config = NodeConfig(
            query=mutation,
            params={
                "session_id": session_id,
                "total_score": total_score,
                "max_score": max_score,
                "scene_scores": str(scene_scores),
            },
        )

        await self.pool.execute_node("mutation", node_config)
        return session_id

    async def get_score(self, session_id: str) -> dict[str, Any] | None:
        """Retrieve a score by session ID."""
        query = """
            SELECT session_id, total_score, max_score, scene_scores, completed_at
            FROM scores
            WHERE session_id = :session_id
        """

        node_config = NodeConfig(query=query, params={"session_id": session_id}, fetch_one=True)
        result = await self.pool.execute_node("query", node_config)
        return result
