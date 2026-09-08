# 기존 봇을 종료하고 새로 실행한다. (Windows / PowerShell)  코드 변경 반영용.
#   사용:  .\scripts\restart.ps1

& (Join-Path $PSScriptRoot "stop.ps1")
Start-Sleep -Seconds 1
& (Join-Path $PSScriptRoot "run.ps1")
