# scripts — 봇 실행 스크립트

봇 설치·실행·종료용 헬퍼 모음. 모두 **격리 가상환경(`.venv`)** 의 파이썬을 사용합니다.
어느 위치에서 실행하든 스크립트가 프로젝트 루트를 자동으로 찾습니다.

| 목적 | Windows (PowerShell) | Linux / macOS |
|------|----------------------|----------------|
| 최초 설치 (venv + 의존성) | `.\scripts\setup.ps1` | `bash scripts/setup.sh` |
| 실행 | `.\scripts\run.ps1` | `bash scripts/run.sh` |
| 종료 (도는 봇 전부) | `.\scripts\stop.ps1` | `bash scripts/stop.sh` |
| 재시작 (종료 후 실행) | `.\scripts\restart.ps1` | — |
| **상태 확인 / 진단** | `.\scripts\status.ps1` | `bash scripts/status.sh` |
| 고아 세션 정리 (매핑 안 된 .jsonl) | `.\scripts\clean-sessions.ps1` | `bash scripts/clean-sessions.sh` |
| **자동 시작 등록** (로그온 시 백그라운드) | `.\scripts\autostart-install.ps1` | systemd (루트 README 참고) |
| 자동 시작 해제 | `.\scripts\autostart-uninstall.ps1` | `systemctl disable claude-discord` |

### 상태 확인 (`status`)

프로세스·가상환경·패키지·`.env`·인증·세션 상태를 한눈에 점검합니다.
`-Online`(PS) / `--online`(sh) 을 붙이면 Discord API 로 **토큰 유효성과 Public Bot 여부**까지 확인합니다.

```powershell
.\scripts\status.ps1            # 로컬 점검
.\scripts\status.ps1 -Online    # Discord API 포함
```
```bash
bash scripts/status.sh --online
```

예시 출력:
```
[ OK ]  봇 프로세스               실행 중 (PID 12345)
[ OK ]  패키지                  discord.py 2.7.1
[FAIL]  봇 프로세스               중복 2개 실행!  ← stop 으로 정리 필요
[WARN]  ANTHROPIC_API_KEY    환경에 설정됨! 종량제 위험
```

## 처음 시작

```powershell
# Windows
.\scripts\setup.ps1        # 1) venv 생성 + 의존성 설치
#  .env 에 DISCORD_TOKEN / CLAUDE_CODE_OAUTH_TOKEN 입력
.\scripts\run.ps1          # 2) 실행
```

```bash
# Linux / macOS (VPS)
bash scripts/setup.sh
#  .env 채우기
bash scripts/run.sh
```

### 고아 세션 정리 (`clean-sessions`)

`sessions.json` 에 매핑되지 않은 Claude 세션 트랜스크립트(`~/.claude/projects/...agent-workdir/*.jsonl`)를 삭제합니다.
테스트·리셋으로 남은 것들을 정리합니다.

```powershell
.\scripts\clean-sessions.ps1 -DryRun     # 먼저 미리보기 (삭제 안 함)
.\scripts\clean-sessions.ps1             # 실제 삭제
```
```bash
bash scripts/clean-sessions.sh --dry-run
bash scripts/clean-sessions.sh
```

안전장치: `sessions.json` 없거나 파싱 실패 시 중단 · 매핑된 세션 보호 · **최근 60분 내 수정 파일 보호**
(처리 중 세션 보호, `-MinAgeMinutes 0` / `MIN_AGE_MIN=0` 으로 해제) · 지정 폴더 하나로만 범위 제한.

### 자동 시작 (`autostart-install`) — Windows

로그온하면 봇이 **창 없이 백그라운드로** 뜨도록 **작업 스케줄러**에 등록합니다. (작업 이름 `ClaudeDiscordBot`)

```powershell
.\scripts\autostart-install.ps1     # 등록 (로그온 시 자동 실행)
.\scripts\autostart-uninstall.ps1   # 해제
Start-ScheduledTask -TaskName ClaudeDiscordBot   # 재부팅 없이 지금 켜기
```

- **왜 '로그온 시 / 내 계정'인가**: `CLAUDE_CODE_OAUTH_TOKEN` 이 비어 있으면 봇은 **내 프로필의 `claude` 로그인**으로 인증합니다.
  SYSTEM·서비스·다른 계정으로 돌리면 그 인증을 못 찾아 실패합니다.
  로그인 없이(부팅 시) 돌리려면 먼저 `claude setup-token` 으로 토큰을 발급해 `.env` 에 넣으세요.
- **중복 방지**: 런처(`autostart-run.ps1`)가 이미 도는 봇이 있으면 실행하지 않습니다. (멘션 1번에 중복 응답 방지)
- 로그는 `bot.out.log` / `bot.err.log` 에 남습니다 (시작할 때마다 새로 씀).
- `stop.ps1` 로 종료해도 **다음 로그온 때 다시 자동 실행**됩니다. 완전히 끄려면 `autostart-uninstall.ps1`.
- 등록 여부는 `status.ps1` 의 **`자동 시작`** 행에서 확인됩니다.

## 참고

- **코드를 바꿨으면** `restart.ps1`(또는 `stop` 후 `run`)로 재시작해야 반영됩니다.
  discord.py 인텐트는 연결 시점에 고정되어 핫리로드가 안 됩니다.
- **같은 토큰으로 봇을 2개 이상 띄우지 마세요.** 멘션 1번에 중복 응답이 발생합니다.
  헷갈리면 `stop` 으로 전부 정리한 뒤 `run` 으로 1개만 띄우세요.
- 백그라운드 상시 실행은 루트 `README.md` 의 systemd 예시를 참고하세요.
- Linux 에서 `chmod +x scripts/*.sh` 후 `./scripts/run.sh` 로도 실행 가능합니다.
