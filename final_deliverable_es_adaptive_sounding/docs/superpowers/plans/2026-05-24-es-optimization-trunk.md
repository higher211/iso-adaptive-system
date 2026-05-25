# Es任务驱动寻优主干 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将主代码中的 Es 复探寻优阶段实现为“固定扫频窗口、统一搜索范围、不同模式基线/偏好驱动 Pareto 寻优”。

**Architecture:** 保持单 MATLAB 主文件结构。`build_es_target_region` 生成固定扫频范围；`make_es_optimizer_preference` 定义统一可行域；`make_es_task_profile` 只定义模式基线和偏好；`task_objective_vector` 不再使用覆盖率；`es_constraint_violation` 处理硬约束和模式基线；`select_task_pareto_row` 从 Pareto 候选中按模式推荐最终策略。

**Tech Stack:** MATLAB，NSGA-II，PowerShell，`matlab -batch`，Git。

---

## 文件结构

- Modify: `D:\下载\es_only_adaptive_sounding_system_package\final_deliverable_es_adaptive_sounding\code\es_only_adaptive_sounding_system.m`
  - 固定 `fStartMHz/fEndMHz`，不进入寻优。
  - 删除模式对 `bounds/codeTypeSet/NcohIntegerRange` 的覆盖。
  - 从目标函数中移除 `EsCoverage`。
  - 增加 `complexityCost` 指标。
  - 将模式差异集中到 baseline、objectiveMode、selectionMode。
  - 移除范围收缩类旧约束。
- Reference: `D:\下载\es_only_adaptive_sounding_system_package\final_deliverable_es_adaptive_sounding\docs\es_task_driven_optimization_technical_route.md`
- Reference: `D:\下载\es_only_adaptive_sounding_system_package\final_deliverable_es_adaptive_sounding\docs\superpowers\specs\2026-05-24-es-optimization-trunk-design.md`

## Task 1: 基线检查

- [ ] **Step 1: 查看当前修改状态**

Run:

```powershell
git status --short
```

Expected:

```text
 M code/es_only_adaptive_sounding_system.m
?? docs/
```

- [ ] **Step 2: 定位旧逻辑**

Run:

```powershell
Select-String -Path 'code\es_only_adaptive_sounding_system.m' -Pattern 'profile.bounds|profile.codeTypeSet|profile.NcohIntegerRange|EsCoverage|maxAggressiveShrinkRatio|notOverShrunk|task_objective_vector|select_task_pareto_row'
```

Expected:

```text
显示模式专属搜索范围、覆盖率目标、范围收缩约束和目标/选择函数的位置。
```

## Task 2: 固定扫频窗口

- [ ] **Step 1: 修改 `nsga2_bounds`**

目标形态：

```matlab
function b = nsga2_bounds(target, pref)
    reqLow = target.requiredRangeMHz(1);
    reqHigh = target.requiredRangeMHz(2);
    pb = pref.bounds;
    b.lo = [reqLow, reqHigh, pb.dfMHz(1), pb.PRP(1), pb.chipLength(1), pref.NcohIntegerRange(1), 1];
    b.hi = [reqLow, reqHigh, pb.dfMHz(2), pb.PRP(2), pb.chipLength(2), pref.NcohIntegerRange(2), numel(pref.codeLengthSet)];
end
```

- [ ] **Step 2: 修改 `repair_nsga2_x`**

目标逻辑：

```matlab
function x = repair_nsga2_x(x, target, pref)
    b = nsga2_bounds(target, pref);
    x = min(max(x, b.lo), b.hi);
    x(1) = target.requiredRangeMHz(1);
    x(2) = target.requiredRangeMHz(2);
    x(6) = round((round(x(6)) - pref.NcohIntegerRange(1)) / pref.NcohSearchStep) * pref.NcohSearchStep + pref.NcohIntegerRange(1);
    x(6) = min(max(x(6), pref.NcohIntegerRange(1)), pref.NcohIntegerRange(2));
    x(7) = min(max(round(x(7)), 1), numel(pref.codeLengthSet));
    x(1) = target.requiredRangeMHz(1);
    x(2) = target.requiredRangeMHz(2);
end
```

## Task 3: 统一搜索范围

- [ ] **Step 1: 保留全局范围**

在 `make_es_optimizer_preference` 中保留统一范围：

```matlab
pref.bounds.dfMHz = [0.02, 0.50];
pref.bounds.PRP = [5e-3, 15e-3];
pref.bounds.chipLength = [8e-6, 40e-6];
pref.codeTypeSet = {'barker','complementary'};
pref.codeLengthSet = [13, 16];
pref.NcohIntegerRange = [6, 48];
```

- [ ] **Step 2: 移除模式覆盖范围**

从 `apply_task_profile_to_preferences` 或等价函数中删除：

```matlab
pref.codeTypeSet = profile.codeTypeSet;
pref.codeLengthSet = profile.codeLengthSet;
pref.NcohIntegerRange = profile.NcohIntegerRange;
pref.bounds = apply_struct_override(pref.bounds, profile.bounds);
```

从 `make_es_task_profile` 中删除或清空：

```matlab
profile.codeTypeSet
profile.codeLengthSet
profile.NcohIntegerRange
profile.bounds
```

## Task 4: 模式基线结构

- [ ] **Step 1: 在 `make_es_task_profile` 中定义 baseline**

每个模式只定义：

```matlab
profile.objectiveMode = '...';
profile.selectionMode = '...';
profile.baseline = struct(...);
```

示例：

```matlab
profile.baseline.maxScanTimeSec = 1.20;
profile.baseline.scanTimeRatioToInitial = 0.35;
profile.baseline.minFrequencySamples = 5;
profile.baseline.minIntegrationGainDb = 13.5;
profile.baseline.minObservabilityScore = 0.55;
profile.baseline.maxDfMHz = 0.40;
```

- [ ] **Step 2: 保持基线是评价标准而不是搜索边界**

不要把 baseline 中的 `maxDfMHz`、`minNcoh` 等写入 `pref.bounds` 或 `pref.NcohIntegerRange`。

## Task 5: 指标计算

- [ ] **Step 1: 在 `es_strategy_cost` 中增加 `complexityCost`**

目标逻辑：

```matlab
complexityCost = 0.15*double(is_complementary_mode(cfg)) + 0.03*(cfg.Ncoh / pref.NcohIntegerRange(2));
metric.complexityCost = complexityCost;
```

- [ ] **Step 2: 调整可观测性计算**

固定窗口后，`observabilityScore` 不再依赖覆盖率：

```matlab
integrationScore = normalize_score(integrationGainDb, pref.minIntegrationGainDb - 6, pref.minIntegrationGainDb + 8);
observabilityScore = integrationScore;
```

保留 `EsCoverage` 作为一致性检查字段。

## Task 6: 目标函数更新

- [ ] **Step 1: 从 `task_objective_vector` 移除 `EsCoverage`**

目标形态：

```matlab
switch get_opt(pref, 'objectiveMode', 'balanced')
    case 'fast'
        obj = [metric.scanTimeSec, -metric.observabilityScore, metric.complexityCost];
    case 'foes'
        obj = [cfg.dfMHz, metric.scanTimeSec, -metric.integrationGainDb];
    case 'height'
        obj = [metric.heightResolutionKm, -metric.integrationGainDb, metric.scanTimeSec];
    case 'weak'
        obj = [-metric.observabilityScore, -metric.integrationGainDb, metric.scanTimeSec];
    case 'full_trace'
        obj = [cfg.dfMHz, metric.resolutionCost, -metric.observabilityScore, metric.scanTimeSec];
    otherwise
        obj = [metric.scanTimeSec, metric.resolutionCost, -metric.observabilityScore];
end
```

## Task 7: 约束违反量更新

- [ ] **Step 1: 移除范围收缩约束**

删除有效逻辑：

```matlab
maxAggressiveShrinkRatio
notOverShrunk
```

- [ ] **Step 2: 加入 baseline 惩罚**

实现一个小函数或内联逻辑，从 `pref.taskProfile.baseline` 读取字段：

```matlab
v = v + baseline_violation(metric, cfg, baseCfgOrInitialScanTime, pref);
```

若不新增函数，则在 `es_constraint_violation` 中按字段存在性计算：

```matlab
if isfield(b, 'maxScanTimeSec')
    v = v + max(0, metric.scanTimeSec - b.maxScanTimeSec) / max(b.maxScanTimeSec, eps);
end
if isfield(b, 'minFrequencySamples')
    v = v + max(0, b.minFrequencySamples - metric.nFreq) / max(b.minFrequencySamples, eps);
end
if isfield(b, 'minIntegrationGainDb')
    v = v + max(0, b.minIntegrationGainDb - metric.integrationGainDb) / max(b.minIntegrationGainDb, eps);
end
if isfield(b, 'minObservabilityScore')
    v = v + max(0, b.minObservabilityScore - metric.observabilityScore);
end
if isfield(b, 'maxDfMHz')
    v = v + max(0, cfg.dfMHz - b.maxDfMHz) / max(b.maxDfMHz, eps);
end
if isfield(b, 'maxHeightResolutionKm')
    v = v + max(0, metric.heightResolutionKm - b.maxHeightResolutionKm) / max(b.maxHeightResolutionKm, eps);
end
```

## Task 8: Pareto推荐规则

- [ ] **Step 1: 更新排序列**

`select_task_pareto_row` 使用：

```text
fast       scanTimeSec, negObservabilityScore, complexityCost, dfMHz
foEs       dfMHz, scanTimeSec, negIntegrationGainDb, heightResolutionKm
hEs        heightResolutionKm, negIntegrationGainDb, scanTimeSec, dfMHz
weakEs     negObservabilityScore, negIntegrationGainDb, scanTimeSec, complexityCost
full_trace nFreqDescending, dfMHz, resolutionCost, negObservabilityScore, scanTimeSec
balanced   scanTimeSec, resolutionCost, negObservabilityScore
```

- [ ] **Step 2: 确保 `add_task_sort_columns` 包含新列**

```matlab
S.negObservabilityScore = -S.observabilityScore;
S.negIntegrationGainDb = -S.integrationGainDb;
S.nFreqDescending = -S.nFreq;
```

`complexityCost` 应来自 candidate table。

## Task 9: 验证

- [ ] **Step 1: MATLAB 静态检查**

Run:

```powershell
matlab -batch "issues=checkcode('code/es_only_adaptive_sounding_system.m'); fprintf('checkcode=%d syntax=%d\n',numel(issues),sum(strcmp({issues.severity},'error')));"
```

Expected:

```text
syntax=0
```

- [ ] **Step 2: 全模式轻量仿真**

Run:

```powershell
matlab -batch "addpath('code'); modes={'fast','foEs','hEs','weakEs','full_trace','balanced'}; for k=1:numel(modes), out=es_only_adaptive_sounding_system(struct('quiet',true,'userPref',struct('taskMode',modes{k}),'fwdOpt',struct('nSubRays',5,'truthFreqListMHz',1.5:1.0:14.0),'optimizer',struct('populationSize',16,'maxGenerations',3))); tr=out.optimizerInfo.targetRegion.requiredRangeMHz; cfg=[out.optimized.cfg.fStartMHz,out.optimized.cfg.fEndMHz]; fprintf('%s target=[%.3f %.3f] cfg=[%.3f %.3f] fixedErr=%.3g df=%.3f scan=%.3f obs=%.3f gain=%.2f\n',modes{k},tr(1),tr(2),cfg(1),cfg(2),max(abs(tr-cfg)),out.optimized.cfg.dfMHz,out.optimizerInfo.bestMetrics.scanTimeSec,out.optimizerInfo.bestMetrics.observabilityScore,out.optimizerInfo.bestMetrics.integrationGainDb); end"
```

Expected:

```text
所有 fixedErr 为 0 或接近 0；
不同模式在同一搜索范围内得到不同偏好策略；
EsCoverage 不再作为目标函数驱动项。
```

## Task 10: 大批量测试脚本与统计输出

- [ ] **Step 1: 增加批量测试入口**

可在主函数运行选项中增加批量测试配置，或新增一个本地 MATLAB 辅助函数。测试入口需要支持：

```text
taskModes
scenarioSeeds
optimizerSeeds
lightForwardOptions
```

每次运行记录一行结果。

- [ ] **Step 2: 记录固定窗口校验字段**

每次测试必须记录：

```text
targetStartMHz
targetEndMHz
cfgStartMHz
cfgEndMHz
fixedErr
```

判据：

```text
fixedErr = max(abs([targetStartMHz,targetEndMHz] - [cfgStartMHz,cfgEndMHz]))
fixedErr 必须为 0 或接近浮点误差。
```

- [ ] **Step 3: 记录策略与指标字段**

每次测试必须记录：

```text
taskMode
optimizerSeed
scenarioSeed
dfMHz
PRP
chipLength
Ncoh
codeType
codeLength
nFreq
scanTimeSec
heightResolutionKm
integrationGainDb
observabilityScore
resolutionCost
complexityCost
feasible
optimizationFeasible
constraintViolation
nPareto
```

- [ ] **Step 4: 开发阶段测试规模**

Run:

```powershell
matlab -batch "addpath('code'); T=run_es_batch_validation(struct('stage','dev','outputPath','outputs/dev_batch_validation_summary.csv')); disp(T(:,{'taskMode','fixedErr','dfMHz','scanTimeSec','observabilityScore','integrationGainDb','optimizationFeasible'}));"
```

Expected:

```text
6 个模式全部运行完成；
fixedErr 全部为 0 或接近 0。
```

- [ ] **Step 5: 功能验证阶段测试规模**

建议运行：

```text
6 个模式 × 6 个场景 × 5 个优化seed = 180 次。
```

输出为表格文件，例如：

```text
outputs/batch_validation_summary.csv
```

统计：

```text
每个模式的 scanTimeSec、dfMHz、heightResolutionKm、integrationGainDb、observabilityScore 的均值和标准差；
每个模式的 optimizationFeasible 比例；
每个模式的 fixedErr 最大值。
```

- [ ] **Step 6: 论文/报告阶段测试规模**

建议运行：

```text
6 个模式 × 8~12 个场景 × 10~30 个优化seed
总运行数约 480~2160 次。
```

如果耗时过长：

```text
先用低正演精度做统计；
再选代表性样例做高精度复核。
```

- [ ] **Step 7: 消融测试**

建议比较：

```text
A. 规则种子 + 拉丁超立方采样 + 模式基线 + 模式目标；
B. 仅拉丁超立方采样 + 模式基线 + 模式目标；
C. 规则种子 + 拉丁超立方采样 + 无模式基线 + 模式目标；
D. 规则种子 + 拉丁超立方采样 + 模式基线 + 统一目标。
```

对比指标：

```text
可行解比例；
Pareto候选数量；
最终策略是否符合模式偏好；
不同模式指标分布是否能拉开差异。
```
