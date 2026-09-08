#!/usr/bin/env bash
# 실행 중인 봇(bot.py) 프로세스를 모두 종료한다. (Linux / macOS)
#   사용:  bash scripts/stop.sh
set -euo pipefail

pids="$(pgrep -f 'python.*bot\.py' || true)"
if [ -z "$pids" ]; then
    echo "실행 중인 봇이 없습니다."
    exit 0
fi

echo "종료할 PID: $pids"
echo "$pids" | xargs -r kill
echo "봇 프로세스 종료 완료."
