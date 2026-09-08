# 작업 스케줄러가 로그온 시 실행하는 런처. (직접 실행할 일은 거의 없음)
#   - 이미 도는 봇이 있으면 중복 실행하지 않는다 (멘션 1번에 중복 응답 방지).
#   - 봇을 창 없이(백그라운드) 띄우고 로그는 파일로 남긴다.
#   등록: .\scripts\autostart-install.ps1   해제: .\scripts\autostart-uninstall.ps1

$Root = Split-Path -Parent $PSScriptRoot
$Py   = Join-Path $Root ".venv\Scripts\python.exe"
$Out  = Join-Path $Root "bot.out.log"
$Err  = Join-Path $Root "bot.err.log"

if (-not (Test-Path $Py)) {
    # 가상환경이 없으면 조용히 종료 (setup.ps1 미실행 상태)
    exit 1
}

# 중복 방지: 부모가 또 다른 bot.py 가 아닌 것(=root)만 세어 논리적 인스턴스 수를 구한다.
# (Windows venv 의 python.exe 는 런처라 런처+워커 2개로 보이는 게 정상)
$all = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'bot\.py' })
$allPids = @($all | ForEach-Object { $_.ProcessId })
$roots = @($all | Where-Object { $allPids -notcontains $_.ParentProcessId })
if ($roots.Count -gt 0) {
    # 이미 실행 중 → 아무것도 하지 않음
    exit 0
}

Start-Process -FilePath $Py -ArgumentList "bot.py" -WorkingDirectory $Root `
    -RedirectStandardOutput $Out -RedirectStandardError $Err -WindowStyle Hidden
