#!/usr/bin/env bash
# 매핑되지 않은(고아) Claude 세션 트랜스크립트(.jsonl) 정리. (Linux / macOS)
#   bash scripts/clean-sessions.sh              # 실제 삭제
#   bash scripts/clean-sessions.sh --dry-run    # 미리보기(권장: 먼저 실행)
#   MIN_AGE_MIN=0 bash scripts/clean-sessions.sh # 최근 파일 보호 해제
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
MIN_AGE_MIN="${MIN_AGE_MIN:-60}"

WORK="$ROOT/agent_workdir"
ENC="$(printf '%s' "$WORK" | sed 's/[^A-Za-z0-9]/-/g')"
PROJDIR="$HOME/.claude/projects/$ENC"

[ -d "$PROJDIR" ] || { echo "세션 폴더가 없습니다 (정리할 것 없음): $PROJDIR"; exit 0; }

SF="$ROOT/sessions.json"
[ -f "$SF" ] || { echo "sessions.json 이 없습니다 — 안전을 위해 중단합니다."; exit 1; }

PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="python3"
KEEP="$("$PY" -c "import json; print('\n'.join(v for v in json.load(open('$SF',encoding='utf-8')).values() if v))" 2>/dev/null)" \
    || { echo "sessions.json 파싱 실패 — 안전을 위해 중단합니다."; exit 1; }

now=$(date +%s); cutoff=$(( now - MIN_AGE_MIN * 60 ))
kept=0; recent=0; deleted=0; freed=0
shopt -s nullglob
for f in "$PROJDIR"/*.jsonl; do
    uuid="$(basename "$f" .jsonl)"
    if printf '%s\n' "$KEEP" | grep -qxF "$uuid"; then kept=$((kept+1)); continue; fi
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$mtime" -gt "$cutoff" ]; then recent=$((recent+1)); continue; fi   # 최근 파일 보호
    sz=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
    freed=$((freed + sz))
    if [ "$DRY" -eq 1 ]; then echo "[미리보기] 삭제 대상: $(basename "$f") ($sz bytes)"
    else rm -f "$f" && echo "삭제: $(basename "$f")"; fi
    deleted=$((deleted+1))
done

mb="$(awk "BEGIN{printf \"%.2f\", $freed/1048576}")"
if [ "$DRY" -eq 1 ]; then verb="삭제 예정"; else verb="삭제됨"; fi
echo
echo "정리 완료: 유지 ${kept}개 · 최근보호 ${recent}개 · ${verb} ${deleted}개 (${mb} MB)"
[ "$DRY" -eq 1 ] && echo "실제 삭제하려면 --dry-run 없이 다시 실행하세요."
