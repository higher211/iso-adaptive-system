# Es自适应复探策略寻优系统技术分析报告

## 1. 系统目标

本系统面向偶发E层（Es）复探任务，目标不是寻找一个适用于所有探测需求的唯一最优策略，而是构建一个任务驱动的自适应策略寻优框架。

系统核心定位为：

```text
基于初探电离图特征和IRI背景先验生成固定复探扫频范围；
在统一物理/工程可行域内搜索策略参数；
根据不同任务模式的基线约束和目标偏好形成Pareto候选；
最终输出面向任务需求的复探策略。
```

因此，不同模式结果的差异来自任务评价标准，而不是来自人为改变搜索范围。

## 2. 系统主流程

系统完整流程如下：

```text
Es场景与背景电离层建模
↓
初探策略仿真
↓
初探电离图预处理
↓
Es/E层特征提取
    foE_obs
    foEs_obs
    meanSNR
    traceContinuity
↓
IRI背景先验获取
    foE_IRI
↓
按任务模式生成固定复探扫频范围
↓
NSGA-II策略参数寻优
↓
Pareto候选筛选
↓
按任务偏好选择最终推荐策略
↓
优化策略复探仿真与结果评价
```

其中，真值场景只用于最终验证，不进入策略寻优过程。

## 3. 固定扫频范围生成

当前系统已经将复探扫频范围从寻优变量中移除。

固定量：

```text
fStartMHz
fEndMHz
```

优化量：

```text
dfMHz
PRP
chipLength
Ncoh
codeType / codeLength
```

扫频范围由以下信息生成：

```text
foE_IRI：IRI背景E层临界频率
foE_obs：初探观测E层截止频率
foEs_obs：初探观测Es截止频率
df_coarse：初扫频率步进
userMargin：用户设置的IRI扩展margin
taskMode：任务模式
```

规则是：

```text
先比较参与频率点大小；
再根据边界点来源进行扩展；
IRI点使用margin扩展；
观测点使用df_coarse扩展；
最终得到固定复探窗口。
```

NSGA-II 内部虽然仍保留七维染色体接口：

```text
[fStartMHz, fEndMHz, dfMHz, PRP, chipLength, Ncoh, codeIndex]
```

但 `fStartMHz` 和 `fEndMHz` 的上下界被强制固定为 `target.requiredRangeMHz`，交叉、变异、修复和最终策略选择均不能改变这两个值。

## 4. 统一搜索范围

所有任务模式共享同一套工程/物理可行域：

```text
dfMHz        ∈ 全局频率步进范围
PRP          ∈ 全局脉冲重复周期范围
chipLength   ∈ 全局码片宽度范围
Ncoh         ∈ 全局相干积累次数范围
codeType     ∈ 全局可选码型集合
```

当前设计明确禁止不同模式单独覆盖：

```text
bounds.dfMHz
bounds.chipLength
codeTypeSet
NcohIntegerRange
```

也就是说：

```text
所有模式在同一个搜索空间内竞争；
不同模式只改变基线约束、目标函数和Pareto选择规则。
```

这增强了系统方法的可解释性，避免“不同模式靠人为缩小搜索范围得到不同结果”的质疑。

## 5. 各任务模式寻优逻辑

### 5.1 fast 快速告警模式

目标：

```text
尽快判断Es是否出现。
```

偏好：

```text
min scanTimeSec
max observabilityScore
min complexityCost
```

典型策略表现：

```text
较大df
较低Ncoh
较短扫描时间
较低复杂度
```

### 5.2 foEs 精读模式

目标：

```text
提高Es截止频率foEs读取精度。
```

偏好：

```text
min dfMHz
min scanTimeSec
max integrationGainDb
```

典型策略表现：

```text
较小df
较多频点
适中扫描时间
```

### 5.3 h'Es 稳定读取模式

目标：

```text
提高Es虚高h'Es读取稳定性。
```

偏好：

```text
min heightResolutionKm
max integrationGainDb
min scanTimeSec
```

典型策略表现：

```text
较短chipLength
较高高度分辨率
适中积累增益
```

### 5.4 weakEs 弱Es增强模式

目标：

```text
弱回波条件下优先保证Es可观测。
```

偏好：

```text
max observabilityScore
max integrationGainDb
min scanTimeSec
```

典型策略表现：

```text
较高Ncoh
较高积累增益
扫描时间相对较长
```

### 5.5 full_trace 完整形态观测模式

目标：

```text
获取Es完整频率结构和轨迹形态。
```

偏好：

```text
min dfMHz
min resolutionCost
max observabilityScore
min scanTimeSec
```

典型策略表现：

```text
频点数最多
df较小
扫描时间较长
适合形态分析
```

### 5.6 balanced 综合平衡模式

目标：

```text
在扫描时间、分辨率和可观测性之间折中。
```

偏好：

```text
min scanTimeSec
min resolutionCost
max observabilityScore
```

典型策略表现：

```text
扫描时间、频率分辨率、高度分辨率和增益均处于中等折中状态。
```

## 6. Es强度与随机种子设置

### 6.1 Es强度设置

最终测试中使用三档Es强度：

```text
weak
moderate
strong
```

它们通过以下参数控制：

```text
foEsExcessOverIriEMHz
foEsSigmaMHz
reflectivity
noiseStd
```

含义如下：

```text
foEsExcessOverIriEMHz：
    控制Es截止频率相对IRI背景E层的超出量，是Es总体强度的重要控制量。

foEsSigmaMHz：
    控制Es空间随机起伏强度。

reflectivity：
    控制Es回波反射强度比例。

noiseStd：
    控制观测噪声强度。
```

### 6.2 scenarioSeed

`scenarioSeed` 控制同一强度等级下的随机空间实现。

它影响：

```text
Es空间斑块位置
局部foEs起伏
patchWeight分布
局部Es强弱和连续性
```

它不直接改变Es总体强度等级，但会改变该强度等级下具体一次场景实现。

### 6.3 optimizerSeed

`optimizerSeed` 控制 NSGA-II 优化随机过程，包括：

```text
规则种子之外的随机补充初始种群
父代选择
交叉
变异
```

一次完整优化运行只设置一次 `optimizerSeed`，后续所有随机步骤沿用该随机序列，不会每一代重新设置seed。

## 7. 批量测试设计

最终论文/报告规模测试采用：

```text
3 个Es强度等级
× 6 个任务模式
× 10 个scenarioSeed
× 10 个optimizerSeed
= 1800 次运行
```

测试目的：

```text
1. 验证固定扫频范围是否始终不进入寻优；
2. 验证不同任务模式是否产生不同策略倾向；
3. 验证不同Es强度下系统是否稳定；
4. 验证不同空间斑块实现下系统是否稳定；
5. 验证不同NSGA-II随机搜索路径下结果是否稳定。
```

测试输出文件：

```text
code/outputs/final_report_batch_validation_summary.csv
code/outputs/final_report_batch_validation_summary.mat
```

## 8. 最终测试结果分析

### 8.1 测试规模完整性

结果文件包含：

```text
1800 行
```

覆盖：

```text
intensityMode = weak / moderate / strong
taskMode = fast / foEs / hEs / weakEs / full_trace / balanced
scenarioSeed = 3101:3110
optimizerSeed = 20260515:20260524
```

说明最终测试规模完整。

### 8.2 固定扫频范围结果

核心指标：

```text
maxFixedErr = 0
```

说明1800次测试中：

```text
optimizedCfg.fStartMHz == targetStartMHz
optimizedCfg.fEndMHz   == targetEndMHz
```

结论：

```text
扫频范围固定机制完全生效；
fStartMHz/fEndMHz没有进入NSGA-II寻优。
```

### 8.3 总体可行率

整体可行率：

```text
optimizationFeasible rate = 0.9917
```

即约：

```text
99.17%
```

这说明大多数场景下系统都能找到满足硬约束和任务基线的可行策略。

## 9. 各模式统计结果

按全部强度合并统计，各模式平均结果为：

```text
fast:
    meanScan = 0.274 s
    meanDf   = 0.338 MHz
    meanGain = 18.92 dB

foEs:
    meanDf    = 0.021 MHz
    meanNFreq = 25.2
    meanScan  = 1.239 s

hEs:
    meanHRes = 1.200 km
    meanGain = 23.21 dB

weakEs:
    meanGain = 26.44 dB
    meanScan = 3.898 s

full_trace:
    meanNFreq = 34.8
    meanDf    = 0.067 MHz
    meanScan  = 3.849 s

balanced:
    meanScan = 0.907 s
    meanDf   = 0.182 MHz
```

这些结果与模式设计一致：

```text
fast最快；
foEs频率步进最小；
hEs高度分辨率最好；
weakEs积累增益最高；
full_trace频点数最多；
balanced处于折中位置。
```

## 10. 不同Es强度结果

按强度统计：

```text
weak:
    meanFoEs = 8.775 MHz
    feasibleRate = 1.000

moderate:
    meanFoEs = 9.475 MHz
    feasibleRate = 1.000

strong:
    meanFoEs = 10.300 MHz
    feasibleRate = 0.975
```

说明：

```text
Es强度设置生效；
foEs_obs随强度等级增强而升高；
强Es场景通常对应更高foEs和更宽目标窗口。
```

## 11. 未完全可行样例分析

未完全满足 `optimizationFeasible` 的样例集中在：

```text
intensityMode = strong
taskMode = weakEs
scenarioSeed = 3107 / 3109 / 3110
```

这些场景具有：

```text
foEs_obs = 11.75 MHz
targetEndMHz = 12 MHz
```

典型失败样例指标：

```text
integrationGainDb ≈ 24.56 ~ 24.94 dB
observabilityScore ≈ 0.683 ~ 0.710
constraintViolation ≈ 0.0099 ~ 0.0369
feasible = 1
optimizationFeasible = 0
```

解释：

```text
这些策略满足物理/工程硬约束；
但在strong Es且foEs很高的宽窗口场景下，
weakEs模式要求更高可观测性，
少量候选略低于任务基线，因此optimizationFeasible为0。
```

这不是程序错误，而是任务基线发挥作用的体现。

## 12. 结果意义

最终测试结果说明：

```text
1. 固定扫频窗口机制稳定可靠；
2. 统一搜索范围设计成立；
3. 不同模式策略分化明显；
4. 强度分组生效；
5. 系统在多场景、多随机搜索路径下具有较高稳定性；
6. 少量不可行样例具有明确物理和任务约束解释。
```

## 13. 后续改进建议

当前系统中的 `observabilityScore` 主要由策略参数中的积累增益等指标计算，未充分利用初探提取的真实回波特征。

后续可以进一步加入：

```text
meanSNR
traceContinuity
weakEdgeWidthMHz
```

使弱Es、强Es以及轨迹连续性变化更直接地影响策略寻优。

建议改进方向：

```text
1. 将初探meanSNR引入weakEs模式基线；
2. 将traceContinuity引入full_trace模式评价；
3. 将weakEdgeWidthMHz引入foEs边界读取稳定性评价；
4. 对strong + weakEs宽窗口场景适当放宽或动态调整可观测性基线。
```

## 14. 总结

本系统已经实现了：

```text
固定扫频范围；
统一工程可行域；
任务基线与偏好驱动；
NSGA-II Pareto寻优；
多强度、多场景、多随机路径验证。
```

最终1800次测试结果表明：

```text
扫频范围固定完全正确；
整体可行率达到99.17%；
不同任务模式呈现符合设计目标的策略差异；
Es强度设置对foEs_obs和目标窗口产生了合理影响。
```

因此，该系统可以作为论文/报告中的“任务需求驱动Es自适应复探策略寻优框架”的核心实验结果。
