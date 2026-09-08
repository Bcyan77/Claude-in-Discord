#!/usr/bin/env bash
# 봇을 실행한다. (Linux / macOS)  항상 격리 가상환경(.venv)의 파이썬을 사용.
#   사용:  bash scripts/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"

if [ ! -x "$PY" ]; then
    echo "가상환경이 없습니다. 먼저  bash scripts/setup.sh  를 실행하세요." >&2
    exit 1
fi
if [ ! -f "$ROOT/.env" ]; then
    echo "경고: .env 파일이 없습니다. .env.example 을 복사해 토큰을 채워주세요." >&2
fi

cd "$ROOT"
exec "$PY" bot.py
