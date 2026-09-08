"""프롬프트 인젝션·SSRF 방어층.

- make_path_guard: PreToolUse 훅. 파일 도구를 요청별 workspace 안으로만 제한.
- _SafeResolver / download_to_workspace / make_tools_server:
  URL 파일 다운로드 도구. 스킴·사설IP(SSRF)·DNS 리바인딩·크기·리다이렉트 방어.
"""

from __future__ import annotations

import asyncio
import ipaddress
import os
import socket
from pathlib import Path
from urllib.parse import urljoin, urlparse

import aiohttp
from aiohttp.abc import AbstractResolver
from aiohttp.resolver import ThreadedResolver

from claude_agent_sdk import create_sdk_mcp_server, tool

from .config import (
    DOWNLOAD_MAX_BYTES,
    DOWNLOAD_MAX_REDIRECTS,
    DOWNLOAD_TIMEOUT,
    PATH_SCOPED_TOOLS,
    log,
)
from .workspace import _unique_path, sanitize_filename


# ── 경로 제한 훅 (프롬프트 인젝션 방지) ────────────────────────────────────

def _is_within(path: str, root_norm: str) -> bool:
    """path 가 root(정규화된 절대경로) 안에 있는지."""
    if not path:
        return False
    try:
        rp = os.path.normcase(os.path.realpath(path))
    except Exception:
        return False
    return rp == root_norm or rp.startswith(root_norm + os.sep)


def make_path_guard(workspace: Path):
    """PreToolUse 훅: Read/Write/Glob/Grep 이 workspace 밖을 건드리면 거부."""
    root_norm = os.path.normcase(os.path.realpath(str(workspace)))

    async def guard(input_data, tool_use_id, context):
        tool_name = input_data.get("tool_name", "")
        if tool_name not in PATH_SCOPED_TOOLS:
            return {}
        ti = input_data.get("tool_input", {}) or {}
        target = ti.get("file_path") or ti.get("path") or ""
        if _is_within(target, root_norm):
            return {}
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": (
                    f"공유 workspace 폴더 밖은 접근할 수 없습니다. "
                    f"허용 폴더: {workspace}  (요청 경로: {target or '없음'})"
                ),
            }
        }

    return guard


# ── SSRF / DNS 리바인딩 방어 + URL 다운로드 ────────────────────────────────

def _ip_is_blocked(ip: str) -> bool:
    """공인망 IP가 아니면 True (사설/루프백/링크로컬/예약/멀티캐스트 차단)."""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return True
    return (not addr.is_global) or addr.is_private or addr.is_loopback \
        or addr.is_link_local or addr.is_reserved or addr.is_multicast


class _SafeResolver(AbstractResolver):
    """
    DNS 리바인딩 방지용 리졸버.
    aiohttp 가 '실제 연결에 사용할' 주소 해석을 이 자리에서 검증하므로,
    사전 검사(_url_host_is_safe)와 연결이 서로 다른 IP를 볼 수 없다 (TOCTOU 제거).
    """

    def __init__(self) -> None:
        self._inner = ThreadedResolver()

    async def resolve(self, *args, **kwargs):
        # aiohttp 버전별 시그니처 차이를 피하려 내부 리졸버로 그대로 위임
        infos = await self._inner.resolve(*args, **kwargs)
        safe = [info for info in infos if not _ip_is_blocked(info["host"])]
        if not safe:
            host = args[0] if args else kwargs.get("host", "?")
            raise OSError(f"차단: {host} 이(가) 사설/내부 주소로 해석됨 (SSRF/DNS 리바인딩 방지)")
        return safe

    async def close(self) -> None:
        await self._inner.close()


async def _url_host_is_safe(url: str) -> tuple[bool, str]:
    """스킴 확인 + 호스트의 모든 IP가 공인망인지 사전 검사 (빠른 거부용).
    최종 방어는 연결 시점의 _SafeResolver 가 담당한다 (DNS 리바인딩 대비)."""
    try:
        u = urlparse(url)
    except Exception:
        return False, "URL 파싱 실패"
    if u.scheme not in ("http", "https"):
        return False, f"허용되지 않은 스킴({u.scheme or '없음'}) — http/https 만 가능"
    host = u.hostname
    if not host:
        return False, "호스트 없음"
    port = u.port or (443 if u.scheme == "https" else 80)
    try:
        infos = await asyncio.to_thread(socket.getaddrinfo, host, port, 0, socket.SOCK_STREAM)
    except Exception as exc:  # noqa: BLE001
        return False, f"DNS 조회 실패: {exc}"
    for info in infos:
        if _ip_is_blocked(info[4][0]):
            return False, f"사설/내부 주소 차단(SSRF 방지): {info[4][0]}"
    return True, "ok"


async def download_to_workspace(url: str, filename: str, workspace: Path) -> tuple[bool, str]:
    """URL 파일을 안전 검사 후 workspace 에 저장. (스킴/SSRF/크기/리다이렉트 방어)"""
    current = url
    timeout = aiohttp.ClientTimeout(total=DOWNLOAD_TIMEOUT)
    # 연결 시점 IP 검증(_SafeResolver) + DNS 캐시 비활성화로 매 연결마다 재검증 → DNS 리바인딩 차단
    connector = aiohttp.TCPConnector(resolver=_SafeResolver(), use_dns_cache=False)
    try:
        async with aiohttp.ClientSession(timeout=timeout, connector=connector) as session:
            for _ in range(DOWNLOAD_MAX_REDIRECTS + 1):
                ok, reason = await _url_host_is_safe(current)   # 사전 빠른 거부(스킴 포함)
                if not ok:
                    return False, f"거부: {reason}"
                async with session.get(current, allow_redirects=False) as resp:
                    if resp.status in (301, 302, 303, 307, 308):
                        loc = resp.headers.get("Location")
                        if not loc:
                            return False, "거부: 리다이렉트 위치 없음"
                        current = urljoin(current, loc)   # 다음 루프에서 IP 재검증
                        continue
                    if resp.status != 200:
                        return False, f"거부: HTTP {resp.status}"
                    clen = resp.headers.get("Content-Length", "")
                    if clen.isdigit() and int(clen) > DOWNLOAD_MAX_BYTES:
                        return False, f"거부: 파일이 너무 큼 ({int(clen) // 1048576}MB > {DOWNLOAD_MAX_BYTES // 1048576}MB)"
                    base = sanitize_filename(filename or os.path.basename(urlparse(current).path))
                    if not base or base == "file":
                        base = "download"
                    target = _unique_path(workspace, base)
                    total = 0
                    try:
                        with open(target, "wb") as fh:
                            async for chunk in resp.content.iter_chunked(65536):
                                total += len(chunk)
                                if total > DOWNLOAD_MAX_BYTES:
                                    fh.close()
                                    target.unlink(missing_ok=True)
                                    return False, f"거부: 파일이 너무 큼 (>{DOWNLOAD_MAX_BYTES // 1048576}MB)"
                                fh.write(chunk)
                    except OSError as exc:
                        return False, f"저장 실패: {exc}"
                    ctype = resp.headers.get("Content-Type", "?").split(";")[0]
                    return True, f"저장 완료: {target.name} ({total} bytes, {ctype})"
            return False, "거부: 리다이렉트가 너무 많음"
    except asyncio.TimeoutError:
        return False, "거부: 다운로드 시간 초과"
    except aiohttp.ClientError as exc:
        return False, f"다운로드 실패: {exc}"


def make_tools_server(workspace: Path):
    """요청별 workspace 를 캡처한 커스텀 MCP 도구 서버 (파일 다운로드)."""

    @tool(
        "download_file",
        "Download a file (image, PDF, document, etc.) from an http(s) URL and save it into the "
        "shared workspace so it is sent to the user as a Discord attachment. Use when the user "
        "asks you to send/attach a file found on the web. Give a descriptive filename with the "
        "correct extension. The fetch is safety-checked (scheme, size, private-IP/SSRF).",
        {"url": str, "filename": str},
    )
    async def download_file(args):
        url = str(args.get("url", "")).strip()
        filename = str(args.get("filename", "")).strip()
        if not url:
            return {"content": [{"type": "text", "text": "url 인자가 필요합니다."}], "is_error": True}
        ok, msg = await download_to_workspace(url, filename, workspace)
        log.info("download_file: %s -> %s", url[:80], msg)
        return {"content": [{"type": "text", "text": msg}], "is_error": not ok}

    return create_sdk_mcp_server(name="files", version="1.0.0", tools=[download_file])
