# 격리 가상환경(.venv) 생성 + 의존성 설치. (Windows / PowerShell)  최초 1회.
#   사용:  .\scripts\setup.ps1
# ($ErrorActionPreference=Stop 미사용 — pip 의 네이티브 stderr 로 중단되는 것 방지)

$Root = Split-Path -Parent $PSScriptRoot
$Py   = Join-Path $Root ".venv\Scripts\python.exe"
Set-Location $Root

if (-not (Test-Path $Py)) {
    Write-Host "가상환경(.venv) 생성 중..."
    python -m venv .venv
    if ($LASTEXITCODE -ne 0) { Write-Host "venv 생성 실패 (python 설치 확인)" -ForegroundColor Red; exit 1 }
}

Write-Host "pip 업그레이드..."
& $Py -m pip install --upgrade pip --quiet

Write-Host "의존성 설치 중 (requirements.txt)..."
& $Py -m pip install -r (Join-Path $Root "requirements.txt")
if ($LASTEXITCODE -ne 0) { Write-Host "의존성 설치 실패" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "설치 완료. 다음 순서로 실행하세요:" -ForegroundColor Green
Write-Host "  1) .env 에 DISCORD_TOKEN / CLAUDE_CODE_OAUTH_TOKEN 입력"
Write-Host "  2) .\scripts\run.ps1"
