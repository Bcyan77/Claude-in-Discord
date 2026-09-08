"""설정·상수·로깅 — 다른 앱 모듈에 의존하지 않는 최하위 레이어."""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

# ── 경로 ──────────────────────────────────────────────────────────────────
# 프로젝트 루트 = 이 파일(claude_discord/config.py)의 두 단계 상위.
# (데이터 파일들은 예전처럼 루트에 그대로 생성된다.)
BASE_DIR = Path(__file__).resolve().parent.parent
SESSIONS_FILE = BASE_DIR / "sessions.json"        # 채널 → 세션 ID 매핑 (재시작 후에도 맥락 유지)
WORKDIR = BASE_DIR / "agent_workdir"              # 에이전트 CLI 작업 폴더 (세션 저장 위치 고정용)
WORKSPACE_DIR = BASE_DIR / "workspace"            # 요청별 파일 입출력 폴더 (첨부/생성물)
USAGE_FILE = BASE_DIR / "usage.json"              # 사용량 누적 저장 (요청/토큰/비용)
WATCHES_FILE = BASE_DIR / "watches.json"          # 게임 서버 감시 목록 (채널→서버, 마지막 상태)
PERSONA_FILE = BASE_DIR / "system_prompt.md"      # 있으면 이 파일 내용을 페르소나로 사용
PROFILES_FILE = BASE_DIR / "profiles.json"        # (서버,사용자) → 기억해 둔 특징
GUILDS_FILE = BASE_DIR / "guilds.json"            # 서버(길드) → 서버 전체 분위기 메모

USAGE_WINDOW_SEC = 5 * 3600                        # "최근 N시간" 창 (구독 사용 한도 창과 동일하게 5시간)

# ── 동작 상수 ─────────────────────────────────────────────────────────────
DISCORD_LIMIT = 2000                               # Discord 메시지 길이 제한
CHUNK_LIMIT = 1990                                 # 분할 시 여유 마진

# 긴 답변 전송 형식 — 2000자 초과는 임베드 1개로(4096자까지), 그보다 길면 발췌 + 전문 첨부
EMBED_DESC_LIMIT = 4096                            # Discord 임베드 description 최대 길이
EMBED_COLOR = 0x5865F2                             # 임베드 좌측 바 색 (Discord blurple)
LONG_ANSWER_EXCERPT = 1800                         # 임베드에도 안 담길 때 본문에 보여줄 발췌 길이
ANSWER_FILE_NAME = "답변.md"                        # 전문을 담아 첨부할 파일명

# 링크 자동 미리보기(unfurl) 허용 호스트 — 이 목록 밖의 링크는 <>로 감싸 미리보기 카드를 막는다.
# env LINK_PREVIEW_HOSTS 로 변경 (콤마 구분 · 비우면 아래 기본값 · none=전부 차단 · *=전부 허용)
DEFAULT_LINK_PREVIEW_HOSTS = ("youtube.com", "youtu.be", "youtube-nocookie.com")
MAX_TURNS = 20                                     # 도구 사용(검색·읽기·쓰기) 여유 + 폭주 방지 상한
DEFAULT_MODEL = "sonnet"                           # CLAUDE_MODEL 미지정 시 기본 모델 (별칭 → 최신 Sonnet)
ALLOW_DM = False                                   # DM 대화 허용 여부 (False = 서버 채널 멘션만, DM 무시)
REQUEST_TIMEOUT = 240                              # 한 요청 처리 최대 시간(초)

# 도구 정책
ALLOWED_TOOLS = ["Read", "Write", "Glob", "Grep", "WebSearch", "WebFetch"]
DISALLOWED_TOOLS = ["Bash", "Edit", "NotebookEdit", "KillShell", "BashOutput", "Task"]
PATH_SCOPED_TOOLS = {"Read", "Write", "Glob", "Grep"}   # workspace 밖이면 거부할 도구

# 파일 전송 제한 (Discord 무료: 파일당·합계 25MB, 최대 10개)
MAX_SEND_FILES = 10
MAX_FILE_BYTES = 24 * 1024 * 1024
MAX_TOTAL_BYTES = 24 * 1024 * 1024
MAX_ATTACH_BYTES = 25 * 1024 * 1024                # 다운로드할 첨부 최대 크기
DEFAULT_CACHE_MB = 1024                             # workspace 캐시 기본 상한(MB). env WORKSPACE_CACHE_MB 로 변경 (0=무제한)

# URL 파일 다운로드 도구 (에이전트가 웹에서 찾은 파일을 workspace 로 받아 전송)
DOWNLOAD_TOOL_NAME = "mcp__files__download_file"
DOWNLOAD_MAX_BYTES = MAX_ATTACH_BYTES              # 다운로드 파일 최대 크기 (25MB)
DOWNLOAD_MAX_REDIRECTS = 5
DOWNLOAD_TIMEOUT = 60                               # 초

# ── 사용자별 기억(프로필) ──
# 화자 구분 + 서버(길드)별로 그 사람에 대해 알게 된 사실을 기억. 에이전트가 remember_user 로 기록.
MEMORY_TOOL_NAMES = ("mcp__memory__remember_user", "mcp__memory__forget_user")
MEMORY_MAX_FACTS = 20              # 한 사용자당 기억 항목 수 상한 (넘으면 오래된 것부터 삭제)
MEMORY_MAX_FACT_CHARS = 200        # 항목 1개 길이 상한
MEMORY_MAX_BLOCK_CHARS = 1200      # 프롬프트에 주입할 기억 블록 총 길이 상한 (매 요청 토큰 비용)
MEMORY_MAX_NAME_CHARS = 60         # 표시 이름 길이 상한

# 서버 기억(분위기·주제·말투 규범) — 그 서버 사람 모두에게 공유되는 메모
SERVER_TOOL_NAMES = ("mcp__memory__remember_server", "mcp__memory__forget_server")
SERVER_MAX_FACTS = 16              # 서버당 메모 개수 상한 (여러 채널에서 모이므로 채널 때보다 여유)
SERVER_MAX_BLOCK_CHARS = 900       # 프롬프트에 주입할 서버 메모 블록 길이 상한

# 과거 대화 학습 (`/기억 학습` — 관리자 전용, 채널 기록을 읽어 사용자별 특징을 한 번에 정리)
LEARN_DEFAULT_MESSAGES = 500       # 스캔할 최근 메시지 수 기본값 (명령 인자 `개수` 로 지정)
LEARN_MIN_MESSAGES = 50            # 인자 최소
LEARN_MAX_MESSAGES = 5000          # 인자 최대 (그 이상은 시간·토큰 과다)
LEARN_MIN_USER_MESSAGES = 5        # 이 미만으로 말한 사람은 건너뜀 (표본 부족)
LEARN_MAX_USERS = 25               # `인원` 인자 기본값 — 처리할 최대 인원 (발화 많은 순)
LEARN_USERS_LIMIT = 200            # `인원` 인자 최대. 1명당 추출 호출 1회 = 시간·토큰이 선형으로 는다
LEARN_MAX_USER_CHARS = 4000        # 사용자 1인 전사 길이 상한 (최근 메시지 우선)
LEARN_MSG_MAX_CHARS = 300          # 메시지 1건을 자를 길이
LEARN_MAX_FACTS_PER_USER = 5       # 1회 학습에서 사람당 뽑을 최대 항목
LEARN_TIMEOUT = 120                # 사용자 1명 추출 제한(초)
LEARN_SERVER_CHARS = 6000          # 서버 분위기 추출에 쓸 전사 길이 상한 (여러 사람 섞인 대화)

# 대화 초기화 키워드 (멘션 뒤에 이 단어만 있으면 해당 채널 맥락 리셋)
RESET_KEYWORDS = {"reset", "/reset", "새대화", "새 대화", "초기화", "clear", "리셋"}

# 사용량 조회 키워드 (멘션 뒤에 이 단어만 있으면 사용량 표시 — 슬래시 명령 없이도 동작)
USAGE_KEYWORDS = {"usage", "/usage", "사용량", "quota", "쿼터", "한도"}

# ── 게임 서버 온라인/오프라인 감시 ──
GAME_DEFAULT_POLL_SEC = 60          # 감시 주기(초). env GAME_POLL_SEC 로 변경 (최소 GAME_MIN_POLL_SEC)
GAME_MIN_POLL_SEC = 10
GAME_DEFAULT_FAIL_THRESHOLD = 2     # 상태 전환 확정에 필요한 연속 관측 횟수(플래핑 방지). env GAME_FAIL_THRESHOLD
GAME_PROBE_TIMEOUT = 5              # 서버 1회 프로브 제한(초)
GAME_MAX_WATCHES = 50              # 감시 목록 상한 (남용 방지)
MC_DEFAULT_PORT = 25565            # 포트 생략 시 기본값 (마인크래프트)

# ── 로깅 ──────────────────────────────────────────────────────────────────
# Windows 콘솔(cp949)에서 한글 로그가 깨지지 않도록 UTF-8 로 강제
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(name)s: %(message)s",
    datefmt="%H:%M:%S",
    stream=sys.stdout,   # stderr 대신 stdout — PowerShell 5.1이 로그를 에러로 오인하지 않도록
)
log = logging.getLogger("claude-discord")


def _int_env(key: str, default: int, minimum: int = 0) -> int:
    """정수 환경변수 읽기 (잘못된 값/최소값 미만이면 기본값)."""
    raw = os.environ.get(key, "").strip()
    if not raw:
        return default
    try:
        val = int(raw)
    except ValueError:
        log.warning("%s 값이 잘못됨(%r) — 기본 %d 사용", key, raw, default)
        return default
    if val < minimum:
        log.warning("%s=%d 은(는) 최소 %d 미만 — %d 사용", key, val, minimum, minimum)
        return minimum
    return val
