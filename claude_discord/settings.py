"""환경설정 로드 (.env → 실행 설정 dict)."""

from __future__ import annotations

import os
import sys

from dotenv import load_dotenv

from .config import (
    BASE_DIR,
    DEFAULT_CACHE_MB,
    DEFAULT_LINK_PREVIEW_HOSTS,
    DEFAULT_MODEL,
    GAME_DEFAULT_FAIL_THRESHOLD,
    GAME_DEFAULT_POLL_SEC,
    GAME_MIN_POLL_SEC,
    _int_env,
    log,
)
from .persona import compose_system_prompt, load_persona


def _link_preview_hosts() -> tuple[str, ...]:
    """링크 미리보기를 허용할 호스트. 비움=기본(유튜브) · none=전부 차단 · *=전부 허용."""
    raw = os.environ.get("LINK_PREVIEW_HOSTS", "").strip()
    if not raw:
        return DEFAULT_LINK_PREVIEW_HOSTS
    if raw.lower() == "none":
        return ()
    return tuple(h.strip().lower().lstrip(".") for h in raw.split(",") if h.strip())


def _learn_allow_users() -> tuple[str, ...]:
    """`/기억 학습` 을 관리 권한 없이도 쓸 수 있는 계정 목록 (콤마 구분).

    사용자 ID(숫자) 또는 사용자명(`example_user`) 을 넣는다. ID 가 안전하다 — 사용자명은 바뀔 수 있다.
    """
    raw = os.environ.get("MEMORY_LEARN_USERS", "").strip()
    return tuple(
        t.strip().lstrip("@").lower() for t in raw.split(",") if t.strip().lstrip("@")
    )


def _application_id() -> str:
    """봇 초대 링크에 쓸 Discord 애플리케이션 ID (env DISCORD_APPLICATION_ID).

    비우면 로그인 후 봇 계정 ID 로 대체한다 — 봇 유저 ID 는 애플리케이션 ID 와 같아서
    보통은 설정할 필요가 없다. 초대 링크 로그에만 쓰이므로 틀려도 봇 동작엔 영향 없음.
    """
    raw = os.environ.get("DISCORD_APPLICATION_ID", "").strip()
    if raw and not raw.isdigit():
        log.warning("DISCORD_APPLICATION_ID 값이 숫자가 아님(%r) — 봇 계정 ID 로 대체", raw)
        return ""
    return raw


def load_config() -> dict:
    load_dotenv(BASE_DIR / ".env")

    # ⚠️ 종량제 과금 방지: ANTHROPIC_API_KEY 가 있으면 서브프로세스로 새어나가지 않도록 제거.
    if os.environ.pop("ANTHROPIC_API_KEY", None) is not None:
        log.warning("ANTHROPIC_API_KEY 가 환경에 있어 제거했습니다. (구독 인증만 사용)")

    discord_token = os.environ.get("DISCORD_TOKEN", "").strip()
    if not discord_token:
        log.error("DISCORD_TOKEN 이 비어 있습니다. .env 파일에 봇 토큰을 넣어주세요.")
        sys.exit(1)

    if not os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "").strip():
        log.warning(
            "CLAUDE_CODE_OAUTH_TOKEN 이 비어 있습니다. "
            "로컬에 로그인된 Claude Code 인증으로 동작을 시도합니다. "
            "서버 배포 시에는 `claude setup-token` 으로 발급해 .env 에 넣으세요."
        )

    raw_cache = os.environ.get("WORKSPACE_CACHE_MB", "").strip()
    try:
        cache_mb = int(raw_cache) if raw_cache else DEFAULT_CACHE_MB
    except ValueError:
        log.warning("WORKSPACE_CACHE_MB 값이 잘못됨(%r) — 기본 %dMB 사용", raw_cache, DEFAULT_CACHE_MB)
        cache_mb = DEFAULT_CACHE_MB
    if cache_mb < 0:
        cache_mb = DEFAULT_CACHE_MB

    persona, persona_src = load_persona()
    log.info("시스템 프롬프트 페르소나 소스: %s", persona_src)

    return {
        "discord_token": discord_token,
        "model": os.environ.get("CLAUDE_MODEL", "").strip() or DEFAULT_MODEL,
        "cache_bytes": cache_mb * 1024 * 1024,   # 0 이면 무제한
        "system_prompt": compose_system_prompt(persona),
        "game_poll_sec": _int_env("GAME_POLL_SEC", GAME_DEFAULT_POLL_SEC, minimum=GAME_MIN_POLL_SEC),
        "game_fail_threshold": _int_env("GAME_FAIL_THRESHOLD", GAME_DEFAULT_FAIL_THRESHOLD, minimum=1),
        "link_preview_hosts": _link_preview_hosts(),
        "learn_allow_users": _learn_allow_users(),
        "application_id": _application_id(),
    }
