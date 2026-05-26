# Es自适应复探策略寻优系统技术与实验分析报告

## 1. 报告目的

本文档用于系统性说明当前 Es 自适应复探策略寻优系统的整体结构、核心原理、关键算法、实验设计以及仿真结果。该系统的定位不是寻找一个适用于所有场景的唯一最优探测策略，而是面向不同 Es 探测任务需求，在固定物理与工程约束下，生成对应任务偏好的 Pareto 折中复探策略。

当前系统已经完成以下工作：

- 构建了 Es 层初探、特征提取、IRI 背景先验、复探窗口生成、NSGA-II 策略寻优和结果评价的完整流程。
- 将扫频范围从优化变量中移除，改为由任务模式、IRI 先验和初扫特征固定生成。
- 设计了 fast、foEs、hEs、weakEs、full_trace 和 balanced 六类任务模式。
- 完成了 1800 条主实验、7200 条固定经验策略对比实验和 9000 条消融实验。
- 生成了 7 张论文级统计图。

该系统更适合表述为：

```text
面向不同偶发E层探测任务需求的自适应复探策略寻优框架。
```

而不应表述为：

```text
寻找唯一绝对最优的Es探测策略。
```

这是因为不同科研任务对探测策略的需求不同。例如快速告警更重视扫描时间，foEs 精读更重视频率分辨率，h'Es 读取更重视高度分辨率，弱 Es 探测更重视积累增益和可观测性。因此系统需要根据任务目标生成不同的策略，而不是强行给出一个全局唯一解。

## 2. 项目文件结构

当前项目主目录为：

```text
final_deliverable_es_adaptive_sounding/
```

主要分为四类目录：

```text
code/
docs/
outputs/
outputs/final_full_run/
```

### 2.1 code 目录

`code` 目录保存系统主代码和实验入口。

```text
code/es_only_adaptive_sounding_system.m
```

这是系统主文件，包含 Es 场景构造、初扫仿真、特征提取、IRI 背景先验接入、任务模式解析、固定扫频范围生成、NSGA-II 优化、Pareto 策略选择和结果评价等核心功能。

```text
code/iri2020_profile.py
```

这是 IRI 背景模型辅助脚本。系统通过它获取背景电离层 E 层先验。如果 Python IRI 调用失败，主系统中还提供 Chapman 背景模型作为 fallback。

```text
code/run_es_batch_validation.m
```

这是批量验证脚本。它按照 Es 强度、任务模式、场景随机种子和优化器随机种子批量调用主系统，并将每次运行结果整理成表格。

```text
code/run_es_final_report_batch_test.m
```

这是论文主实验入口。完整 final 实验规模为：

```text
3种Es强度 × 6种任务模式 × 10个场景种子 × 10个优化器种子 = 1800条
```

```text
code/run_es_sci_supplement_experiments.m
```

这是 SCI 补充实验入口。它负责：

- 生成或读取 full_system 完整系统结果。
- 生成固定经验策略 baseline 对比结果。
- 执行 ablation 消融实验。
- 生成统计图。
- 保存最终 MAT 汇总文件。

### 2.2 docs 目录

`docs` 目录保存技术路线和系统分析文档。

当前已经存在：

```text
docs/es_task_driven_optimization_technical_route.md
docs/es_system_technical_analysis_report.md
docs/es_adaptive_sounding_final_technical_report.md
```

其中本文档是当前系统最新的完整技术和结果分析报告。

### 2.3 outputs 目录

`outputs` 目录保存小规模测试、功能验证和 smoke 实验结果。

典型文件包括：

```text
outputs/dev_batch_validation_summary.csv
outputs/functional_batch_validation_summary.csv
outputs/smoke_final_report_batch_validation_summary.csv
outputs/sci_supplement_smoke/
outputs/figures_smoke/
```

这些结果主要用于快速检查代码是否能正常运行。

### 2.4 outputs/final_full_run 目录

这是最终完整规模实验目录，也是论文结果最重要的目录。

主要文件包括：

```text
outputs/final_full_run/final_report_batch_validation_summary.csv
outputs/final_full_run/final_report_batch_validation_summary.mat
```

这是 1800 条主实验结果。

```text
outputs/final_full_run/sci_supplement_final/full_system_for_supplement.csv
outputs/final_full_run/sci_supplement_final/baseline_comparison_summary.csv
outputs/final_full_run/sci_supplement_final/ablation_study_summary.csv
outputs/final_full_run/sci_supplement_final/sci_supplement_results.mat
```

这是 SCI 补充实验结果。

```text
outputs/final_full_run/figures_final/
```

其中保存 7 张统计图：

```text
mode_scan_time.png
mode_df.png
mode_height_resolution.png
mode_gain.png
feasible_rate_heatmap.png
baseline_scan_time.png
ablation_feasible_rate.png
```

## 3. 系统总体流程

系统主流程如下：

```text
Es场景生成
    ↓
初扫探测仿真
    ↓
电离图预处理
    ↓
E层与Es层特征提取
    ↓
接入IRI背景先验
    ↓
根据任务模式生成固定复探扫频范围
    ↓
NSGA-II在固定范围内优化策略参数
    ↓
生成Pareto候选策略
    ↓
按任务偏好选择最终推荐策略
    ↓
输出策略、指标、对比结果和解释
```

系统中最重要的分工是：

```text
扫哪里：由 IRI 先验、初扫特征和任务模式决定。
怎么扫：由 NSGA-II 在固定范围内优化策略参数决定。
选哪个：由任务偏好和基线约束从 Pareto 前沿中选择。
```

也就是说，当前系统已经将“复探范围选择”和“探测策略参数优化”分离开来。复探范围不再作为优化变量，而是作为任务约束固定传入优化器。

## 4. Es场景与初探仿真原理

系统首先构造一个包含背景电离层和 Es 层扰动的仿真场景。Es 层不是简单的一条固定线，而是具有空间结构、临界频率变化、斑块扰动和噪声影响的二维或准二维场景。

场景主要由以下因素决定：

- 背景 E 层电子密度分布。
- Es 层电子密度增强。
- Es 层空间斑块结构。
- Es 层反射高度。
- 反射频率范围。
- 噪声水平。
- 子回波路径和随机扰动。

系统使用随机种子控制场景复现性。

```text
scenarioSeed
```

主要控制 Es 场景、空间斑块、噪声和子回波路径等随机因素。

```text
optimizerSeed
```

主要控制 NSGA-II 优化过程中的随机性，包括初始随机种群、交叉、变异和选择过程。

初扫阶段使用一个较粗的探测策略进行电离图采样。初扫的作用不是得到最终最优结果，而是从当前场景中提取可用于复探决策的观测特征。

## 5. 特征提取与IRI背景先验

初扫仿真生成电离图后，系统对电离图进行预处理和特征提取。

提取的关键特征包括：

```text
foE_obs
foEs_obs
Es虚高
Es轨迹连续性
SNR
Es覆盖情况
```

其中：

```text
foE_obs
```

表示初扫电离图中观测到的正常 E 层临界频率。

```text
foEs_obs
```

表示初扫电离图中观测到的 Es 层临界频率。

```text
foE_IRI
```

表示 IRI 背景模型给出的正常 E 层临界频率先验。

三者含义不同：

- `foE_IRI` 是物理经验模型先验。
- `foE_obs` 是当前初扫观测到的正常 E 层频率。
- `foEs_obs` 是当前初扫观测到的 Es 层频率。

系统不假设三者大小顺序。真实情况下可能出现：

```text
foE_IRI < foE_obs < foEs_obs
foE_obs < foE_IRI < foEs_obs
foEs_obs < foE_obs < foE_IRI
foE_IRI < foEs_obs < foE_obs
```

因此系统采用“先比较，再扩展”的规则，而不是预设固定顺序。

## 6. 固定扫频范围生成原理

这是当前系统最关键的修改之一。

系统不再让 NSGA-II 优化 `fStart` 和 `fEnd`。扫频范围由任务模式和初扫特征固定生成。

### 6.1 总体原则

系统先收集可用频率点：

```text
foE_IRI
foE_obs
foEs_obs
```

然后进行大小比较：

```text
f_min = min(可靠频率点)
f_max = max(可靠频率点)
```

随后按来源类型进行扩展：

```text
IRI来源频率：使用人工定义 margin 扩展
初扫观测频率：使用初扫扫频步进 df_coarse 扩展
```

也就是说：

```text
IRI 不使用 df_coarse 扩展。
观测频率不使用 margin 扩展。
```

这样可以保证扩展逻辑清楚，不会出现既加 0.2 又加 0.3 的混乱情况。

### 6.2 IRI频率扩展

如果边界频率来自 IRI：

```text
foE_IRI
```

则扩展量为：

```text
margin
```

这是因为 IRI 是模型先验，不是初扫观测点，其误差来源主要是模型不确定性。

### 6.3 初扫观测频率扩展

如果边界频率来自初扫观测：

```text
foE_obs
foEs_obs
```

则扩展量为：

```text
df_coarse
```

这是因为观测频率的读取精度受初扫扫频步进限制。

### 6.4 不同模式的扫频范围

不同任务模式会生成不同固定范围。

例如：

```text
fast
```

更偏向快速判断 Es 是否出现，因此窗口可以更紧凑。

```text
foEs
```

关注 Es 截止频率，因此更倾向围绕 `foEs_obs` 附近构造窄扫窗口。

```text
hEs
```

关注 Es 虚高稳定读取，因此窗口要覆盖 Es 主要反射区，同时重点优化高度分辨率。

```text
weakEs
```

关注弱回波增强，因此窗口通常需要保证 Es 可能出现区域的覆盖，并给优化器留出提高积累增益的空间。

```text
full_trace
```

关注完整 Es 形态，因此窗口更完整，覆盖正常 E 层到 Es 层可能范围。

```text
balanced
```

采用折中范围，不极端偏向某一指标。

无论哪种模式，最终生成的扫频范围都会被固定：

```text
cfg.fStartMHz = target.requiredRangeMHz(1)
cfg.fEndMHz   = target.requiredRangeMHz(2)
```

NSGA-II 后续不能修改这两个值。

## 7. 六种任务模式设计

系统支持六种任务模式。

### 7.1 fast模式

目标：

```text
快速判断 Es 是否出现。
```

主要偏好：

- 扫描时间短。
- 允许频率分辨率较粗。
- 保持基本可观测性。
- 控制复杂度。

典型策略倾向：

- 较大 `df`。
- 较低或中等 `Ncoh`。
- Barker 码优先。
- 较短扫描时间。

### 7.2 foEs模式

目标：

```text
精确读取 Es 截止频率 foEs。
```

主要偏好：

- 频率分辨率高。
- `df` 尽可能小。
- 扫描时间不能过长。
- 重点围绕 Es 截止频率附近复探。

典型策略倾向：

- 小 `df`。
- 频点数较多。
- 扫描时间高于 fast，但明显低于传统宽扫。

### 7.3 hEs模式

目标：

```text
稳定读取 Es 虚高 h'Es。
```

主要偏好：

- 高度分辨率高。
- 较短 `chipLength`。
- 中等或较高积累增益。
- 扫描时间适中。

典型策略倾向：

- 较小 `chipLength`。
- 较好的高度分辨率。
- 增益和扫描时间折中。

### 7.4 weakEs模式

目标：

```text
增强弱 Es 回波可观测性。
```

主要偏好：

- 高 `Ncoh`。
- 高积累增益。
- 高可观测性。
- 可接受更长扫描时间。

典型策略倾向：

- 较高 `Ncoh`。
- 可能选择互补码。
- 扫描时间较长。
- 积累增益最高。

### 7.5 full_trace模式

目标：

```text
观测 Es 完整形态。
```

主要偏好：

- 更多频点。
- 更连续的轨迹。
- 较好的频率分辨率。
- 允许扫描时间增加。

典型策略倾向：

- 频点数最多。
- 扫描时间较长。
- df 较小。

### 7.6 balanced模式

目标：

```text
在扫描时间、分辨率、增益和复杂度之间折中。
```

主要偏好：

- 不极端追求某一指标。
- 给出综合平衡策略。

典型策略倾向：

- 扫描时间低于大多数精细模式。
- 分辨率优于 fast。
- 增益和复杂度适中。

## 8. NSGA-II寻优机制

系统使用 NSGA-II 进行多目标优化，但优化变量已经不包括扫频范围。

### 8.1 优化变量

当前优化变量包括：

```text
df
PRP
chipLength
Ncoh
codeType
```

其中：

- `df` 决定频率分辨率和频点数。
- `PRP` 决定脉冲重复周期，与高度模糊和扫描时间有关。
- `chipLength` 决定高度分辨率。
- `Ncoh` 决定相干积累增益和扫描时间。
- `codeType` 决定编码增益和复杂度。

### 8.2 不同模式不修改统一参数范围

当前设计中，不同模式不会修改全局参数 bounds。

这点非常重要。

也就是说：

```text
fast、foEs、hEs、weakEs、full_trace、balanced
```

都在同一个统一可行参数范围内搜索。

不同模式的差异来自：

- 目标函数不同。
- 基线约束不同。
- Pareto 最终选择规则不同。

不是靠人为给每个模式设置不同参数范围。

### 8.3 规则种子策略

NSGA-II 初始种群中包含规则种子策略。

规则种子不是最终答案，也不是拍脑袋指定结果。它的作用是：

```text
给优化器提供一组物理上合理、工程上可用的初始参考点。
```

随后 NSGA-II 通过交叉、变异和选择生成新策略。

因此规则种子更像是：

```text
搜索起点和方向引导。
```

而不是：

```text
直接规定最终策略。
```

### 8.4 目标函数

系统在 `task_objective_vector` 中根据不同任务模式构造目标。

例如：

```text
fast
```

主要优化：

- 最小扫描时间。
- 最大可观测性。
- 最小复杂度。

```text
foEs
```

主要优化：

- 最小 `df`。
- 控制扫描时间。
- 保持基本增益。

```text
hEs
```

主要优化：

- 最小高度分辨率。
- 保持增益。
- 控制扫描时间。

```text
weakEs
```

主要优化：

- 最大积累增益。
- 最大可观测性。
- 在扫描时间约束下搜索。

当前系统已经移除了 `EsCoverage` 作为优化目标。这是合理的，因为扫频范围固定后覆盖率不再由优化器决定，不应该重复进入评价。

### 8.5 约束违背

系统通过 `es_constraint_violation` 计算策略是否违反约束。

约束包括：

- 物理工程约束。
- PRP 高度不模糊约束。
- 占空比约束。
- 频点数约束。
- 任务基线约束。

任务基线不是人为指定一个最终答案，而是定义：

```text
什么策略在该任务下是可接受的。
```

例如 fast 模式要求扫描时间不能太慢，weakEs 模式要求增益不能太低，hEs 模式要求高度分辨率不能太差。

### 8.6 Pareto选择

NSGA-II 输出的是一组 Pareto 候选策略。

系统不会简单取某个单指标最优点，而是根据任务偏好从 Pareto 前沿中选择最终策略。

这与系统定位一致：

```text
不是全局唯一最优，而是任务约束下的折中最优。
```

## 9. 实验设计

当前完整实验包含三部分。

### 9.1 主实验

主实验规模：

```text
3种Es强度 × 6种任务模式 × 10个场景种子 × 10个优化器种子 = 1800条
```

三种 Es 强度为：

```text
weak
moderate
strong
```

六种任务模式为：

```text
fast
foEs
hEs
weakEs
full_trace
balanced
```

主实验主要验证：

- 系统整体可行率。
- 固定扫频范围是否被保持。
- 不同模式是否产生不同策略倾向。
- 不同 Es 强度下系统是否稳定。

### 9.2 固定策略对比实验

固定策略对比规模：

```text
7200条
```

对比方法包括：

```text
NSGA-II task-driven
Fixed medium
Traditional wide scan
Manual task heuristic
```

该实验用于回答：

```text
任务驱动 NSGA-II 策略是否优于固定经验策略？
```

### 9.3 消融实验

消融实验规模：

```text
5个变体 × 1800条 = 9000条
```

五个变体为：

```text
full_system
no_baseline
no_rule_seed
no_iri_prior
unified_objective
```

含义如下：

- `full_system`：完整系统。
- `no_baseline`：去掉任务基线约束。
- `no_rule_seed`：去掉规则种子策略。
- `no_iri_prior`：去掉 IRI 背景先验。
- `unified_objective`：不区分任务模式，使用统一目标。

该实验用于分析各模块对系统结果的影响。

## 10. 主实验结果分析

主实验总体结果：

```text
样本数：1800
fixedErr_max：0
总体可行率：99.17%
平均约束违背：0.0294
```

其中 `fixedErr_max=0` 是非常关键的结果。它说明所有实验中：

```text
优化后的 fStart/fEnd 完全等于任务生成的固定扫频范围。
```

这证明扫频范围没有进入 NSGA-II 寻优过程。

### 10.1 分模式结果

各模式平均结果如下：

```text
fast:
    scanTime = 0.274 s
    df = 0.3379 MHz
    heightResolution = 2.8689 km
    gain = 18.9209 dB
    feasibleRate = 100%

foEs:
    scanTime = 1.239 s
    df = 0.0207 MHz
    heightResolution = 1.8567 km
    gain = 19.3927 dB
    feasibleRate = 100%

hEs:
    scanTime = 1.937 s
    df = 0.1607 MHz
    heightResolution = 1.2004 km
    gain = 23.2063 dB
    feasibleRate = 100%

weakEs:
    scanTime = 3.898 s
    df = 0.1559 MHz
    heightResolution = 2.0986 km
    gain = 26.4450 dB
    feasibleRate = 95%

full_trace:
    scanTime = 3.849 s
    df = 0.0666 MHz
    heightResolution = 1.4635 km
    gain = 22.5378 dB
    feasibleRate = 100%

balanced:
    scanTime = 0.907 s
    df = 0.1821 MHz
    heightResolution = 1.5472 km
    gain = 21.2024 dB
    feasibleRate = 100%
```

这些结果说明不同任务模式确实形成了不同策略倾向。

### 10.2 fast模式评价

fast 模式扫描时间最短：

```text
0.274 s
```

但它的 `df` 较大：

```text
0.3379 MHz
```

这说明 fast 模式确实牺牲频率分辨率来换取扫描速度。这个结果符合快速告警任务需求。

### 10.3 foEs模式评价

foEs 模式的 `df` 最小：

```text
0.0207 MHz
```

说明它最适合精确读取 Es 截止频率。

它的扫描时间为：

```text
1.239 s
```

虽然比 fast 慢，但相比传统宽扫仍明显更快。

### 10.4 hEs模式评价

hEs 模式高度分辨率最好：

```text
1.2004 km
```

说明该模式确实倾向于选择更短 chipLength 或更利于高度读取的参数组合。

### 10.5 weakEs模式评价

weakEs 模式增益最高：

```text
26.4450 dB
```

说明它成功朝着弱回波增强目标优化。

但它的可行率为：

```text
95%
```

低于其他模式。进一步看，主要问题出现在 strong 强度下的 weakEs：

```text
strong + weakEs 可行率 = 85%
```

这说明 weakEs 模式基线约束较强，在某些强 Es 场景下，与扫描时间、复杂度或参数边界发生冲突。

这个结果不一定是系统缺陷，也可以解释为：

```text
高增益弱回波增强任务对约束更敏感。
```

### 10.6 full_trace模式评价

full_trace 模式频点数最多：

```text
nFreq = 34.77
```

说明它更适合完整 Es 轨迹观测。

### 10.7 balanced模式评价

balanced 模式扫描时间为：

```text
0.907 s
```

整体指标处于折中位置，符合综合平衡任务定位。

## 11. 固定策略对比结果分析

固定策略对比中，传统宽扫策略平均扫描时间为：

```text
6.528 s
```

任务驱动 NSGA-II 策略相比传统宽扫具有明显扫描时间优势。

### 11.1 相比传统宽扫

NSGA-II 相比传统宽扫的扫描时间降低比例：

```text
fast:       95.8%
foEs:       81.0%
hEs:        70.3%
weakEs:     40.3%
full_trace: 41.0%
balanced:   86.1%
```

这说明系统不是盲目全窗口复探，而是根据任务目标选择更合适的策略。

### 11.2 foEs模式优势

foEs 模式相比传统宽扫：

```text
df 从 0.250 MHz 降到 0.0207 MHz
扫描时间从 6.528 s 降到 1.239 s
```

这同时提高了频率分辨率并降低了扫描时间，是非常有说服力的结果。

### 11.3 weakEs模式优势

weakEs 模式相比传统宽扫：

```text
积分增益提高约 3.26 dB
扫描时间降低约 40.3%
```

说明系统能够在弱 Es 增强任务下提高可观测性，同时避免传统宽扫的长时间成本。

### 11.4 hEs模式优势

hEs 模式相比传统宽扫：

```text
高度分辨率从约 2.998 km 改善到约 1.200 km
扫描时间降低约 70.3%
```

说明 hEs 模式在虚高读取方面具有明确优势。

### 11.5 与固定medium策略对比

固定 medium 策略较稳定，但缺乏任务适配能力。

例如：

- fast 模式中，NSGA-II 扫描时间降低约 90.7%。
- foEs 模式中，NSGA-II 显著降低 df。
- weakEs 模式中，NSGA-II 增益提高约 3.26 dB。
- hEs 模式中，NSGA-II 高度分辨率显著改善。

因此固定 medium 可以作为稳定基线，但不能替代任务驱动优化。

### 11.6 与人工启发式策略对比

人工启发式策略在部分模式下表现接近，例如 hEs。但它的缺点是扫描时间和复杂度不稳定。

例如 weakEs：

```text
人工启发式扫描时间：8.706 s
NSGA-II扫描时间：3.898 s
```

NSGA-II 扫描时间降低约：

```text
55.2%
```

说明人工经验策略可以在单一目标上表现较好，但缺少多目标折中能力。

## 12. 消融实验结果分析

消融实验共 9000 条。

总体结果：

```text
fixedErr_max = 0
```

说明所有消融变体中，扫频范围仍然保持固定。

各变体平均结果如下：

```text
full_system:
    scanTime = 2.017 s
    df = 0.1540 MHz
    gain = 21.9508 dB
    observability = 0.7702
    feasibleRate = 99.17%

no_baseline:
    scanTime = 1.946 s
    df = 0.1523 MHz
    gain = 21.4303 dB
    observability = 0.7328
    feasibleRate = 100%

no_rule_seed:
    scanTime = 2.047 s
    df = 0.1582 MHz
    gain = 22.3111 dB
    observability = 0.7936
    feasibleRate = 99.50%

no_iri_prior:
    scanTime = 1.413 s
    df = 0.0708 MHz
    gain = 23.2477 dB
    observability = 0.8629
    feasibleRate = 100%

unified_objective:
    scanTime = 1.123 s
    df = 0.1704 MHz
    gain = 21.1604 dB
    observability = 0.7138
    feasibleRate = 99.61%
```

### 12.1 full_system

完整系统不是每个单项指标最优，但它是任务约束下的折中结果。

完整系统保留：

- IRI 先验。
- 任务基线。
- 规则种子。
- 分任务目标函数。

因此它更强调物理完整性、任务一致性和搜索稳定性，而不是某一个指标的极端最优。

### 12.2 no_baseline

去掉任务基线后：

```text
可行率从 99.17% 到 100%
可观测性从 0.7702 降到 0.7328
```

这说明任务基线确实增加了筛选压力，但也提高了策略质量要求。

如果没有任务基线，优化器更容易找到数学上可行的解，但这些解不一定满足任务需求。

### 12.3 no_rule_seed

去掉规则种子后：

```text
平均约束违背从 0.0294 升到 0.0561
最大约束违背达到 1.4838
```

这说明规则种子能提高搜索稳定性，使初始种群更容易落在物理和工程上合理的区域。

规则种子不是直接决定最终答案，而是给 NSGA-II 提供较好的搜索起点。

### 12.4 no_iri_prior

去掉 IRI 先验后，表面指标更好：

```text
scanTime 更短
df 更小
gain 更高
constraintViolation = 0
```

但这不能简单解释为 IRI 先验无用。

更合理的解释是：

```text
去掉 IRI 后，目标范围可能变窄，优化问题更容易。
```

IRI 的价值主要在于提高物理保守性，保证下一次复探范围覆盖正常 E 层至 Es 层的可能区域。

因此论文中不能写：

```text
去掉 IRI 更好。
```

而应该写：

```text
去除 IRI 先验会使部分数值指标变好，但可能降低对背景 E 层不确定性的物理覆盖能力。
```

### 12.5 unified_objective

统一目标函数后：

```text
scanTime = 1.123 s
observability = 0.7138
```

扫描时间很短，但可观测性较低。

这说明统一目标容易偏向某些平均指标，削弱任务差异。

因此分任务目标函数是合理的。

## 13. 统计图说明

最终生成 7 张图。

### 13.1 mode_scan_time.png

展示不同任务模式的平均扫描时间。

应重点说明：

- fast 最快。
- weakEs 和 full_trace 最慢。
- balanced 居中。

### 13.2 mode_df.png

展示不同任务模式的频率步进。

应重点说明：

- foEs 的 df 最小。
- fast 的 df 最大。
- full_trace 的 df 较小。

### 13.3 mode_height_resolution.png

展示不同模式的高度分辨率。

应重点说明：

- hEs 高度分辨率最好。
- fast 高度分辨率较弱。

### 13.4 mode_gain.png

展示不同模式的积累增益。

应重点说明：

- weakEs 增益最高。
- fast 增益最低。

### 13.5 feasible_rate_heatmap.png

展示不同 Es 强度和任务模式下的可行率。

应重点说明：

- 大部分组合可行率为 100%。
- strong + weakEs 可行率下降到 85%。

### 13.6 baseline_scan_time.png

展示不同策略方法的扫描时间对比。

应重点说明：

- 传统宽扫时间最长。
- 任务驱动 NSGA-II 在多数模式下明显缩短扫描时间。

### 13.7 ablation_feasible_rate.png

展示不同消融变体的可行率。

应重点说明：

- 大部分变体可行率接近或达到 100%。
- 可行率不是唯一评价指标，还应结合可观测性、物理覆盖和任务一致性。

## 14. 系统优点

当前系统的主要优点包括：

### 14.1 定位合理

系统不再声称寻找唯一最优策略，而是根据任务需求生成 Pareto 折中策略。

这避免了多目标优化中“权重人为”和“唯一最优不可证明”的问题。

### 14.2 固定扫频范围逻辑清楚

系统明确区分：

```text
扫频范围生成
策略参数优化
```

扫频范围由 IRI 和初扫特征生成，不进入优化器。

实验中：

```text
fixedErr_max = 0
```

证明该机制有效。

### 14.3 任务模式差异明显

不同模式产生了符合物理直觉和任务需求的策略：

- fast 快。
- foEs 细。
- hEs 高度分辨率好。
- weakEs 增益高。
- full_trace 频点多。
- balanced 折中。

### 14.4 实验规模充分

完整实验包括：

```text
1800 主实验
7200 baseline
9000 ablation
```

这个规模已经可以支撑论文中的统计分析。

### 14.5 对比实验有说服力

相比传统宽扫，任务驱动策略在多数模式下显著缩短扫描时间，并在特定模式中改善关键指标。

## 15. 当前不足

### 15.1 仍以仿真为主

当前结果主要来自仿真系统。如果要冲更高水平 SCI，最好补充真实或半真实电离图验证。

### 15.2 no_iri_prior结果需要谨慎解释

消融中 no_iri_prior 表面指标更好，容易被审稿人质疑 IRI 模块必要性。

需要在论文中强调：

```text
IRI先验的价值不只是提高优化指标，而是保证物理覆盖的保守性。
```

### 15.3 weakEs在strong条件下可行率下降

strong + weakEs 可行率为 85%，需要解释为高增益弱回波增强任务对约束更敏感。

也可以在后续增加更柔性的 weakEs 基线或自适应基线。

### 15.4 主代码仍偏大

主文件功能完整，但代码集中在一个文件中，后续如果交付或开源，建议拆分为：

```text
scene/
simulation/
feature_extraction/
target_region/
optimization/
evaluation/
experiments/
```

### 15.5 长时实验需要更完善进度日志

虽然已经修复了 ablation 中途停止不落盘的问题，但后续最好加入逐 case 进度日志。

## 16. SCI论文投稿评价

从 SCI 审稿角度看，当前系统有较明确的应用价值和工程完整性。

适合的论文定位是：

```text
A Task-Driven Adaptive Re-Sounding Strategy Optimization Framework for Sporadic E-Layer Ionosonde Observations
```

不建议定位为：

```text
An Optimal Es Detection Strategy
```

因为后者容易被质疑最优性不可证明。

当前结果更适合支撑：

```text
任务需求驱动的自适应策略推荐框架。
```

### 16.1 当前可投稿层级

如果只基于当前仿真系统：

```text
SCI三区较稳妥。
```

如果补充真实或半真实电离图验证，并加强物理解释：

```text
可以尝试二区。
```

一区目前不建议作为目标，除非补充真实观测数据、仪器系统验证和更强原创物理发现。

### 16.2 适合方向

适合方向包括：

```text
电离层探测
空间天气监测
无线电传播
自适应探测策略
多目标优化在地球空间环境观测中的应用
```

可考虑期刊类型：

```text
Journal of Atmospheric and Solar-Terrestrial Physics
Radio Science
Advances in Space Research
Earth and Space Science
Sensors
Acta Geophysica
```

## 17. 推荐论文表达

建议论文核心表述为：

```text
本文提出一种面向偶发 E 层探测任务需求的自适应复探策略寻优框架。
该框架利用 IRI 背景先验和初扫电离图特征确定固定复探扫频范围，
并根据用户设定的扫描时效、频率分辨率、虚高分辨率和弱回波可观测性偏好，
在统一物理和工程约束范围内搜索 Pareto 折中探测策略。
```

实验结论可表述为：

```text
在 1800 组完整仿真实验中，系统固定扫频范围误差为 0，总体优化可行率达到 99.17%。
不同任务模式产生了符合预期的策略分化：
fast 模式显著缩短扫描时间，foEs 模式获得最高频率分辨率，
hEs 模式改善高度分辨率，weakEs 模式获得最高积累增益。
与传统宽扫策略相比，任务驱动策略在多数模式下显著降低扫描时间，
并保持与任务目标一致的关键性能指标。
```

## 18. 后续改进建议

为了进一步提高论文质量，建议后续补充：

### 18.1 真实或半真实数据验证

哪怕只有少量真实电离图案例，也会显著提高论文说服力。

可以做：

- 真实初扫电离图输入。
- 人工标注 foE 和 foEs。
- 系统生成复探策略。
- 与测站经验策略对比。

### 18.2 IRI先验敏感性分析

因为 no_iri_prior 表面指标更好，需要增加一组实验说明 IRI 的物理覆盖价值。

例如：

```text
比较有无IRI时目标窗口是否覆盖正常E层和Es层可能范围。
```

### 18.3 weakEs基线优化

strong + weakEs 可行率较低，可以考虑：

- 自适应放宽扫描时间。
- 根据强度自动调整 weakEs 基线。
- 将 weakEs 分为 weak-only 和 general-visibility 两种模式。

### 18.4 代码模块化

后续建议拆分主文件，提高可维护性。

### 18.5 增加逐case进度日志

长时间实验建议每完成一个 case 就写入进度文件，避免中断后无法判断状态。

## 19. 总结

当前系统已经形成完整的 Es 自适应复探策略寻优框架。

其核心贡献是：

```text
将 Es 复探策略设计从单一最优问题转化为任务需求驱动的 Pareto 寻优问题。
```

系统通过 IRI 背景先验和初扫特征生成固定扫频范围，再在该范围内利用 NSGA-II 搜索不同任务偏好的策略参数。

完整实验表明：

- 扫频范围固定机制有效，`fixedErr_max = 0`。
- 总体优化可行率高，达到 `99.17%`。
- 六种任务模式产生了清晰的策略分化。
- 相比传统宽扫策略，扫描时间显著降低。
- baseline 和 ablation 实验支撑了系统设计的合理性。

因此，当前系统具备撰写 SCI 论文的基础。若仅基于仿真结果，较适合冲击 SCI 三区；若补充真实或半真实电离图验证，并加强 IRI 先验和物理覆盖性的论证，则可以尝试 SCI 二区。
