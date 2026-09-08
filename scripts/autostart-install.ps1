# 봇을 '로그온 시 백그라운드 자동 실행' 으로 등록한다. (Windows 작업 스케줄러)
#   사용:  .\scripts\autostart-install.ps1
#   해제:  .\scripts\autostart-uninstall.ps1
#
# 왜 '로그온 시 / 내 계정' 인가:
#   CLAUDE_CODE_OAUTH_TOKEN 이 비어 있으면 봇은 내 프로필의 claude 로그인 인증을 쓴다.
#   SYSTEM 이나 다른 계정으로 돌리면 그 인증을 못 찾아 실패한다.
#   로그인 없이(부팅 시) 돌리려면 먼저 `claude setup-token` 으로 토큰을 발급해 .env 에 넣을 것.
param([string]$TaskName = "ClaudeDiscordBot")

$Root   = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $Root "scripts\autostart-run.ps1"
$Py     = Join-Path $Root ".venv\Scripts\python.exe"

if (-not (Test-Path $Py)) {
    Write-Host "가상환경이 없습니다. 먼저  .\scripts\setup.ps1  을 실행하세요." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Runner)) {
    Write-Host "런처를 찾을 수 없습니다: $Runner" -ForegroundColor Red
    exit 1
}

$user = "$env:USERDOMAIN\$env:USERNAME"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $Runner) `
    -WorkingDirectory $Root

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user

# Hidden = 창 숨김, ExecutionTimeLimit 0 = 시간 제한 없음, IgnoreNew = 중복 인스턴스 금지
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -Hidden -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description "Claude Discord 봇 — 로그온 시 백그라운드 자동 실행" -Force | Out-Null
} catch {
    Write-Host ("등록 실패: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host "관리자 권한 PowerShell 에서 다시 시도해 보세요." -ForegroundColor Yellow
    exit 1
}

Write-Host ("자동 시작 등록 완료: 작업 이름 '{0}' (로그온 시 · 계정 {1})" -f $TaskName, $user) -ForegroundColor Green
Write-Host "  · 지금 바로 켜보려면:  Start-ScheduledTask -TaskName $TaskName"
Write-Host "  · 상태 확인:          .\scripts\status.ps1"
Write-Host "  · 등록 해제:          .\scripts\autostart-uninstall.ps1"
Write-Host "  · 봇 종료:            .\scripts\stop.ps1   (다음 로그온 때 다시 자동 실행됨)"
