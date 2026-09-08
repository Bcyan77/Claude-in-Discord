#!/usr/bin/env bash
# 격리 가상환경(.venv) 생성 + 의존성 설치. (Linux / macOS)  최초 1회.
#   사용:  bash scripts/setup.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ ! -d .venv ]; then
    echo "가상환경(.venv) 생성 중..."
    python3 -m venv .venv
fi

echo "pip 업그레이드..."
./.venv/bin/python -m pip install --upgrade pip --quiet

echo "의존성 설치 중 (requirements.txt)..."
./.venv/bin/python -m pip install -r requirements.txt

echo
echo "설치 완료. .env 를 채운 뒤  bash scripts/run.sh  로 실행하세요."
