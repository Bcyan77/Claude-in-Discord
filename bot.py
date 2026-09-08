"""Claude 대화형 Discord 봇 — 실행 진입점.

실제 구현은 claude_discord/ 패키지에 있습니다. 이 파일은 얇은 진입점입니다.
  실행:  python bot.py   (또는 scripts/run.ps1 · scripts/run.sh)
  구조:  claude_discord/__init__.py 상단 주석 참고.
"""

from claude_discord import main

if __name__ == "__main__":
    main()
