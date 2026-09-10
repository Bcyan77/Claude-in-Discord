#!/usr/bin/env bash
# 봇 상태 확인 / 진단. (Linux / macOS)
#   사용:  bash scripts/status.sh            (로컬 점검)
#          bash scripts/status.sh --online    (Discord API 로 토큰/공개여부까지)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"
ENVF="$ROOT/.env"
WSDIR="$ROOT/workspace"
ONLINE=0
[ "${1:-}" = "--online" ] && ONLINE=1

row() { # $1=ok|warn|fail  $2=label  $3=detail
    case "$1" in
        ok)   tag="[ OK ]";; warn) tag="[WARN]";; fail) tag="[FAIL]";; *) tag="[ -- ]";;
    esac
    printf '%s  %-20s %s\n' "$tag" "$2" "$3"
}

env_val() { # $1=key
    [ -f "$ENVF" ] || { echo ""; return; }
    sed -n "s/^[[:space:]]*$1[[:space:]]*=//p" "$ENVF" | head -n1 | tr -d '[:space:]'
}

echo "== Claude Discord 봇 상태 =="

# 1) 프로세스
#    부모가 또 다른 bot.py 가 아닌 것(=root)만 세어 논리적 인스턴스 수를 구한다.
#    (Linux venv 는 보통 단일 프로세스지만, 런처+워커 구조에서도 오탐 없이 1개로 계산)
all_pids="$(pgrep -f 'python.*bot\.py' || true)"
roots=""
for pid in $all_pids; do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    is_child=0
    for q in $all_pids; do [ "$q" = "$ppid" ] && { is_child=1; break; }; done
    [ "$is_child" -eq 0 ] && roots="$roots $pid"
done
roots="$(echo $roots | xargs 2>/dev/null || true)"
rcount=$(echo -n "$roots" | wc -w | tr -d ' ')
if   [ "$rcount" -eq 0 ]; then row warn "봇 프로세스" "중지됨 (실행: bash scripts/run.sh)"
elif [ "$rcount" -eq 1 ]; then row ok   "봇 프로세스" "실행 중 (PID $roots)"
else row fail "봇 프로세스" "중복 ${rcount}개 실행! PID: ${roots} — 1개만 남기세요"
fi

# 2) 가상환경 + 파이썬
if [ -x "$PY" ]; then row ok "가상환경(.venv)" "$("$PY" --version 2>&1)"
else row fail "가상환경(.venv)" "없음 (실행: bash scripts/setup.sh)"; fi

# 3) 핵심 패키지
if [ -x "$PY" ]; then
    "$PY" - <<'PYEOF' | while read -r line; do
import importlib.metadata as m
for p in ['discord.py','claude-agent-sdk','python-dotenv']:
    try: print(p, m.version(p))
    except Exception: print(p, 'MISSING')
PYEOF
        case "$line" in *MISSING*) row fail "패키지" "$line";; *) row ok "패키지" "$line";; esac
    done
fi

# 4) .env / 시크릿
if [ -f "$ENVF" ]; then
    dt="$(env_val DISCORD_TOKEN)"; ct="$(env_val CLAUDE_CODE_OAUTH_TOKEN)"; cm="$(env_val CLAUDE_MODEL)"; ai="$(env_val DISCORD_APPLICATION_ID)"
    [ -n "$dt" ] && row ok "DISCORD_TOKEN" "설정됨 (길이 ${#dt})" || row fail "DISCORD_TOKEN" "비어있음"
    [ -n "$ct" ] && row ok "OAUTH_TOKEN" "설정됨 (길이 ${#ct})" || row warn "OAUTH_TOKEN" "비어있음 (서버 배포 시 필요)"
    [ -n "$cm" ] && row ok "CLAUDE_MODEL" "$cm" || row ok "CLAUDE_MODEL" "기본값 sonnet"
    if [ -z "$ai" ]; then row ok "앱 ID" "봇 계정 ID 자동 사용 (DISCORD_APPLICATION_ID 미설정)"
    elif printf '%s' "$ai" | grep -qE '^[0-9]+$'; then row ok "앱 ID" "$ai (초대 링크용)"
    else row warn "앱 ID" "DISCORD_APPLICATION_ID 가 숫자가 아님 — 봇 계정 ID 로 대체됨"; fi
else
    row fail ".env" "없음 (.env.example 복사)"
fi

# 4b) 시스템 프롬프트 소스
sp="$(env_val SYSTEM_PROMPT)"; spf="$(env_val SYSTEM_PROMPT_FILE)"
if [ -n "$sp" ]; then row ok "시스템 프롬프트" "env SYSTEM_PROMPT (인라인)"
elif [ -n "$spf" ] && [ -f "$spf" ]; then row ok "시스템 프롬프트" "file: $spf"
elif [ -n "$spf" ]; then row warn "시스템 프롬프트" "지정 파일 없음: $spf (기본값 사용)"
elif [ -f "$ROOT/system_prompt.md" ]; then row ok "시스템 프롬프트" "file: system_prompt.md"
else row ok "시스템 프롬프트" "기본값 (내장 페르소나)"; fi

# 5) ANTHROPIC_API_KEY
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then row warn "ANTHROPIC_API_KEY" "설정됨! 종량제 위험 (봇은 시작 시 무시)"
else row ok "ANTHROPIC_API_KEY" "없음 (구독 인증만 — 정상)"; fi

# 6) claude CLI
if command -v claude >/dev/null 2>&1; then row ok "claude CLI" "$(claude --version 2>&1)"
else row warn "claude CLI" "미발견 (SDK 번들 CLI 로도 동작)"; fi

# 7) 세션 상태
SF="$ROOT/sessions.json"
if [ -f "$SF" ] && [ -x "$PY" ]; then
    n="$("$PY" -c "import json; print(len(json.load(open('$SF',encoding='utf-8'))))" 2>/dev/null)"
    row ok "sessions.json" "채널 ${n:-?}개 맥락 저장됨"
else
    row ok "sessions.json" "없음 (첫 대화 시 생성)"
fi

# 8) workspace 파일 캐시
capmb="$(env_val WORKSPACE_CACHE_MB)"
case "$capmb" in ''|*[!0-9]*) capmb=1024;; esac
if [ "$capmb" -eq 0 ]; then captext="무제한"; else captext="${capmb} MB"; fi
if [ -d "$WSDIR" ]; then
    kb="$(du -sk "$WSDIR" 2>/dev/null | awk '{print $1}')"
    mb="$(awk "BEGIN{printf \"%.1f\", ${kb:-0}/1024}")"
    nfiles="$(find "$WSDIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
    ndirs="$(find "$WSDIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    detail="${mb} MB / 상한 ${captext} (요청폴더 ${ndirs}개, 파일 ${nfiles}개)"
    over="$(awk "BEGIN{print ($capmb>0 && $mb>$capmb)?1:0}")"
    if [ "$over" -eq 1 ]; then row warn "workspace 캐시" "$detail"; else row ok "workspace 캐시" "$detail"; fi
else
    row ok "workspace 캐시" "없음 (상한 ${captext}, 첫 파일 요청 시 생성)"
fi

# 8b) 파일 다운로드 도구
row ok "파일 다운로드" "허용 (<=25MB, http/https, SSRF·DNS리바인딩 차단)"

# 8b-2) 답변 전송 형식 + 분량 규칙 (긴 답변 가독성)
row ok "답변 전송" "2000자 이하 평문 / 4096자 이하 임베드 1개 / 초과 시 발췌 + 답변.md 첨부"
lph="$(env_val LINK_PREVIEW_HOSTS)"
if [ -z "$lph" ]; then row ok "링크 미리보기" "유튜브만 허용 (기본) - 그 외 링크는 카드 안 붙음"
elif [ "$lph" = "*" ]; then row warn "링크 미리보기" "전부 허용 (*) - 링크마다 카드가 붙음"
elif [ "$lph" = "none" ]; then row ok "링크 미리보기" "전부 차단 (none)"
else row ok "링크 미리보기" "허용 호스트: $lph"; fi
persona_txt="FORMAT"   # 내장 기본 페르소나에는 분량 규칙이 들어있음
if [ -n "$sp" ]; then persona_txt="$sp"
elif [ -n "$spf" ] && [ -f "$spf" ]; then persona_txt="$(cat "$spf")"
elif [ -f "$ROOT/system_prompt.md" ]; then persona_txt="$(cat "$ROOT/system_prompt.md")"
fi
if printf '%s' "$persona_txt" | grep -qE '답변 형식|FORMAT'; then
    row ok "답변 분량 규칙" "페르소나에 있음"
else
    row warn "답변 분량 규칙" "페르소나에 없음 - 답변이 길어짐 (system_prompt.example.md 참고)"
fi

# 8c) 누적 사용량
UF="$ROOT/usage.json"
if [ -f "$UF" ] && [ -x "$PY" ]; then
    uline="$("$PY" -c "import json; d=json.load(open('$UF',encoding='utf-8')); c=round(float((d.get('total') or {}).get('cost_usd',0)),2); print(f\"요청 {d.get('requests',0)}회, 예상 \${c}\")" 2>/dev/null)"
    row ok "누적 사용량" "${uline:-집계 시작됨}"
else
    row ok "누적 사용량" "없음 (첫 요청 시 생성)"
fi

# 8d) 고아 세션 (매핑 안 된 .jsonl)
ENC="$(printf '%s' "$ROOT/agent_workdir" | sed 's/[^A-Za-z0-9]/-/g')"
PROJDIR="$HOME/.claude/projects/$ENC"
if [ -d "$PROJDIR" ]; then
    keep="$("$PY" -c "import json; print('\n'.join(v for v in json.load(open('$ROOT/sessions.json',encoding='utf-8')).values() if v))" 2>/dev/null || true)"
    orphans=0
    for f in "$PROJDIR"/*.jsonl; do
        [ -e "$f" ] || continue
        u="$(basename "$f" .jsonl)"
        printf '%s\n' "$keep" | grep -qxF "$u" || orphans=$((orphans+1))
    done
    if [ "$orphans" -gt 0 ]; then row warn "고아 세션" "${orphans}개 (정리: scripts/clean-sessions.sh)"
    else row ok "고아 세션" "없음"; fi
else
    row ok "고아 세션" "세션 폴더 없음"
fi

# 8e) 게임 서버 감시 (온라인/오프라인 알림)
WF="$ROOT/watches.json"
if [ -f "$WF" ] && [ -x "$PY" ]; then
    gline="$("$PY" -c "import json; d=json.load(open('$WF',encoding='utf-8')); v=list(d.values()); on=sum(1 for w in v if w.get('state')=='online'); off=sum(1 for w in v if w.get('state')=='offline'); print(f'{len(v)}개 감시 (온라인 {on} · 오프라인 {off})' if v else '등록된 서버 없음 (/서버 추가 로 등록)')" 2>/dev/null)"
    row ok "게임 서버 감시" "${gline:-watches.json 파싱 실패}"
else
    row ok "게임 서버 감시" "없음 (/서버 추가 로 등록)"
fi

# 8e-2) 사용자 기억(프로필) — 사용자별 특징을 서버(길드) 단위로 기억
PF="$ROOT/profiles.json"
if [ -f "$PF" ] && [ -x "$PY" ]; then
    pline="$("$PY" -c "import json; d=json.load(open('$PF',encoding='utf-8')); v=[e for e in d.values() if e.get('facts')]; n=sum(len(e.get('facts') or []) for e in v); g=len(set(k.split(':')[0] for k in d)); print(f'사용자 {len(v)}명 · {n}건 (서버 {g}개, 상한 20건/인)' if v else '기록 없음 (확인/삭제: /기억)')" 2>/dev/null)"
    row ok "사용자 기억" "${pline:-profiles.json 파싱 실패}"
else
    row ok "사용자 기억" "없음 (대화 중 자동 생성 · 확인/삭제: /기억)"
fi

# 8e-2b) 서버 기억 (서버 분위기 메모 — 그 서버 사람 모두에게 공유)
GF="$ROOT/guilds.json"
if [ -f "$GF" ] && [ -x "$PY" ]; then
    gline2="$("$PY" -c "import json; d=json.load(open('$GF',encoding='utf-8')); v=[e for e in d.values() if e.get('facts')]; n=sum(len(e.get('facts') or []) for e in v); print(f'서버 {len(v)}개 · {n}건 (상한 16건/서버)' if v else '기록 없음 (확인: /기억 서버)')" 2>/dev/null)"
    row ok "서버 기억" "${gline2:-guilds.json 파싱 실패}"
    tline="$("$PY" -c "import json; d=json.load(open('$GF',encoding='utf-8')); t=[(e.get('options') or {}).get('tone') for e in d.values()]; t=[x for x in t if x]; r=t.count('raw'); o=t.count('off'); print(f'{len(t)}개 서버가 직접 설정 — 그대로 {r}개 · 끔 {o}개' if t else '기본값 보통 (어조만 · 공격적 표현 제외)')" 2>/dev/null)"
    row ok "말투 반영" "${tline:-guilds.json 파싱 실패}"
else
    row ok "서버 기억" "없음 (대화 중 자동 생성 · 확인: /기억 서버)"
fi

# 8e-3) `/기억 학습` 허용 계정 (관리 권한 없이도 실행 가능한 계정)
lu="$(env_val MEMORY_LEARN_USERS)"
if [ -n "$lu" ]; then row ok "학습 허용 계정" "$lu  (+ 서버 관리 권한자)"
else row ok "학습 허용 계정" "'서버 관리' 권한자만 (MEMORY_LEARN_USERS 미설정)"; fi

# 8f) 자동 시작 (Linux 는 systemd — Windows 의 작업 스케줄러에 해당)
if command -v systemctl >/dev/null 2>&1; then
    autost="$(systemctl is-enabled claude-discord 2>/dev/null || true)"
    if   [ "$autost" = "enabled" ]; then row ok   "자동 시작" "systemd claude-discord (enabled)"
    elif [ -n "$autost" ];          then row warn "자동 시작" "systemd claude-discord ($autost)"
    else row ok "자동 시작" "미등록 (README 의 systemd 예시 참고)"; fi
else
    row ok "자동 시작" "systemd 없음 (해당 없음)"
fi

# 9) (옵션) Discord API
if [ "$ONLINE" -eq 1 ]; then
    echo "-- Discord API 점검 --"
    token="$(env_val DISCORD_TOKEN)"
    if [ -z "$token" ]; then
        row fail "Discord API" "DISCORD_TOKEN 없음"
    else
        json="$(curl -s -H "Authorization: Bot $token" https://discord.com/api/v10/applications/@me || true)"
        id="$(echo "$json"   | sed -n 's/.*"id":[[:space:]]*"\([0-9]*\)".*/\1/p' | head -n1)"
        name="$(echo "$json" | sed -n 's/.*"name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        if [ -n "$id" ]; then
            row ok "토큰 유효" "$name (id=$id)"
            if echo "$json" | grep -q '"bot_public":[[:space:]]*true'; then
                row warn "Public Bot" "true — 아무나 초대 가능 (개인용이면 false 권장)"
            else
                row ok "Public Bot" "false — 소유자만 초대 가능"
            fi
        else
            row fail "Discord API" "응답 이상: $json"
        fi
    fi
fi
