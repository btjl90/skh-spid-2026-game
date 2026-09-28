"""
Healthcare Sim API Service
Provides REST endpoints for the static SPA to fetch questions/scores from database.
"""
from __future__ import annotations

import uuid
from dataclasses import dataclass

from kailash_nexus import NexusServer, RouteConfig
from kailash_dataflow import DataFlowPool

from src.db import QuestionRepository, ScoreRepository, DatabaseConfig, create_pool


@dataclass
class ApiConfig:
    """API server configuration."""
    host: str = "0.0.0.0"
    port: int = 8000
    cors_origins: list[str] = None  # None = allow all (for dev)


class HealthcareSimApi:
    """
    REST API service for healthcare-sim frontend.
    Endpoints:
        GET  /api/scenes          - Fetch all scenes with questions
        GET  /api/health          - Health check
        POST /api/scores          - Save a score session
        GET  /api/scores/{id}     - Get a score by session ID
    """

    def __init__(self, config: ApiConfig | None = None, pool: DataFlowPool | None = None):
        self.config = config or ApiConfig()
        self.pool = pool or create_pool()
        self.question_repo = QuestionRepository(pool=self.pool)
        self.score_repo = ScoreRepository(pool=self.pool)
        self._server = None

    async def get_scenes(self, request) -> dict:
        """Fetch all scenes with questions from database."""
        scenes = await self.question_repo.get_all_scenes()
        return {
            "status": "success",
            "data": scenes,
            "count": len(scenes),
        }

    async def save_score(self, request) -> dict:
        """Save a score session."""
        body = await request.json()
        session_id = body.get("session_id") or str(uuid.uuid4())
        total_score = body.get("total_score", 0)
        max_score = body.get("max_score", 0)
        scene_scores = body.get("scene_scores", {})

        saved_id = await self.score_repo.save_score(
            session_id=session_id,
            total_score=total_score,
            max_score=max_score,
            scene_scores=scene_scores,
        )

        return {
            "status": "success",
            "session_id": saved_id,
        }

    async def get_score(self, request, session_id: str) -> dict:
        """Get a score by session ID."""
        score = await self.score_repo.get_score(session_id)
        if score is None:
            return {"status": "error", "message": "Score not found"}, 404
        return {"status": "success", "data": score}

    async def health_check(self, request) -> dict:
        """Health check endpoint."""
        return {"status": "healthy", "service": "healthcare-sim-api"}

    def setup_routes(self) -> list[RouteConfig]:
        """Define API routes."""
        return [
            RouteConfig("GET", "/api/health", self.health_check),
            RouteConfig("GET", "/api/scenes", self.get_scenes),
            RouteConfig("POST", "/api/scores", self.save_score),
            RouteConfig("GET", "/api/scores/{session_id}", self.get_score),
        ]

    async def start(self):
        """Start the API server."""
        self._server = NexusServer(
            host=self.config.host,
            port=self.config.port,
            routes=self.setup_routes(),
        )
        await self._server.start()
        return self._server

    async def stop(self):
        """Stop the API server."""
        if self._server:
            await self._server.stop()


# CLI entrypoint for running the API server
async def main():
    import os
    from dotenv import load_dotenv

    load_dotenv()  # Load .env for DATABASE_URL

    config = ApiConfig(
        host=os.getenv("API_HOST", "0.0.0.0"),
        port=int(os.getenv("API_PORT", "8000")),
    )

    api = HealthcareSimApi(config)
    print(f"Starting Healthcare Sim API on {config.host}:{config.port}")
    await api.start()


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
