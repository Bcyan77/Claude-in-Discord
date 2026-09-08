# 매핑되지 않은(고아) Claude 세션 트랜스크립트(.jsonl)를 정리한다. (Windows / PowerShell)
#   sessions.json 에 없는 세션 = 테스트/리셋으로 남은 고아 → 삭제.
#
#   .\scripts\clean-sessions.ps1              # 실제 삭제
#   .\scripts\clean-sessions.ps1 -DryRun      # 미리보기(삭제 안 함) — 먼저 이걸 권장
#   .\scripts\clean-sessions.ps1 -MinAgeMinutes 0   # 최근 파일 보호 해제
param([switch]$DryRun, [int]$MinAgeMinutes = 60)

$Root = Split-Path -Parent $PSScriptRoot

# 세션 저장 폴더 = ~/.claude/projects/<agent_workdir 절대경로를 인코딩한 이름>
$work    = Join-Path $Root "agent_workdir"
$encoded = ($work -replace '[^A-Za-z0-9]', '-')
$projDir = Join-Path $env:USERPROFILE ".claude\projects\$encoded"

if (-not (Test-Path $projDir)) {
    Write-Host "세션 폴더가 없습니다 (정리할 것 없음): $projDir" -ForegroundColor Yellow
    return
}

# 안전장치: sessions.json 이 없거나 파싱 실패하면 삭제하지 않고 중단
$sf = Join-Path $Root "sessions.json"
if (-not (Test-Path $sf)) {
    Write-Host "sessions.json 이 없습니다 — 안전을 위해 중단합니다." -ForegroundColor Red
    return
}
try {
    $vals = (Get-Content $sf -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Value
} catch {
    Write-Host "sessions.json 파싱 실패 — 안전을 위해 중단합니다." -ForegroundColor Red
    return
}
$keep = @{}
foreach ($v in $vals) { if ($v) { $keep[[string]$v] = $true } }

$cutoff = (Get-Date).AddMinutes(-[math]::Abs($MinAgeMinutes))
$kept = 0; $recent = 0; $deleted = 0; $freed = 0L
foreach ($f in (Get-ChildItem $projDir -Filter *.jsonl -File -ErrorAction SilentlyContinue)) {
    if ($keep.ContainsKey($f.BaseName)) { $kept++; continue }
    if ($f.LastWriteTime -gt $cutoff)   { $recent++; continue }   # 최근 수정 파일 보호
    $freed += $f.Length
    if ($DryRun) {
        Write-Host ("[미리보기] 삭제 대상: {0} ({1:N0} bytes)" -f $f.Name, $f.Length)
    } else {
        try { Remove-Item $f.FullName -Force -ErrorAction Stop; Write-Host ("삭제: {0}" -f $f.Name) }
        catch { Write-Host ("삭제 실패: {0} — {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Yellow; continue }
    }
    $deleted++
}

$mb   = [math]::Round($freed / 1MB, 2)
$verb = if ($DryRun) { '삭제 예정' } else { '삭제됨' }
Write-Host ""
Write-Host ("정리 완료: 유지 {0}개 · 최근보호 {1}개 · {2} {3}개 ({4} MB)" -f $kept, $recent, $verb, $deleted, $mb) -ForegroundColor Green
if ($DryRun) { Write-Host "실제 삭제하려면 -DryRun 없이 다시 실행하세요." -ForegroundColor Cyan }
