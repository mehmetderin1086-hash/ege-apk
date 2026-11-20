from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

from .db import Database
from .models import JobEvent


class EventBroker:
    def __init__(self, database: Database):
        self.database = database
        self._subscribers: set[asyncio.Queue[dict[str, Any] | None]] = set()

    async def publish(self, event_type: str, payload: dict[str, Any], job_id: str | None = None) -> int:
        async with self.database.sessions.begin() as session:
            event = JobEvent(job_id=job_id, event_type=event_type, payload=payload)
            session.add(event)
            await session.flush()
            event_id = event.id
        message = {"id": event_id, "event": event_type, "data": payload}
        for queue in tuple(self._subscribers):
            try:
                queue.put_nowait(message)
            except asyncio.QueueFull:
                try:
                    queue.get_nowait()
                    queue.put_nowait(message)
                except (asyncio.QueueEmpty, asyncio.QueueFull):
                    pass
        return event_id

    async def subscribe(self) -> AsyncIterator[dict[str, Any]]:
        queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue(maxsize=128)
        self._subscribers.add(queue)
        try:
            while True:
                message = await queue.get()
                if message is None:
                    break
                yield message
        finally:
            self._subscribers.discard(queue)

    def close_subscribers(self) -> None:
        """Wake long-lived SSE responses before Uvicorn starts graceful shutdown."""
        for queue in tuple(self._subscribers):
            try:
                queue.put_nowait(None)
            except asyncio.QueueFull:
                try:
                    queue.get_nowait()
                    queue.put_nowait(None)
                except (asyncio.QueueEmpty, asyncio.QueueFull):
                    pass
