"""요청별 workspace 파일 입출력 · 캐시 상한 유지 · 응답 길이 분할 · 링크 미리보기 억제."""

from __future__ import annotations

import os
import re
from pathlib import Path
from urllib.parse import urlsplit

import discord

from .config import CHUNK_LIMIT, DEFAULT_LINK_PREVIEW_HOSTS, MAX_ATTACH_BYTES, log


def sanitize_filename(name: str) -> str:
    base = os.path.basename(name or "").replace("\\", "_").replace("/", "_").strip()
    return base or "file"


def _unique_path(workspace: Path, name: str) -> Path:
    target = workspace / name
    if not target.exists():
        return target
    stem, suffix = target.stem, target.suffix
    i = 1
    while True:
        cand = workspace / f"{stem}-{i}{suffix}"
        if not cand.exists():
            return cand
        i += 1


async def download_attachments(message: discord.Message, dest: Path) -> list[Path]:
    saved: list[Path] = []
    for att in message.attachments:
        if att.size and att.size > MAX_ATTACH_BYTES:
            log.info("첨부 건너뜀(용량 초과): %s (%s bytes)", att.filename, att.size)
            continue
        target = dest / sanitize_filename(att.filename)
        try:
            await att.save(target)
            saved.append(target)
        except Exception as exc:  # noqa: BLE001
            log.warning("첨부 저장 실패 %s: %s", att.filename, exc)
    return saved


def collect_output_files(workspace: Path, exclude: set[Path]) -> list[Path]:
    """workspace 안에서 (다운로드한 첨부를 제외한) 파일들 = 에이전트 생성물/다운로드물."""
    out: list[Path] = []
    for p in sorted(workspace.rglob("*")):
        if p.is_file() and p.resolve() not in exclude:
            out.append(p)
    return out


def _remove_empty_dirs(root: Path) -> None:
    """root 하위의 빈 디렉터리 제거 (root 자체는 유지)."""
    for d in sorted(root.rglob("*"), reverse=True):
        if d.is_dir():
            try:
                d.rmdir()   # 비어있을 때만 성공
            except OSError:
                pass


def enforce_cache_limit(root: Path, max_bytes: int) -> None:
    """workspace 총량이 상한을 넘으면 가장 오래된 파일부터 순차 삭제. (동기 — 스레드에서 호출)"""
    if max_bytes <= 0:   # 0 = 무제한
        return
    files: list[tuple[float, int, Path]] = []
    total = 0
    for p in root.rglob("*"):
        if p.is_file():
            try:
                st = p.stat()
            except OSError:
                continue
            files.append((st.st_mtime, st.st_size, p))
            total += st.st_size
    if total <= max_bytes:
        return

    files.sort(key=lambda t: t[0])   # 오래된(mtime 작은) 것부터
    freed = 0
    for _mtime, size, p in files:
        if total <= max_bytes:
            break
        try:
            p.unlink()
            total -= size
            freed += size
        except OSError as exc:
            log.warning("캐시 파일 삭제 실패 %s: %s", p, exc)
    _remove_empty_dirs(root)
    log.info(
        "workspace 캐시 정리: %.1fMB 삭제 → 현재 %.1fMB / 상한 %.0fMB",
        freed / 1048576, total / 1048576, max_bytes / 1048576,
    )


def split_message(text: str, limit: int = CHUNK_LIMIT) -> list[str]:
    """긴 텍스트를 limit 이하 조각들로 분할. 줄/단어 경계 우선, 코드펜스 유지."""
    if len(text) <= limit:
        return [text]

    raw: list[str] = []
    remaining = text
    while len(remaining) > limit:
        window = remaining[:limit]
        cut = window.rfind("\n")
        if cut < limit // 2:
            cut = window.rfind(" ")
        if cut < limit // 2:
            cut = limit
        raw.append(remaining[:cut])
        remaining = remaining[cut:]
    if remaining.strip():
        raw.append(remaining)

    # 코드블록(```)이 조각 경계에서 잘리면 닫고 다음 조각에서 다시 열어 렌더 깨짐 방지
    chunks: list[str] = []
    carry_open = False
    for piece in raw:
        body = ("```\n" + piece) if carry_open else piece
        inside_fence = body.count("```") % 2 == 1
        if inside_fence:
            body = body + "\n```"
        carry_open = inside_fence
        chunks.append(body.strip("\n") or "​")  # 빈 조각 방지
    return chunks


# ── 링크 자동 미리보기(unfurl) 억제 ───────────────────────────────────────
# 코드 구간(``` 블록 / 인라인 코드)은 애초에 미리보기가 안 생기고, 손대면 코드가 깨진다 → 제외.
_CODE_SEGMENT_RE = re.compile(r"```.*?```|`[^`\n]*`", re.DOTALL)
_URL_RE = re.compile(r"<?https?://[^\s<>]+>?")
_URL_TRAILING = """.,;:!?"'”’"""


def _host_allowed(url: str, allow_hosts: tuple[str, ...]) -> bool:
    host = (urlsplit(url).hostname or "").lower()
    return any(host == h or host.endswith("." + h) for h in allow_hosts)


def _wrap_urls(part: str, allow_hosts: tuple[str, ...]) -> str:
    def repl(m: re.Match) -> str:
        raw = m.group(0)
        if raw.startswith("<"):          # 이미 <>로 감싼 링크는 그대로 둔다
            return raw
        url, trail = raw, ""
        while url and url[-1] in _URL_TRAILING:      # 문장부호는 URL 밖으로
            url, trail = url[:-1], url[-1] + trail
        while url.endswith(")") and url.count(")") > url.count("("):
            url, trail = url[:-1], ")" + trail       # 마크다운 링크 [글](url) 의 닫는 괄호
        if not url or _host_allowed(url, allow_hosts):
            return raw
        return f"<{url}>{trail}"
    return _URL_RE.sub(repl, part)


def suppress_link_previews(
    text: str, allow_hosts: tuple[str, ...] = DEFAULT_LINK_PREVIEW_HOSTS,
) -> str:
    """허용 호스트(기본: 유튜브) 외의 링크를 `<>` 로 감싸 Discord 자동 미리보기를 막는다.

    Discord 는 평문 메시지의 URL 을 자동으로 펼쳐 큰 미리보기 카드를 붙인다. 링크가 여러 개면
    답변보다 카드가 더 길어지므로 허용 호스트만 남긴다. `<url>` 은 Discord 가 꺾쇠를 지우고
    링크로만 렌더하므로 사용자에게 보이는 모양은 그대로다. (`*` 가 있으면 억제하지 않음)
    """
    if "*" in allow_hosts:
        return text
    out: list[str] = []
    pos = 0
    for m in _CODE_SEGMENT_RE.finditer(text):
        out.append(_wrap_urls(text[pos:m.start()], allow_hosts))
        out.append(m.group(0))
        pos = m.end()
    out.append(_wrap_urls(text[pos:], allow_hosts))
    return "".join(out)
