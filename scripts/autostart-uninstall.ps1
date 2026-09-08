# 로그온 시 자동 실행 등록을 해제한다. (봇이 지금 돌고 있으면 그대로 둔다 — 종료는 stop.ps1)
#   사용:  .\scripts\autostart-uninstall.ps1
param([string]$TaskName = "ClaudeDiscordBot")

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "등록된 자동 시작이 없습니다. (작업 이름: $TaskName)" -ForegroundColor Yellow
    return
}

try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
} catch {
    Write-Host ("해제 실패: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host ("자동 시작 등록을 해제했습니다. (작업 이름: {0})" -f $TaskName) -ForegroundColor Green
Write-Host "  · 지금 도는 봇은 그대로입니다. 종료하려면  .\scripts\stop.ps1"
