# 봇 상태 확인 / 진단. (Windows / PowerShell)
#   사용:  .\scripts\status.ps1            (로컬 점검)
#          .\scripts\status.ps1 -Online    (Discord API 로 토큰/공개여부까지)
param([switch]$Online)

$Root  = Split-Path -Parent $PSScriptRoot
$Py    = Join-Path $Root ".venv\Scripts\python.exe"
$EnvF  = Join-Path $Root ".env"
$WSDir = Join-Path $Root "workspace"

function Row {
    param([string]$Status, [string]$Label, [string]$Detail)
    $tag = '[ -- ]'; $color = 'Gray'
    if ($Status -eq 'ok')   { $tag = '[ OK ]'; $color = 'Green' }
    if ($Status -eq 'warn') { $tag = '[WARN]'; $color = 'Yellow' }
    if ($Status -eq 'fail') { $tag = '[FAIL]'; $color = 'Red' }
    Write-Host $tag -ForegroundColor $color -NoNewline
    Write-Host ("  " + $Label.PadRight(20) + " " + $Detail)
}

function Get-EnvVal {
    param([string]$Key)
    if (-not (Test-Path $EnvF)) { return '' }
    foreach ($l in Get-Content $EnvF) {
        if ($l -match ('^\s*' + $Key + '\s*=(.*)')) { return $matches[1].Trim() }
    }
    return ''
}

Write-Host "== Claude Discord 봇 상태 ==" -ForegroundColor Cyan

# 1) 봇 프로세스
#    Windows venv 의 python.exe 는 '런처'라, 실행하면 베이스 파이썬을 자식으로 띄운다.
#    → OS 프로세스는 (런처+워커) 2개로 보이지만 논리적 봇은 1개.
#    부모가 또 다른 bot.py 프로세스가 아닌 것(=root)만 세어 진짜 인스턴스 수를 구한다.
$all = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -match 'bot\.py' })
$allPids = @($all | ForEach-Object { $_.ProcessId })
$roots = @($all | Where-Object { $allPids -notcontains $_.ParentProcessId })
if ($roots.Count -eq 0) {
    Row 'warn' '봇 프로세스' '중지됨 (실행: scripts\run.ps1)'
} elseif ($roots.Count -eq 1) {
    $detail = '실행 중 (PID ' + $roots[0].ProcessId + ')'
    $workers = $all.Count - $roots.Count
    if ($workers -gt 0) { $detail += (' +워커 ' + $workers + '개') }   # venv 런처가 띄운 실제 파이썬
    Row 'ok' '봇 프로세스' $detail
} else {
    $pidList = ($roots | ForEach-Object { $_.ProcessId }) -join ','
    Row 'fail' '봇 프로세스' ('중복 ' + $roots.Count + '개 실행! PID: ' + $pidList + ' — 1개만 남기세요')
}

# 2) 가상환경 + 파이썬
if (Test-Path $Py) {
    $pyver = & $Py --version
    Row 'ok' '가상환경(.venv)' "$pyver"
} else {
    Row 'fail' '가상환경(.venv)' '없음 (실행: scripts\setup.ps1)'
}

# 3) 핵심 패키지 (파이썬 코드는 변수로 만들어 전달 — 인라인 다중행 파싱 회피)
if (Test-Path $Py) {
    $code = "import importlib.metadata as m`n" +
            "for p in ['discord.py','claude-agent-sdk','python-dotenv']:`n" +
            "    try: print(p, m.version(p))`n" +
            "    except Exception: print(p, 'MISSING')"
    $pkgs = & $Py -c $code
    foreach ($line in $pkgs) {
        if ("$line" -match 'MISSING') { Row 'fail' '패키지' "$line" } else { Row 'ok' '패키지' "$line" }
    }
}

# 4) .env / 시크릿 (값은 마스킹)
if (Test-Path $EnvF) {
    $dt = Get-EnvVal 'DISCORD_TOKEN'
    $ct = Get-EnvVal 'CLAUDE_CODE_OAUTH_TOKEN'
    $cm = Get-EnvVal 'CLAUDE_MODEL'
    $ai = Get-EnvVal 'DISCORD_APPLICATION_ID'
    if ($dt) { Row 'ok' 'DISCORD_TOKEN' ('설정됨 (길이 ' + $dt.Length + ')') } else { Row 'fail' 'DISCORD_TOKEN' '비어있음' }
    if ($ct) { Row 'ok' 'OAUTH_TOKEN' ('설정됨 (길이 ' + $ct.Length + ')') } else { Row 'warn' 'OAUTH_TOKEN' '비어있음 (로컬 로그인 / 서버 배포 시 필요)' }
    if ($cm) { Row 'ok' 'CLAUDE_MODEL' $cm } else { Row 'ok' 'CLAUDE_MODEL' '기본값 sonnet' }
    if ($ai) {
        if ($ai -match '^\d+$') { Row 'ok' '앱 ID' "$ai (초대 링크용)" }
        else { Row 'warn' '앱 ID' 'DISCORD_APPLICATION_ID 가 숫자가 아님 — 봇 계정 ID 로 대체됨' }
    } else { Row 'ok' '앱 ID' '봇 계정 ID 자동 사용 (DISCORD_APPLICATION_ID 미설정)' }
} else {
    Row 'fail' '.env' '없음 (.env.example 복사)'
}

# 4b) 시스템 프롬프트 소스
$sp  = Get-EnvVal 'SYSTEM_PROMPT'
$spf = Get-EnvVal 'SYSTEM_PROMPT_FILE'
if ($sp) { Row 'ok' '시스템 프롬프트' 'env SYSTEM_PROMPT (인라인)' }
elseif ($spf -and (Test-Path $spf)) { Row 'ok' '시스템 프롬프트' "file: $spf" }
elseif ($spf) { Row 'warn' '시스템 프롬프트' "지정 파일 없음: $spf (기본값 사용)" }
elseif (Test-Path (Join-Path $Root 'system_prompt.md')) { Row 'ok' '시스템 프롬프트' 'file: system_prompt.md' }
else { Row 'ok' '시스템 프롬프트' '기본값 (내장 페르소나)' }

# 5) ANTHROPIC_API_KEY (있으면 종량제 과금 위험)
if ($env:ANTHROPIC_API_KEY) {
    Row 'warn' 'ANTHROPIC_API_KEY' '환경에 설정됨! 종량제 위험 (봇은 시작 시 무시)'
} else {
    Row 'ok' 'ANTHROPIC_API_KEY' '없음 (구독 인증만 — 정상)'
}

# 6) claude CLI
$claude = Get-Command claude -ErrorAction SilentlyContinue
if ($claude) {
    $cv = & claude --version
    Row 'ok' 'claude CLI' "$cv"
} else {
    Row 'warn' 'claude CLI' '미발견 (SDK 번들 CLI 로도 동작)'
}

# 7) 세션 상태
$sf = Join-Path $Root "sessions.json"
if (Test-Path $sf) {
    $scode = "import json; print(len(json.load(open(r'" + $sf + "', encoding='utf-8'))))"
    $n = & $Py -c $scode
    Row 'ok' 'sessions.json' ('채널 ' + "$n".Trim() + '개 맥락 저장됨')
} else {
    Row 'ok' 'sessions.json' '없음 (첫 대화 시 생성)'
}

# 8) workspace 파일 캐시
$capMb = 1024
$capRaw = Get-EnvVal 'WORKSPACE_CACHE_MB'
if ($capRaw -match '^\d+$') { $capMb = [int]$capRaw }
$capText = if ($capMb -eq 0) { '무제한' } else { "$capMb MB" }
if (Test-Path $WSDir) {
    $items = @(Get-ChildItem $WSDir -Recurse -File -ErrorAction SilentlyContinue)
    $sum = ($items | Measure-Object -Property Length -Sum).Sum
    if (-not $sum) { $sum = 0 }
    $mb = [math]::Round($sum / 1MB, 1)
    $reqDirs = @(Get-ChildItem $WSDir -Directory -ErrorAction SilentlyContinue).Count
    $detail = "$mb MB / 상한 $capText  (요청폴더 $($reqDirs)개, 파일 $($items.Count)개)"
    if ($capMb -gt 0 -and $mb -gt $capMb) { Row 'warn' 'workspace 캐시' $detail }
    else { Row 'ok' 'workspace 캐시' $detail }
} else {
    Row 'ok' 'workspace 캐시' "없음 (상한 $capText, 첫 파일 요청 시 생성)"
}

# 8b) 파일 다운로드 도구
Row 'ok' '파일 다운로드' '허용 (<=25MB, http/https, SSRF·DNS리바인딩 차단)'

# 8b-2) 답변 전송 형식 + 분량 규칙 (긴 답변 가독성)
Row 'ok' '답변 전송' '2000자 이하 평문 / 4096자 이하 임베드 1개 / 초과 시 발췌 + 답변.md 첨부'
$lph = Get-EnvVal 'LINK_PREVIEW_HOSTS'
if (-not $lph) { Row 'ok' '링크 미리보기' '유튜브만 허용 (기본) - 그 외 링크는 카드 안 붙음' }
elseif ($lph -eq '*') { Row 'warn' '링크 미리보기' '전부 허용 (*) - 링크마다 카드가 붙음' }
elseif ($lph -eq 'none') { Row 'ok' '링크 미리보기' '전부 차단 (none)' }
else { Row 'ok' '링크 미리보기' ('허용 호스트: ' + $lph) }
$personaTxt = 'FORMAT'   # 내장 기본 페르소나에는 분량 규칙이 들어있음
if ($sp) { $personaTxt = $sp }
elseif ($spf -and (Test-Path $spf)) { $personaTxt = Get-Content -Raw -Encoding UTF8 $spf }
elseif (Test-Path (Join-Path $Root 'system_prompt.md')) { $personaTxt = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'system_prompt.md') }
if ($personaTxt -match '답변 형식|FORMAT') {
    Row 'ok' '답변 분량 규칙' '페르소나에 있음'
} else {
    Row 'warn' '답변 분량 규칙' '페르소나에 없음 - 답변이 길어짐 (system_prompt.example.md 참고)'
}

# 8c) 누적 사용량
$uf = Join-Path $Root "usage.json"
if (Test-Path $uf) {
    try {
        $u = Get-Content -Raw -Encoding UTF8 $uf | ConvertFrom-Json
        $cost = 0.0
        if ($u.total -and $u.total.cost_usd) { $cost = [math]::Round([double]$u.total.cost_usd, 2) }
        Row 'ok' '누적 사용량' ('요청 ' + [int]$u.requests + '회, 예상 $' + $cost)
    } catch {
        Row 'warn' '누적 사용량' 'usage.json 파싱 실패'
    }
} else {
    Row 'ok' '누적 사용량' '없음 (첫 요청 시 생성)'
}

# 8d) 고아 세션 (매핑 안 된 .jsonl)
$enc = ((Join-Path $Root "agent_workdir") -replace '[^A-Za-z0-9]', '-')
$projDir = Join-Path $env:USERPROFILE ".claude\projects\$enc"
if (Test-Path $projDir) {
    $keep = @{}
    $sfp = Join-Path $Root 'sessions.json'
    if (Test-Path $sfp) {
        try { (Get-Content $sfp -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Value |
                ForEach-Object { if ($_) { $keep[[string]$_] = $true } } } catch {}
    }
    $orphans = @(Get-ChildItem $projDir -Filter *.jsonl -File -ErrorAction SilentlyContinue |
        Where-Object { -not $keep.ContainsKey($_.BaseName) })
    if ($orphans.Count -gt 0) {
        Row 'warn' '고아 세션' ('' + $orphans.Count + '개 (정리: scripts\clean-sessions.ps1)')
    } else {
        Row 'ok' '고아 세션' '없음'
    }
} else {
    Row 'ok' '고아 세션' '세션 폴더 없음'
}

# 8e) 게임 서버 감시 (온라인/오프라인 알림)
$wf = Join-Path $Root "watches.json"
if (Test-Path $wf) {
    try {
        $w = Get-Content -Raw -Encoding UTF8 $wf | ConvertFrom-Json
        $props = @($w.PSObject.Properties)
        if ($props.Count -eq 0) {
            Row 'ok' '게임 서버 감시' '등록된 서버 없음 (/서버 추가 로 등록)'
        } else {
            $on  = @($props | Where-Object { $_.Value.state -eq 'online' }).Count
            $off = @($props | Where-Object { $_.Value.state -eq 'offline' }).Count
            Row 'ok' '게임 서버 감시' ('' + $props.Count + '개 감시 (온라인 ' + $on + ' · 오프라인 ' + $off + ')')
        }
    } catch {
        Row 'warn' '게임 서버 감시' 'watches.json 파싱 실패'
    }
} else {
    Row 'ok' '게임 서버 감시' '없음 (/서버 추가 로 등록)'
}

# 8e-2) 사용자 기억(프로필) — 사용자별 특징을 서버(길드) 단위로 기억
$pf = Join-Path $Root "profiles.json"
if (Test-Path $pf) {
    try {
        $pr = Get-Content -Raw -Encoding UTF8 $pf | ConvertFrom-Json
        $entries = @($pr.PSObject.Properties | Where-Object { $_.Value.facts })
        if ($entries.Count -eq 0) {
            Row 'ok' '사용자 기억' '기록 없음 (확인/삭제: /기억)'
        } else {
            $nfacts = ($entries | ForEach-Object { @($_.Value.facts).Count } | Measure-Object -Sum).Sum
            $nguilds = @($entries | ForEach-Object { ($_.Name -split ':')[0] } | Sort-Object -Unique).Count
            Row 'ok' '사용자 기억' ('사용자 ' + $entries.Count + '명 · ' + $nfacts + '건 (서버 ' + $nguilds + '개, 상한 20건/인)')
        }
    } catch {
        Row 'warn' '사용자 기억' 'profiles.json 파싱 실패'
    }
} else {
    Row 'ok' '사용자 기억' '없음 (대화 중 자동 생성 · 확인/삭제: /기억)'
}

# 8e-2b) 서버 기억 (서버 분위기 메모 — 그 서버 사람 모두에게 공유)
$gf = Join-Path $Root "guilds.json"
if (Test-Path $gf) {
    try {
        $gj = Get-Content -Raw -Encoding UTF8 $gf | ConvertFrom-Json
        $gentries = @($gj.PSObject.Properties | Where-Object { $_.Value.facts })
        if ($gentries.Count -eq 0) {
            Row 'ok' '서버 기억' '기록 없음 (확인: /기억 서버)'
        } else {
            $gnotes = ($gentries | ForEach-Object { @($_.Value.facts).Count } | Measure-Object -Sum).Sum
            Row 'ok' '서버 기억' ('서버 ' + $gentries.Count + '개 · ' + $gnotes + '건 (상한 16건/서버)')
        }
    } catch {
        Row 'warn' '서버 기억' 'guilds.json 파싱 실패'
    }
} else {
    Row 'ok' '서버 기억' '없음 (대화 중 자동 생성 · 확인: /기억 서버)'
}

# 8e-3) `/기억 학습` 허용 계정 (관리 권한 없이도 실행 가능한 계정)
$lu = Get-EnvVal 'MEMORY_LEARN_USERS'
if ($lu) {
    Row 'ok' '학습 허용 계정' ($lu + '  (+ 서버 관리 권한자)')
} else {
    Row 'ok' '학습 허용 계정' "'서버 관리' 권한자만 (MEMORY_LEARN_USERS 미설정)"
}

# 8f) 자동 시작 (작업 스케줄러 — 로그온 시 백그라운드 실행)
$task = Get-ScheduledTask -TaskName 'ClaudeDiscordBot' -ErrorAction SilentlyContinue
if ($task) {
    if ($task.State -eq 'Disabled') {
        Row 'warn' '자동 시작' '등록됨(사용 안 함) — 작업 스케줄러에서 활성화 필요'
    } else {
        Row 'ok' '자동 시작' '등록됨 (로그온 시 자동 실행)'
    }
} else {
    Row 'ok' '자동 시작' '미등록 (등록: scripts\autostart-install.ps1)'
}

# 9) (옵션) Discord API 온라인 점검
if ($Online) {
    Write-Host "-- Discord API 점검 --" -ForegroundColor Cyan
    $token = Get-EnvVal 'DISCORD_TOKEN'
    if (-not $token) {
        Row 'fail' 'Discord API' 'DISCORD_TOKEN 없음'
    } else {
        $json = & curl.exe -s -H "Authorization: Bot $token" "https://discord.com/api/v10/applications/@me"
        $app = $null
        try { $app = $json | ConvertFrom-Json } catch { $app = $null }
        if ($app -and $app.id) {
            Row 'ok' '토큰 유효' ($app.name + ' (id=' + $app.id + ')')
            if ($app.bot_public) {
                Row 'warn' 'Public Bot' 'true — 아무나 초대 가능 (개인용이면 false 권장)'
            } else {
                Row 'ok' 'Public Bot' 'false — 소유자만 초대 가능'
            }
            Row 'ok' '참여 서버 수' ("" + $app.bot_approximate_guild_count)
        } else {
            Row 'fail' 'Discord API' ('응답 이상: ' + $json)
        }
    }
}
