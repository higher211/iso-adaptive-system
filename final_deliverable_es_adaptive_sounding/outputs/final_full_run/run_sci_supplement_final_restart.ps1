$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

$logDir = Join-Path $root "outputs\final_full_run\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$statusFile = Join-Path $logDir "status.txt"
$restartLog = Join-Path $logDir "sci_supplement_final_restart.log"

function Stamp($msg) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $statusFile -Value $line
    Write-Host $line
}

Stamp "RESTART sci supplement final starts"
matlab -batch "addpath('code'); R=run_es_sci_supplement_experiments(struct('stage','final','outputDir','outputs/final_full_run/sci_supplement_final','figureDir','outputs/final_full_run/figures_final')); fprintf('SCI_FINAL_RESTART baseline=%d ablation=%d figures=%d\n',height(R.baselineComparison),height(R.ablationStudy),numel(R.figureFiles));" *> $restartLog
$exitCode = $LASTEXITCODE
Stamp ("RESTART sci supplement final matlab exit code=" + $exitCode)
if ($exitCode -ne 0) {
    throw "SCI supplement final restart failed with exit code $exitCode"
}
Stamp "RESTART sci supplement final finished"
