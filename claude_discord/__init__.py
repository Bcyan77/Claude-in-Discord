"""Claude 대화형 Discord 봇 패키지.

모듈 구성 (의존 방향: 위 → 아래):
  config.py         상수·경로·로깅 (최하위, 앱 의존 없음)
  persona.py        페르소나 + 보안 규칙(코드 고정)
  settings.py       .env 로드 → 실행 설정
  stores.py         세션/사용량 영속 저장소
  profiles.py       사용자별·서버별 기억(길드 단위) + memory MCP 도구
  workspace.py      요청별 파일 입출력·캐시·응답 분할
  security.py       경로 샌드박스 훅 + 안전한 URL 다운로드(SSRF/DNS리바인딩 방어)
  claude_client.py  Claude Agent SDK 호출(도구+세션 resume)
  gameserver.py     게임 서버 온라인/오프라인 감시
  app.py            ClaudeBot(게이트웨이) + main(진입점)

실행은 루트의 bot.py (`python bot.py`) 또는 `from claude_discord import main`.
"""

from .app import main

__all__ = ["main"]
