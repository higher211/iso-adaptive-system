$ErrorActionPreference = "Stop"
Set-Location "D:\下载\es_only_adaptive_sounding_system_package\final_deliverable_es_adaptive_sounding"
$logDir = "D:\下载\es_only_adaptive_sounding_system_package\final_deliverable_es_adaptive_sounding\outputs\final_full_run\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$mainLog = Join-Path $logDir "main_final_1800.log"
$sciLog = Join-Path $logDir "sci_supplement_final.log"
$statusFile = Join-Path $logDir "status.txt"
function Stamp($msg) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $statusFile -Value $line
    Write-Host $line
}
Stamp "START full-scale run"
Stamp "STEP 1 main final 1800 starts"
matlab -batch "addpath('code'); T=run_es_final_report_batch_test(struct('outputCsv','outputs/final_full_run/final_report_batch_validation_summary.csv','outputMat','outputs/final_full_run/final_report_batch_validation_summary.mat')); fprintf('MAIN_FINAL rows=%d maxFixedErr=%.3g feasibleRate=%.4f\n',height(T),max(T.fixedErr),mean(T.optimizationFeasible));" *> $mainLog
Stamp "STEP 1 main final 1800 finished"
Stamp "STEP 2 sci supplement final starts"
matlab -batch "addpath('code'); R=run_es_sci_supplement_experiments(struct('stage','final','outputDir','outputs/final_full_run/sci_supplement_final','figureDir','outputs/final_full_run/figures_final')); fprintf('SCI_FINAL baseline=%d ablation=%d figures=%d\n',height(R.baselineComparison),height(R.ablationStudy),numel(R.figureFiles));" *> $sciLog
Stamp "STEP 2 sci supplement final finished"
Stamp "DONE full-scale run"
