# Es寻优主干轻量重构设计

## 目标

本文档定义偶发E层自适应复探系统进入寻优阶段后的主干整理方案。前一阶段已经确定：复探扫频范围应当在寻优前生成并固定，不能再作为 NSGA-II 的优化变量。

因此，新的寻优阶段逻辑是：

```text
初探特征 + IRI背景先验 + 用户任务模式
↓
生成固定复探扫频范围
↓
冻结 fStartMHz / fEndMHz
↓
NSGA-II 只优化探测策略参数
↓
输出该任务模式下的 Pareto 折中策略
```

系统不再寻找一个适用于所有场景的唯一最优策略，而是在用户给定任务需求和固定物理工程约束下，给出对应模式的 Pareto 候选和推荐策略。

## 修改范围

本次采用“方案二：轻量重构寻优主干”。

修改范围保持在当前主 MATLAB 文件内：

- `code/es_only_adaptive_sounding_system.m`

本阶段不进行大规模拆文件。这样可以降低路径依赖和函数调用变化带来的风险，同时把当前论文/仿真需要的主干逻辑整理清楚。

## 寻优阶段固定输入

NSGA-II 进入前，系统已经得到以下固定上下文：

- `initialCfg`：初探策略配置，包括初扫扫频步进。
- `initialFeature`：由初探电离图提取出的 Es/E层特征。
- `pref.taskMode`：用户选择的任务模式。
- `target.requiredRangeMHz`：已经按任务模式生成的固定复探扫频范围。

其中：

```text
target.requiredRangeMHz(1) = 固定 fStartMHz
target.requiredRangeMHz(2) = 固定 fEndMHz
```

这两个值只作为寻优输入，不进入寻优搜索。

## 寻优变量

NSGA-II 只允许优化以下参数：

```text
dfMHz
PRP
chipLength
Ncoh
codeType / codeLength
```

为减少对现有代码结构的扰动，内部染色体可以继续保留七维形式：

```text
[fStartMHz, fEndMHz, dfMHz, PRP, chipLength, Ncoh, codeIndex]
```

但 `fStartMHz` 和 `fEndMHz` 的上下界必须被强制固定为 `target.requiredRangeMHz`，并且在初始化、交叉、变异、修复和最终候选生成中都不能发生实际变化。

换句话说，七维染色体只是保留现有接口形式，真实可变维度只有五类策略参数。

## 候选策略评价指标

每个候选策略需要计算以下指标：

```text
scanTimeSec
nFreq
heightResolutionKm
hAmbKm
dutyRatio
integrationGainDb
EsCoverage
observabilityScore
resolutionCost
```

这些指标同时服务于三件事：

```text
1. 构造不同任务模式下的多目标向量；
2. 判断候选策略是否满足工程/物理约束；
3. 在 Pareto 候选中选择最终推荐策略。
```

## 约束条件

寻优阶段应检查以下约束：

```text
1. 固定目标扫频窗口必须被完整覆盖；
2. 总扫描时间不能超过系统硬上限；
3. 扫描时间应满足任务模式的自适应复探上限；
4. 频点数不能低于任务模式要求；
5. EsCoverage 不能低于任务模式要求；
6. 积累增益不能低于任务模式要求；
7. PRP 对应的不模糊高度必须满足最大探测高度要求；
8. 占空比不能超过工程上限；
9. 编码脉冲宽度加保护时间必须小于 PRP；
10. 码型与码长必须匹配；
11. Ncoh 必须是合法整数搜索值。
```

由于扫频窗口已经固定，和“压缩扫频范围”相关的约束应当删除或失效。例如 `maxAggressiveShrinkRatio` 只在 `fStartMHz/fEndMHz` 参与寻优时有意义；现在窗口不可收缩，它不应该再影响候选策略可行性。

## 不同任务模式的目标函数

不同模式使用不同的多目标向量。

### 快速告警模式

目标：

```text
min scanTimeSec
max EsCoverage
max observabilityScore
```

含义：尽快判断 Es 是否出现，允许分辨率适当降低，但不能失去基本覆盖和可观测性。

### foEs精读模式

目标：

```text
min dfMHz
min scanTimeSec
max integrationGainDb
```

含义：围绕初探 foEs 边界进行窄扫，重点提高频率分辨率，同时保证边界回波有足够积累增益。

### h'Es稳定读取模式

目标：

```text
min heightResolutionKm
min scanTimeSec
max integrationGainDb
```

含义：重点提高虚高读取稳定性，优先选择更短 chipLength 和足够的相干积累。

### 弱Es增强模式

目标：

```text
max observabilityScore
max integrationGainDb
min scanTimeSec
```

含义：Es 较弱时，优先保证“看得见”，允许扫描时间相对放宽。

### 完整形态观测模式

目标：

```text
max EsCoverage
min resolutionCost
min scanTimeSec
max observabilityScore
```

含义：面向 Es 完整轨迹形态研究，强调窗口覆盖、轨迹连续性、分辨率和可观测性的综合表现。

### 综合平衡模式

目标：

```text
min scanTimeSec
min resolutionCost
max observabilityScore
```

含义：在扫描效率、分辨率和 Es 可观测性之间寻找折中点。

## Pareto候选与最终推荐

NSGA-II 负责产生受约束的 Pareto 候选集合。最终推荐策略不通过人为给所有指标强行加权得到，而是按任务模式进行排序选择：

```text
fast       → 优先扫描时间，再看覆盖率和可观测性
foEs       → 优先 df，再看扫描时间和积累增益
hEs        → 优先高度分辨率，再看积累增益和扫描时间
weakEs     → 优先可观测性和积累增益
full_trace → 优先覆盖率、频点数和综合分辨率
balanced   → 在低扫描时间候选中选择覆盖、分辨率和可观测性较平衡的点
```

这样可以避免把所有模式都压成同一个“全局最优”问题，而是保留“任务需求驱动”的系统定位。

## 需要清理的代码点

本次实现重点检查和清理以下位置：

```text
1. nsga2_bounds
   明确固定 fStartMHz/fEndMHz 的上下界。

2. repair_nsga2_x
   确保修复逻辑不会为了最小频宽等旧规则改动固定窗口。

3. initialize_nsga2_population
   种群初始化中所有 seed 都必须使用固定 target 范围。

4. mutate_nsga2_x / crossover_mutate_nsga2
   即使交叉变异触碰到前两维，修复后也必须回到固定窗口。

5. es_constraint_violation 与 es_strategy_cost
   删除或失效只服务于“扫频范围收缩寻优”的约束。

6. select_strategy_from_pareto_candidates
   保留按任务模式选择 Pareto 推荐策略的逻辑，并确保不改变扫频范围。

7. build_es_optimizer_reason_table
   输出解释应改为“固定任务扫频窗口 + 策略参数寻优”。
```

## 验证要求

实现完成后，需要进行以下验证：

```text
1. MATLAB 静态/语法检查；
2. 分别运行全部任务模式：
   fast
   foEs
   hEs
   weakEs
   full_trace
   balanced
```

每个模式都需要确认：

```text
1. target.requiredRangeMHz 在 NSGA-II 前已经生成；
2. optimizedCfg.fStartMHz == target.requiredRangeMHz(1)；
3. optimizedCfg.fEndMHz   == target.requiredRangeMHz(2)；
4. NSGA-II 实际只改变 dfMHz、PRP、chipLength、Ncoh 和码型；
5. 最终策略满足主要约束；
6. 如果某模式无法完全满足约束，需要输出具体未满足的约束项。
```

## 不在本次范围内的内容

本次不处理以下内容：

```text
1. 不重新设计已经确认的扫频范围生成规则；
2. 不加入 blanketing Es 逻辑；
3. 不把主 MATLAB 文件拆成多个文件；
4. 不修改 IRI 背景先验获取方式；
5. 不修改初探电离图特征提取流程，除非发现它直接破坏寻优输入。
```

## 最终预期效果

完成后，系统主干应表达为：

```text
特征提取与IRI背景先验
↓
按任务模式生成固定复探扫频范围
↓
进入 NSGA-II 参数寻优
↓
生成 Pareto 候选
↓
按任务偏好选择推荐策略
↓
输出策略参数、约束状态和推荐理由
```

这使系统定位更加清晰：

```text
不是寻找唯一绝对最优的 Es 探测策略，
而是在用户任务需求和固定工程约束下，
寻找对应模式的 Pareto 折中复探策略。
```
