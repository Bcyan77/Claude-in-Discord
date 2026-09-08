"""영속 저장소: 대화 세션 매핑(SessionStore) + 사용량 집계(UsageStore)."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from .config import USAGE_WINDOW_SEC, log


class SessionStore:
    """채널 ID → Claude 세션 ID 매핑을 파일로 영속화."""

    def __init__(self, path: Path):
        self.path = path
        self._data: dict[str, str] = {}
        self._load()

    def _load(self) -> None:
        try:
            self._data = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            self._data = {}
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("세션 파일을 읽지 못해 새로 시작합니다: %s", exc)
            self._data = {}

    def _save(self) -> None:
        try:
            self.path.write_text(
                json.dumps(self._data, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError as exc:
            log.warning("세션 파일 저장 실패: %s", exc)

    def get(self, channel_id: int) -> str | None:
        return self._data.get(str(channel_id))

    def set(self, channel_id: int, session_id: str) -> None:
        self._data[str(channel_id)] = session_id
        self._save()

    def clear(self, channel_id: int) -> bool:
        removed = self._data.pop(str(channel_id), None)
        if removed is not None:
            self._save()
        return removed is not None


_USAGE_FIELD_MAP = (
    ("inputTokens", "input"),
    ("outputTokens", "output"),
    ("cacheReadInputTokens", "cache_read"),
    ("cacheCreationInputTokens", "cache_creation"),
    ("webSearchRequests", "web_search"),
)


class UsageStore:
    """ResultMessage.model_usage 를 누적해 usage.json 에 저장. 최근 5시간 창도 유지."""

    def __init__(self, path: Path):
        self.path = path
        self._data: dict = {
            "started_at": None, "requests": 0, "turns": 0,
            "total": {}, "per_model": {}, "recent": [],
        }
        self._load()
        if not self._data.get("started_at"):
            self._data["started_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
            self._save()

    def _load(self) -> None:
        try:
            self._data.update(json.loads(self.path.read_text(encoding="utf-8")))
        except FileNotFoundError:
            pass
        except (json.JSONDecodeError, OSError) as exc:
            log.warning("사용량 파일을 읽지 못해 새로 시작합니다: %s", exc)

    def _save(self) -> None:
        try:
            self.path.write_text(
                json.dumps(self._data, ensure_ascii=False, indent=2), encoding="utf-8"
            )
        except OSError as exc:
            log.warning("사용량 저장 실패: %s", exc)

    def record(self, model_usage: dict | None, num_turns: int, now: float) -> None:
        self._data["requests"] = self._data.get("requests", 0) + 1
        self._data["turns"] = self._data.get("turns", 0) + int(num_turns or 0)
        total = self._data.setdefault("total", {})
        per_model = self._data.setdefault("per_model", {})
        req_cost = 0.0
        req_tokens = 0
        for model, u in (model_usage or {}).items():
            if not isinstance(u, dict):
                continue
            pm = per_model.setdefault(model, {})
            for src, dst in _USAGE_FIELD_MAP:
                val = int(u.get(src, 0) or 0)
                pm[dst] = pm.get(dst, 0) + val
                total[dst] = total.get(dst, 0) + val
                if dst in ("input", "output"):
                    req_tokens += val
            cost = float(u.get("costUSD", 0) or 0)
            pm["cost_usd"] = round(pm.get("cost_usd", 0.0) + cost, 6)
            pm["requests"] = pm.get("requests", 0) + 1
            total["cost_usd"] = round(total.get("cost_usd", 0.0) + cost, 6)
            req_cost += cost
        recent = self._data.setdefault("recent", [])
        recent.append([int(now), round(req_cost, 6), req_tokens])
        cutoff = now - USAGE_WINDOW_SEC
        self._data["recent"] = [r for r in recent if r and r[0] >= cutoff]
        self._save()

    def summary(self, now: float) -> dict:
        cutoff = now - USAGE_WINDOW_SEC
        recent = [r for r in self._data.get("recent", []) if r and r[0] >= cutoff]
        return {
            "started_at": self._data.get("started_at"),
            "requests": self._data.get("requests", 0),
            "turns": self._data.get("turns", 0),
            "total": self._data.get("total", {}),
            "per_model": self._data.get("per_model", {}),
            "recent_requests": len(recent),
            "recent_cost": round(sum(r[1] for r in recent), 4),
            "recent_tokens": sum(r[2] for r in recent),
        }
