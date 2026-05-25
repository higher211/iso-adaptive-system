# Es任务驱动复探寻优主干设计

## 1. 系统定位

本系统不寻找适用于所有偶发E层（Es）探测任务的唯一最优策略，而是构建一个任务驱动的自适应复探策略寻优框架。

核心思想是：

```text
固定扫频范围；
统一工程可行域；
不同任务模式使用不同基线约束和目标偏好；
NSGA-II 在统一可行域内生成 Pareto 候选；
系统再按任务偏好选择最终推荐策略。
```

这样可以避免“不同模式靠改变搜索范围得到不同结果”的问题。不同模式的差异来自评价标准，而不是来自人为改动可行域。

## 2. 主流程

```text
初探电离图
↓
特征提取：foE_obs、foEs_obs、初扫df、SNR、连续性等
↓
IRI背景先验：foE_IRI
↓
按任务模式生成固定复探扫频范围
↓
冻结 fStartMHz / fEndMHz
↓
在统一可行域内生成初始种群
↓
NSGA-II 迭代生成候选策略
↓
按模式基线约束筛选可接受候选
↓
形成 Pareto 前沿
↓
按模式偏好选择最终策略
```

## 3. 固定扫频范围

扫频范围在 NSGA-II 前生成，不进入寻优过程。

```text
fStartMHz = target.requiredRangeMHz(1)
fEndMHz   = target.requiredRangeMHz(2)
```

NSGA-II 内部可以继续保留七维染色体接口：

```text
[fStartMHz, fEndMHz, dfMHz, PRP, chipLength, Ncoh, codeIndex]
```

但前两维必须被固定为目标窗口边界。交叉、变异、修复和最终候选生成都不能改变它们。

## 4. 统一搜索范围

所有模式共享同一个工程/物理可行域：

```text
dfMHz
PRP
chipLength
Ncoh
codeType / codeLength
```

不同任务模式不再覆盖：

```text
bounds.dfMHz
bounds.chipLength
codeTypeSet
NcohIntegerRange
```

这些参数范围由系统设备能力和物理工程约束统一给出。任务模式只改变评价方式，不改变可行域。

## 5. 规则种子与随机采样

NSGA-II 初始种群由两部分构成：

```text
1. 统一规则种子策略；
2. 统一可行域内的拉丁超立方采样。
```

规则种子不是最终答案，也不是人为指定的最优解。它们只是具有物理意义的搜索起点，用于覆盖典型策略区域：

```text
快速策略种子：较大df、较低Ncoh、简单码型；
频率精细种子：较小df、中等Ncoh；
高增益种子：较高Ncoh、互补码；
高度分辨率种子：较短chipLength；
综合折中种子：中等df、中等Ncoh、中等chipLength。
```

所有模式使用同一套规则种子和同一套随机采样机制。不同模式的结果不同，是因为它们后续使用不同基线约束、目标偏好和 Pareto 选择规则。

## 6. 覆盖率的角色

由于扫频范围已经固定，`EsCoverage` 不再作为优化目标。

在正确实现下，每个候选策略都应覆盖同一个固定窗口，因此：

```text
EsCoverage ≈ 1
```

它只保留为一致性检查：

```text
optimizedCfg.fStartMHz == target.requiredRangeMHz(1)
optimizedCfg.fEndMHz   == target.requiredRangeMHz(2)
```

如果覆盖率异常，说明固定窗口约束被破坏，而不是说明某个策略在目标函数上更优。

## 7. 模式基线约束

基线约束不是最优解，也不是改变搜索范围。它定义的是某个任务模式下“最低可接受策略”。

基线来源分三类：

```text
1. 物理/工程硬约束：
   高度不模糊、占空比、脉冲宽度、码型合法、Ncoh整数等。

2. 初扫相对基线：
   例如复探扫描时间应相对初扫明显降低。

3. 数据可用性基线：
   例如最低频点数、最低积累增益、最低可观测性。
```

基线通过 `constraintViolation` 进入 NSGA-II。违反基线的候选不会被直接删除，而是在约束支配排序中处于劣势。

## 8. 各模式评价逻辑

### 8.1 快速告警模式 fast

任务目标：

```text
尽快判断 Es 是否出现。
```

基线倾向：

```text
扫描时间应明显短于初扫；
频点数不能少到失去基本判断能力；
积累增益和可观测性达到最低可用水平。
```

目标偏好：

```text
min scanTimeSec
max observabilityScore
min complexityCost
```

### 8.2 foEs精读模式

任务目标：

```text
提高 Es 截止频率 foEs 的读取精度。
```

基线倾向：

```text
频点数足够支撑边界读取；
扫描时间不超过可接受上限；
边界回波积累增益达标。
```

目标偏好：

```text
min dfMHz
min scanTimeSec
max integrationGainDb
```

### 8.3 h'Es稳定读取模式

任务目标：

```text
稳定读取 Es 虚高 h'Es。
```

基线倾向：

```text
高度分辨率满足虚高读取要求；
PRP 对应不模糊高度满足探测高度；
扫描时间可接受。
```

目标偏好：

```text
min heightResolutionKm
max integrationGainDb
min scanTimeSec
```

### 8.4 弱Es增强模式

任务目标：

```text
弱回波场景下优先保证 Es 可观测。
```

基线倾向：

```text
积累增益和可观测性要求更高；
扫描时间可适当放宽。
```

目标偏好：

```text
max observabilityScore
max integrationGainDb
min scanTimeSec
```

### 8.5 完整形态观测模式 full_trace

任务目标：

```text
研究 Es 轨迹形态和频率结构。
```

基线倾向：

```text
固定窗口内频点数较多；
df 不能太粗；
积累增益达标。
```

目标偏好：

```text
min dfMHz
min resolutionCost
max observabilityScore
min scanTimeSec
```

### 8.6 综合平衡模式 balanced

任务目标：

```text
在扫描效率、分辨率和可观测性之间取得折中。
```

基线倾向：

```text
扫描时间、频率分辨率、高度分辨率和积累增益达到中等可用水平。
```

目标偏好：

```text
min scanTimeSec
min resolutionCost
max observabilityScore
```

## 9. 关键函数职责

### `make_es_task_profile`

只定义：

```text
objectiveMode
selectionMode
baseline
```

不再定义或覆盖：

```text
bounds
codeTypeSet
codeLengthSet
NcohIntegerRange
```

### `task_objective_vector`

根据任务模式生成目标向量。

不再使用 `EsCoverage`，只使用当前模式真正关心的指标：

```text
scanTimeSec
dfMHz
heightResolutionKm
integrationGainDb
observabilityScore
resolutionCost
complexityCost
```

### `es_strategy_cost`

负责把候选策略参数转换为评价指标：

```text
scanTimeSec
nFreq
heightResolutionKm
hAmbKm
dutyRatio
integrationGainDb
observabilityScore
resolutionCost
complexityCost
```

### `es_constraint_violation`

负责计算约束违反量：

```text
硬约束违反量
固定窗口一致性违反量
模式基线违反量
```

同时移除范围收缩类旧逻辑：

```text
maxAggressiveShrinkRatio
notOverShrunk
```

### `select_task_pareto_row`

从满足基线的 Pareto 候选中按模式偏好选择最终策略。

它不改变策略，只负责推荐：

```text
fast       → 更快且可观测性达标；
foEs       → df更小且边界增益达标；
hEs        → 高度分辨率更高；
weakEs     → 可观测性和积累增益更强；
full_trace → 频点更充分、分辨率更好；
balanced   → 扫描时间、分辨率和可观测性折中。
```

## 10. 最终结论

最终系统应表达为：

```text
统一搜索空间；
统一规则种子；
统一随机采样；
不同模式使用不同基线约束；
不同模式使用不同目标偏好；
不同模式使用不同 Pareto 推荐规则。
```

一句话概括：

```text
规则种子和搜索空间统一，任务基线和偏好分化；
NSGA-II 在统一可行域中生成候选，
不同模式用不同评价标准筛选 Pareto 策略。
```
