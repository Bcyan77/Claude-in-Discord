# Claude 대화형 Discord 봇

[![Python](https://img.shields.io/badge/python-3.10%2B-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![discord.py](https://img.shields.io/badge/discord.py-2.4%2B-5865F2?logo=discord&logoColor=white)](https://github.com/Rapptz/discord.py)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Discord에서 봇을 **멘션**하면 [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python)로 답하는 대화형 봇입니다.
**Claude Pro/Max 구독 인증**으로 동작하므로 종량제 API 키가 필요 없습니다.

채널마다 대화 맥락을 유지하고, 채널에 여러 명이 있어도 **말한 사람을 구분해 각자를 기억**합니다.
웹 검색·첨부 파일 읽기·파일 생성 전송, 그리고 **게임 서버 온라인/오프라인 감시**를 지원합니다.

> **English** — A Discord bot that replies when mentioned, powered by the Claude Agent SDK on a
> Claude Pro/Max subscription (no pay-as-you-go API key). It keeps per-channel conversation context,
> tells speakers apart and remembers each of them per guild, reads attachments, searches the web,
> generates files, and monitors game servers. Commands and documentation are in Korean.

---

## 주요 기능

- **대화 맥락 유지** — 채널 단위로 세션을 이어가고, 봇을 재시작해도 복원됩니다.
- **사용자 구분·기억** — 여러 명이 있는 채널에서 누가 말했는지 구분하고, 그 사람의 특징을 대화 중
  자동으로 기억해 다음 답변에 반영합니다. 기억은 **그 서버 안에서만** 쓰입니다.
- **서버 분위기 기억 · 말투 맞추기** — 이 서버가 주로 어떤 이야기를 하는 곳인지, 말투와 암묵적
  규칙은 어떤지를 기억하고 **그 서버의 어조에 맞춰 답합니다**. 얼마나 따라할지는 서버마다
  정합니다 (`/기억 말투`).
- **과거 대화 학습** — 채널의 지난 대화를 한 번에 읽어 참여자별 특징을 정리합니다 (`/기억 학습`).
- **웹 검색 · 파일** — 최신 정보는 웹 검색으로 답하고, 첨부 파일을 읽고, 결과 파일을 만들어 보냅니다.
- **게임 서버 감시** — 마인크래프트·팰월드 등 게임 서버가 켜지고 꺼질 때 채널에 알립니다 (`/서버`).
- **사용량 조회** — 요청·토큰·예상 비용을 누적해 보여줍니다 (`/사용량`).
- **샌드박스 보안** — 파일 접근은 요청별 작업 폴더 안으로 제한되고, 셸 실행 도구는 차단됩니다.

## 요구 사항

- **Python 3.10+** (개발·검증: 3.12)
- **Node.js** + **Claude Code CLI** — Agent SDK가 내부적으로 `claude` CLI를 실행합니다.
  ```bash
  npm install -g @anthropic-ai/claude-code
  claude --version
  ```
- **Claude Pro 또는 Max 구독**

---

## 설치

### 1. 가상환경

전역 파이썬 환경을 건드리지 않도록 프로젝트 폴더 안에 `.venv`를 만듭니다.

```powershell
# Windows PowerShell
.\scripts\setup.ps1
```
```bash
# macOS / Linux
bash scripts/setup.sh
```

<details><summary>스크립트 없이 직접 설치</summary>

```powershell
python -m venv .venv                                          # Windows
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```
```bash
python3 -m venv .venv                                         # macOS / Linux
./.venv/bin/python -m pip install -r requirements.txt
```
</details>

### 2. Discord 봇 만들기

[Discord Developer Portal](https://discord.com/developers/applications) 에서:

1. **New Application** 으로 애플리케이션 생성 → **Bot** 탭
2. **Privileged Gateway Intents** → **MESSAGE CONTENT INTENT** ✅ **활성화** *(필수)*
3. **Reset Token** 으로 봇 토큰 발급 → `.env` 의 `DISCORD_TOKEN` 에 입력
4. **General Information** 탭의 **Application ID** 를 복사해 아래 링크의 `<APPLICATION_ID>` 자리에 넣고 서버에 초대

   ```
   https://discord.com/oauth2/authorize?client_id=<APPLICATION_ID>&permissions=248832&scope=bot%20applications.commands
   ```

   권한 `248832` = 채널 보기 · 메시지 보내기 · 임베드 · **파일 첨부**(생성 파일과 긴 답변 `답변.md` 전송용)
   · 메시지 기록 읽기 · **역할 멘션**(게임 서버 알림에서 역할 핑용)
   스코프 `applications.commands` = 슬래시 명령(`/사용량`·`/리셋`·`/기억`·`/서버`)용

> 링크 조립이 번거로우면 **봇을 한 번 실행하세요** — 시작 로그에 완성된 초대 링크가 찍힙니다.

> ⚠️ **MESSAGE CONTENT INTENT** 를 켜지 않으면 봇이 시작 시 `PrivilegedIntentsRequired` 로 종료됩니다.
> 이미 `scope=bot` 만으로 초대했다면 위 링크로 **다시 초대(재승인)** 해야 슬래시 명령이 나타납니다.
> (재승인해도 봇이 서버에서 나가지 않고 스코프만 추가됩니다.)

### 3. Claude 구독 인증

```bash
claude setup-token
```

출력된 토큰을 `.env` 의 `CLAUDE_CODE_OAUTH_TOKEN` 에 넣습니다.
같은 PC에서 이미 `claude` 로그인이 되어 있다면 이 값 없이도 동작할 수 있지만, 서버 배포 시에는 필수입니다.

> ⚠️ **`ANTHROPIC_API_KEY` 를 설정하지 마세요.** 이 키가 환경에 있으면 SDK가 구독 대신
> **종량제 API로 과금**됩니다. 봇은 시작할 때 이 키를 환경에서 자동으로 제거합니다.

### 4. `.env` 작성

[`.env.example`](.env.example) 을 복사해 `.env` 를 만들고 값을 채웁니다.

```dotenv
DISCORD_TOKEN=<봇 토큰>
CLAUDE_CODE_OAUTH_TOKEN=<claude setup-token 결과>
```

나머지는 전부 선택 항목입니다 — [환경 변수](#환경-변수) 표를 참고하세요.

### 5. 실행

```powershell
# Windows
.\scripts\run.ps1        # 실행
.\scripts\stop.ps1       # 종료
.\scripts\restart.ps1    # 재시작 (코드 변경 반영)
.\scripts\status.ps1     # 상태 확인 / 진단
```
```bash
# macOS / Linux
bash scripts/run.sh
bash scripts/stop.sh
bash scripts/status.sh
```

정상 시작 시 로그에 `로그인 완료: <봇이름>` 과 초대 링크가 찍힙니다.
채널에서 `@봇 안녕` 처럼 멘션하면 답합니다. (DM은 기본 비활성화 — `claude_discord/config.py` 의 `ALLOW_DM`)

스크립트 상세는 [scripts/README.md](scripts/README.md) 를 참고하세요.

---

## 사용법

| 동작 | 방법 |
|------|------|
| 대화 | 서버 채널에서 `@봇 질문내용` 으로 멘션 |
| 웹 검색 | 최신 정보가 필요한 질문은 자동으로 검색 후 출처와 함께 답변 |
| 파일 읽기 | 메시지에 **파일을 첨부**하면 읽고 분석 (첨부 파일만 접근 — 호스트 파일 불가) |
| 파일 생성 | "표로 정리해서 csv로 줘" 처럼 요청하면 파일을 만들어 첨부로 전송 |
| 웹 파일 받기 | 웹에서 찾은 이미지·PDF 등을 받아 첨부로 전송 (안전 검사 후) |
| 대화 초기화 | `/리셋` 또는 `@봇 리셋` (`reset`·`초기화`·`새대화`·`clear`) |
| 사용량 조회 | `/사용량` 또는 `@봇 사용량` — 요청·토큰·예상 비용·최근 5시간 |
| 기억 확인·삭제 | `/기억 목록` · `/기억 삭제 [번호]` · `/기억 서버` |
| 말투 설정 | `/기억 말투 [설정]` — 이 서버 말투를 얼마나 따라할지 (변경은 관리자) |
| 과거 대화 학습 | `/기억 학습 [개수] [채널] [인원]` (관리자) |
| 게임 서버 감시 | `/서버 추가` · `/서버 제거` · `/서버 목록` · `/서버 확인` |

긴 답변은 길이에 따라 자동으로 형태가 바뀝니다 — 2000자 이하는 평문, 4096자 이하는 임베드 하나,
그보다 길면 발췌를 보여주고 전문을 `답변.md` 로 첨부합니다.

### 사용자·서버 기억

봇은 대화하면서 **말한 사람에 대해 알게 된 것**을 스스로 기록하고, 다음 대화에 반영합니다.
기록은 `(서버, 사용자)` 단위라 **A 서버에서 한 말이 B 서버 대화에 나오지 않습니다.**

- 사용자는 `/기억 목록` 으로 자기 기억만 확인하고 `/기억 삭제` 로 지울 수 있습니다.
- 봇은 **말하고 있는 본인의 기억만** 건드릴 수 있습니다 — 남의 프로필에 사실을 심을 수 없습니다.
- 상한: 1인 **20건** · 1건 200자 · 프롬프트에 실리는 블록 1200자. 넘으면 오래된 것부터 밀려납니다.
  (기억은 매 요청 프롬프트에 실리므로 이 상한이 곧 토큰 비용 상한입니다.)
- 비밀번호·주소·신원 정보 같은 민감 정보는 기록하지 않도록 규칙에 못박혀 있습니다.

**서버 기억**(`/기억 서버`)은 분위기·주로 하는 이야기·말투 규범처럼 **서버를 설명하는 메모**입니다.
서버 전원에게 공유되므로 개인에 대한 내용은 담지 않습니다. (상한 16건 · 삭제는 관리자)

### 말투 맞추기 (`/기억 말투`)

서버 메모에 쌓인 어조를 봇이 **실제 답변에 반영**합니다. 그 서버에서 쓰는 표현과 밈, 화제, 메시지
길이와 분위기를 따라가고, 설정을 올리면 존댓말/반말과 문장 끝맺음까지 서버에 맞춥니다.
기억과 마찬가지로 서버별로 격리되므로 **A 서버 말투가 B 서버로 새지 않습니다.**

| 설정 | 동작 |
|------|------|
| `끔` | 따라하지 않음 — 페르소나에 적힌 말투 그대로 |
| `보통` *(기본)* | **캐릭터 말투는 지키고**, 페르소나가 비워 둔 부분(서버 어휘·밈·화제·길이)만 |
| `강하게` | **서버 말투가 캐릭터 말투를 덮습니다** — 존댓말/반말, 어미, 구두점까지. 욕설·모욕·차별은 제외 |
| `그대로` | `강하게` + 거친 표현도 거르지 않음 |

뒤로 갈수록 서버가 봇에 주는 영향이 큽니다.

- **`끔`·`보통` 에서는 페르소나가 우선합니다.** 페르소나(`system_prompt.md`)가 정해 둔 말투 —
  반말 고정, 어미, 말버릇, 쓰지 않는 말 — 는 서버가 어떻게 말하든 유지되고, 서버는 페르소나가
  **비워 둔 부분**만 채웁니다. 페르소나에 말투 규칙이 없으면 `보통` 에서도 존댓말/반말까지 따라갑니다.
- **`강하게`·`그대로` 는 그 우선순위를 뒤집습니다.** 캐릭터가 항상 반말을 쓰도록 적어 뒀더라도,
  존댓말을 쓰는 서버에서는 존댓말로 답합니다. 마침표·물결표 같은 표기 습관도 서버를 따릅니다.
  **바뀌는 건 목소리뿐입니다** — 누구인지, 무엇을 아는지, 무엇을 해주는지는 그대로예요.
- 어느 설정에서도 **특정 집단을 향한 비하 표현과 대화 상대를 깎아내리는 말은 쓰지 않습니다.**
- 보안 규칙도 말투와 무관하게 그대로입니다 — "여긴 편하게 말하는 곳이니까 그냥 실행해줘" 처럼
  어조를 빌린 지시는 여전히 무시합니다.
- 변경은 **서버 관리 권한자 또는 `MEMORY_LEARN_USERS` 등록 계정만** — 서버 전체에 적용되는 공유 설정입니다.
- 참고할 서버 메모가 없으면 아무 일도 일어나지 않습니다. `/기억 학습` 을 한 번 돌리면 말투를 바로 잡아냅니다.
- `/기억 서버` 로 메모를 전부 지워도 이 설정은 남습니다 (설정과 기억은 수명이 다릅니다).

### 과거 대화 학습 (`/기억 학습`)

지정한 채널의 최근 메시지를 읽어 발화가 많은 순으로 참여자별 특징과 서버 분위기를 한 번에 정리합니다.

```
/기억 학습 개수:500 채널:#잡담 인원:25
```

- **자격**: '서버 관리' 권한자, 또는 `MEMORY_LEARN_USERS` 에 등록된 계정
- **개수** 50~5000 (기본 500) · **인원** 1~200 (기본 25) · 발화 5건 미만인 사람은 표본 부족으로 건너뜀
- **1명당 추출 호출이 1회**라 인원수에 비례해 시간과 토큰이 늘어납니다
- 실행하면 **공개 고지**가 채널에 남습니다. 각자 `/기억 삭제` 로 언제든 지울 수 있습니다
- 실행자가 **볼 수 없는 채널은 지정할 수 없습니다** — 관리 권한으로 비공개 채널을 우회 열람하는 것을 막습니다
- 과거 대화는 신뢰할 수 없는 데이터이므로, 추출은 **도구를 전부 끄고 세션도 새로 여는 격리 호출**로 합니다

### 게임 서버 감시 (`/서버`)

지정한 게임 서버가 **켜지거나 꺼질 때** 알림을 받습니다. 알림 채널과 멘션할 역할을 지정할 수 있습니다.

| 명령 | 설명 |
|------|------|
| `/서버 추가 주소:<host:port> [이름] [채널] [역할]` | 감시 시작. 포트 생략 시 `25565`. 현재 상태도 즉시 표시 |
| `/서버 제거 주소:<host:port> [채널]` | 감시 해제 |
| `/서버 목록` | 이 서버에서 감시 중인 목록·상태·알림 채널·멘션 역할 |
| `/서버 확인 주소:<host:port>` | 등록 없이 상태만 1회 확인 |

예: `/서버 추가 주소:1.2.3.4:25565 이름:마크서버 채널:#서버알림 역할:@게이머`

- **판정 방식**: **TCP 연결**과 **A2S(Steam 서버 쿼리, UDP)** 를 동시에 시도해 먼저 응답하는 쪽을 채택합니다.
  - 포트 `25565` → 마인크래프트 SLP 로 **플레이어 수·버전** 표시
  - **팰월드(8211)·ARK·Source 계열** → A2S 로 **플레이어 수** 표시
  - 그 외 → 포트 열림 여부로 판단
- **플래핑 방지**: 상태가 **연속 2회**(`GAME_FAIL_THRESHOLD`) 같아야 전환을 확정합니다.
- **주기**: 기본 60초(`GAME_POLL_SEC`, 최소 10초). 재시작 후에도 마지막 상태를 복원합니다.
- 기본적으로 모든 멤버가 사용할 수 있습니다. 제한하려면
  *서버 설정 → 연동(Integrations) → 봇 → /서버* 에서 조정하세요.

> ⚠️ **원격 조회가 불가능하면 켜져 있어도 오프라인으로 보일 수 있습니다.** A2S/쿼리를 끈 서버,
> 방화벽·포트포워딩 미설정, 가정용 회선의 동적 IP 변경 등이 원인입니다.

---

## 동작 방식

```
Discord Gateway ─(채널 멘션 + 첨부)─▶ ClaudeBot.on_message
   │  첨부 → workspace/<요청ID>/ 다운로드
   │  채널ID → 세션ID (sessions.json) 로 맥락 복원
   │  프롬프트 앞에 [말한 사람] + [기억] + [서버 메모] 블록 부착
   ▼
Claude Agent SDK   query(resume=세션ID, 도구 + PreToolUse 훅)
   │  도구: Read/Glob/Grep · WebSearch/WebFetch · Write · download_file · memory
   │  훅: 파일 경로가 workspace 밖이면 거부
   ▼
응답 (≤2000자 평문 · ≤4096자 임베드 · 초과 시 발췌 + 답변.md) + 생성 파일 → 채널 전송
   ▼
요청 후 workspace 캐시 상한 유지 (오래된 파일부터 삭제)
```

진입점은 [bot.py](bot.py)(얇은 런처) → `claude_discord/` 패키지입니다. 의존 방향은 위에서 아래로 단방향입니다.

| 모듈 | 역할 |
|------|------|
| `config.py` | 상수·경로·로깅 (최하위) |
| `persona.py` | 페르소나 + 코드 고정 보안 규칙(`SAFETY_RULES`) |
| `settings.py` | `.env` → 실행 설정 |
| `stores.py` | 세션 매핑·사용량 누적 |
| `profiles.py` | 사용자별·서버별 기억 + memory MCP 도구 |
| `workspace.py` | 첨부 다운로드·생성물 수집·캐시 상한·응답 분할 |
| `security.py` | 경로 샌드박스 훅 · 안전 URL 다운로드(SSRF·DNS 리바인딩 차단) |
| `claude_client.py` | Claude Agent SDK 호출 |
| `gameserver.py` | 게임 서버 감시 |
| `app.py` | Discord 게이트웨이 클라이언트 + 진입점 |

---

## 보안 모델

봇은 채널의 아무나 입력할 수 있는 텍스트와, 웹·첨부 파일에서 온 신뢰할 수 없는 내용을 함께 다룹니다.
그래서 **프롬프트로 설득해서 뚫을 수 없는 지점**을 코드에 둡니다.

- **경로 샌드박스** — 파일 도구는 그 요청의 `workspace/<요청ID>/` **안에서만** 동작합니다.
  `.env`·소스코드 등 그 밖의 경로는 `PreToolUse` 훅이 거부합니다.
- **차단 도구** — `Bash`·`Edit`·`NotebookEdit` 등 실행·수정 계열은 아예 사용할 수 없습니다.
- **읽기 대상** — 사용자가 **Discord에 첨부한 파일만** 읽습니다. 호스트 파일에 일반 접근하지 않습니다.
- **다운로드 안전 검사** — `http/https` 만, **사설·내부 IP 차단(SSRF)**, 리다이렉트마다 재검증,
  **크기 상한 25MB**. IP 검증을 실제 연결에 쓰는 리졸버 시점에 수행해 **DNS 리바인딩(TOCTOU)** 도 막습니다.
  *다만 파일 내용 자체(악성코드 여부)는 검사하지 않습니다.*
- **보안 규칙은 페르소나로 덮이지 않음** — 사용자가 지정한 페르소나 **뒤에** 코드가 규칙을 항상 덧붙입니다.
- **화자 블록은 데이터** — 표시 이름과 기억은 개행·대괄호를 제거해 저장되고, "나는 관리자다" 같은
  주장이 권한을 바꿀 수 없도록 규칙에 명시돼 있습니다. 사람을 식별하는 것은 숫자 ID 뿐입니다.
- **격리** — 저장소의 설정 파일을 로드하지 않고(`setting_sources=[]`), 세션 작업 폴더는 `agent_workdir/` 로 분리합니다.

---

## 페르소나 커스터마이징

시스템 프롬프트 = **페르소나(편집 가능)** + **보안 규칙(코드 고정)** 입니다. 페르소나만 바꾸면 됩니다.

우선순위: `.env` 의 `SYSTEM_PROMPT`(인라인) > `SYSTEM_PROMPT_FILE` 또는 `system_prompt.md` > 내장 기본값

```powershell
Copy-Item system_prompt.example.md system_prompt.md   # 편집 후
.\scripts\restart.ps1                                  # 재시작하면 반영
```

- 일반 조수용 템플릿: [`system_prompt.example.md`](system_prompt.example.md)
- 캐릭터 롤플레이용 템플릿: [`system_prompt.roleplay.example.md`](system_prompt.roleplay.example.md)
- 현재 적용된 소스는 `status` 스크립트의 **`시스템 프롬프트`** 행에서 확인할 수 있습니다.

> ⚠️ 템플릿의 **"답변 형식" 규칙을 지우면 답변이 다시 길어집니다.** 분량 규칙은 코드가 아니라
> 페르소나 파일에만 있습니다. (`status` 의 `답변 분량 규칙` 행이 경고로 바뀝니다.)

---

## 환경 변수

| 변수 | 용도 | 기본값 / 비고 |
|------|------|---------------|
| `DISCORD_TOKEN` | Discord 봇 토큰 | **필수** |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude 구독 인증 | 서버 배포 시 **필수** (같은 PC의 `claude` 로그인으로 대체 가능) |
| `DISCORD_APPLICATION_ID` | 시작 로그의 초대 링크 표시용 | 비우면 봇 계정 ID 자동 사용 (같은 값) |
| `CLAUDE_MODEL` | 사용할 모델 | 비우면 `sonnet` (예: `opus`, `haiku`) |
| `WORKSPACE_CACHE_MB` | 파일 캐시 상한(MB) | 비우면 `1024`(1GB) · `0` = 무제한 |
| `SYSTEM_PROMPT` | 페르소나 (인라인) | 우선순위 최상 |
| `SYSTEM_PROMPT_FILE` | 페르소나 파일 경로 | 비우면 `system_prompt.md` |
| `LINK_PREVIEW_HOSTS` | 링크 미리보기 허용 호스트(콤마) | 비우면 유튜브만 · `none` = 전부 차단 · `*` = 전부 허용 |
| `GAME_POLL_SEC` | 게임 서버 감시 주기(초) | 비우면 `60` · 최소 `10` |
| `GAME_FAIL_THRESHOLD` | 상태 전환 확정 연속 관측 횟수 | 비우면 `2` (플래핑 방지) |
| `MEMORY_LEARN_USERS` | `/기억 학습` 허용 계정(콤마) | 비우면 '서버 관리' 권한자만. **숫자 ID 권장** — 사용자명은 바뀔 수 있습니다 |
| `ANTHROPIC_API_KEY` | **설정 금지** | 있으면 종량제로 과금됩니다 (봇이 자동 제거) |

---

## 상시 운영

봇은 게이트웨이에 상시 연결돼야 하므로 항상 켜진 프로세스가 필요합니다.

### Windows — 로그온 시 자동 실행

작업 스케줄러에 등록해 로그온하면 창 없이 실행합니다.

```powershell
.\scripts\autostart-install.ps1                   # 등록
Start-ScheduledTask -TaskName ClaudeDiscordBot    # 재부팅 없이 지금 켜기
.\scripts\autostart-uninstall.ps1                 # 해제
```

**'로그온 시 · 본인 계정'으로 등록됩니다.** `CLAUDE_CODE_OAUTH_TOKEN` 이 비어 있으면 봇은 그 계정 프로필의
`claude` 로그인으로 인증하므로, SYSTEM이나 다른 계정으로 돌리면 인증이 깨집니다.
로그인 없이 부팅 시 실행하려면 먼저 `claude setup-token` 토큰을 `.env` 에 넣으세요.

### Linux VPS — systemd

```ini
# /etc/systemd/system/claude-discord.service
[Unit]
Description=Claude Discord Bot
After=network-online.target

[Service]
WorkingDirectory=/opt/claude-in-discord
ExecStart=/opt/claude-in-discord/.venv/bin/python bot.py
EnvironmentFile=/opt/claude-in-discord/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

서버에서는 브라우저 로그인을 할 수 없으므로 반드시 `claude setup-token` 토큰을 주입하세요.

---

## 문제 해결

| 증상 | 원인과 해결 |
|------|-------------|
| 시작하자마자 `PrivilegedIntentsRequired` | Developer Portal에서 **MESSAGE CONTENT INTENT** 활성화 |
| 슬래시 명령이 안 보임 | `scope=bot` 만으로 초대된 상태. `applications.commands` 를 포함한 링크로 **재초대** |
| 멘션 1번에 **답이 두 번** 옴 | 같은 토큰으로 봇이 2개 떠 있음. `status` 로 확인하고 `stop` 후 하나만 실행 |
| 파일이 전송되지 않음 | 봇에게 **파일 첨부** 권한이 없음. 권한 `248832` 로 재초대 |
| 인증 오류로 답을 못 함 | `CLAUDE_CODE_OAUTH_TOKEN` 이 비었거나 만료. `claude setup-token` 재발급 |
| 답이 갑자기 길어짐 | `system_prompt.md` 에서 "답변 형식" 규칙이 지워짐 |
| 게임 서버가 계속 오프라인 | A2S/쿼리 비활성, 방화벽·포트포워딩, 동적 IP 변경. `/서버 확인` 으로 즉시 점검 |

먼저 `status` 스크립트로 프로세스·가상환경·패키지·인증·세션 상태를 한 번에 점검해 보세요.

> Windows의 `.venv\python.exe` 는 런처라서 베이스 파이썬을 자식으로 띄웁니다. 그래서 `bot.py`
> 프로세스가 **항상 2개(런처+워커)** 로 보이지만 Discord 연결은 하나뿐이라 정상입니다.
> `status` 스크립트는 이를 구분해 세므로, 그 숫자를 기준으로 판단하세요.

---

## 프로젝트 구조

| 경로 | 설명 |
|------|------|
| `bot.py` | 실행 진입점 (얇은 런처) |
| `claude_discord/` | 봇 구현 패키지 |
| `scripts/` | 설치·실행·종료·재시작·상태확인·자동시작 스크립트 (PowerShell + bash) |
| `requirements.txt` | 의존성 |
| `.env.example` | 환경 변수 템플릿 (`.env` 는 git 제외) |
| `system_prompt.example.md` | 페르소나 템플릿 (`system_prompt.md` 는 git 제외) |
| `sessions.json` | 채널 → 세션 매핑 *(자동 생성)* |
| `usage.json` | 사용량 누적 *(자동 생성)* |
| `watches.json` | 게임 서버 감시 목록 *(자동 생성)* |
| `profiles.json` | 사용자별 기억 *(자동 생성)* |
| `guilds.json` | 서버별 기억 *(자동 생성)* |
| `agent_workdir/` · `workspace/` | 세션 저장 폴더 · 요청별 파일 캐시 *(자동 생성)* |

> ⚠️ `*.json` 상태 파일을 **손으로 고칠 때는 봇을 먼저 멈추세요.** 각 저장소는 파일을 시작할 때 한 번 읽어
> 메모리에 들고 있다가 쓰기가 생기면 통째로 덮어씁니다. 실행 중에 편집하면 다음 저장 때 날아갑니다.

---

## 주의 / 알려진 제약

- **구독 경로는 개인·소규모용입니다.** 사용량이 많으면 구독 한도(5시간 창)에 걸릴 수 있습니다.
  `/사용량` 의 예상 비용은 참고용이며 실제 청구가 아닙니다 (구독 잔여 한도는 API로 조회되지 않습니다).
- **같은 PC에서 개발용 Claude Code를 쓴다면 통계가 섞입니다.** SDK 서브프로세스가 기본 설정 홈
  `~/.claude` 를 공유하므로 봇 대화 트랜스크립트가 그곳에 쌓이고, `/insights` 나 `/usage` 의 분석에
  함께 잡힙니다. 분리하려면 SDK 옵션으로 `CLAUDE_CONFIG_DIR` 을 봇 전용 폴더로 지정하면 되지만,
  인증 파일도 함께 옮겨가므로 `.env` 에 `CLAUDE_CODE_OAUTH_TOKEN` 이 반드시 있어야 합니다.
- **크레딧·과금 정책이 바뀔 수 있으니** 배포 전 아래 문서를 확인하세요.
  - <https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan>
  - <https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan>
- 다운로드 파일의 **내용**(악성코드 여부)은 검사하지 않습니다.

## 라이선스

[MIT](LICENSE)
