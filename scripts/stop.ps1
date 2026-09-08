# 실행 중인 봇(bot.py) 프로세스를 모두 종료한다. (Windows / PowerShell)
#   사용:  .\scripts\stop.ps1

$procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match 'bot\.py' })

if ($procs.Count -eq 0) {
    Write-Host "실행 중인 봇이 없습니다."
    return
}

$killed = 0
foreach ($p in $procs) {
    try {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
        Write-Host ("종료: PID {0}" -f $p.ProcessId)
        $killed++
    } catch {
        Write-Host ("이미 종료됨: PID {0}" -f $p.ProcessId) -ForegroundColor DarkGray
    }
}
Write-Host ("봇 프로세스 {0}개 종료 완료." -f $killed)
