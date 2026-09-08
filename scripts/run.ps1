# 봇을 실행한다. (Windows / PowerShell)  항상 격리 가상환경(.venv)의 파이썬을 사용.
#   사용:  .\scripts\run.ps1
#
# 주의: 여기서 $ErrorActionPreference = "Stop" 을 쓰지 않는다.
#       python 로그가 (캡처/리다이렉트 환경에서) 네이티브 stderr 로 취급될 때
#       PowerShell 5.1 이 이를 에러로 감싸 스크립트를 중단시키기 때문.

$Root = Split-Path -Parent $PSScriptRoot          # 프로젝트 루트
$Py   = Join-Path $Root ".venv\Scripts\python.exe"

if (-not (Test-Path $Py)) {
    Write-Host "가상환경이 없습니다. 먼저  .\scripts\setup.ps1  을 실행하세요." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $Root ".env"))) {
    Write-Host "경고: .env 파일이 없습니다. .env.example 을 복사해 토큰을 채워주세요." -ForegroundColor Yellow
}

Set-Location $Root
& $Py (Join-Path $Root "bot.py")
exit $LASTEXITCODE
