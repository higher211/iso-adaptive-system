# Es任务驱动自适应复探寻优技术路线报告

## 一、问题背景

偶发E层（Es）复探策略不存在一个对所有任务都绝对最优的参数组合。快速告警、foEs 精读、h'Es 稳定读取、弱 Es 增强和完整形态观测，对扫描时间、频率分辨率、高度分辨率、积累增益和可观测性的要求不同。

因此，本系统采用任务驱动寻优路线：

```text
用户先确定探测任务；
系统固定复探扫频范围；
所有任务在统一工程可行域中搜索；
不同任务通过基线约束和偏好目标引导 NSGA-II；
最终输出该任务下的 Pareto 折中策略。
```

## 二、总体技术路线

```text
初探策略执行
↓
初探电离图特征提取
    foE_obs
    foEs_obs
    df_coarse
    SNR
    traceContinuity
↓
IRI背景先验获取
    foE_IRI
↓
按任务模式生成固定复探扫频范围
    fStartMHz
    fEndMHz
↓
统一工程可行域定义
    df / PRP / chipLength / Ncoh / codeType
↓
统一初始种群生成
    规则种子策略 + 拉丁超立方采样
↓
NSGA-II迭代
    评价指标计算
    模式基线约束
    非支配排序
    拥挤距离
    交叉与变异
↓
形成Pareto候选
↓
按任务偏好选择最终策略
↓
输出复探策略与推荐理由
```

## 三、固定扫频范围

扫频范围由初探特征和 IRI 背景先验生成，在进入 NSGA-II 前已经确定。

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

因此，覆盖率不再作为优化目标。`EsCoverage` 只用于检查固定窗口是否被破坏。

## 四、统一工程可行域

所有模式共享同一套搜索范围：

```text
dfMHz        ∈ 全局频率步进范围
PRP          ∈ 全局脉冲重复周期范围
chipLength   ∈ 全局码片宽度范围
Ncoh         ∈ 全局相干积累次数范围
codeType     ∈ 全局可选码型集合
```

不同模式不允许通过修改这些范围来制造不同结果。

其意义是：

```text
工程可行域由设备能力和物理约束决定；
任务模式只改变评价标准；
最终差异来自任务需求，而不是来自人为缩放搜索空间。
```

## 五、规则种子策略的作用

规则种子策略是 NSGA-II 初始种群的一部分。

它不是最终策略，也不是人为指定最优解，而是具有工程意义的搜索起点：

```text
快速种子：代表短扫描时间方向；
精细频率种子：代表 foEs 精读方向；
高增益种子：代表弱 Es 增强方向；
高度分辨率种子：代表 h'Es 稳定读取方向；
综合种子：代表平衡折中方向。
```

所有模式使用同一套规则种子。

随后，NSGA-II 通过交叉、变异和选择产生新策略。真正决定策略演化方向的是：

```text
当前模式的基线约束；
当前模式的目标函数；
约束支配排序；
Pareto非支配关系。
```

## 六、随机采样策略的作用

除规则种子外，剩余初始个体通过统一可行域内的拉丁超立方采样生成。

拉丁超立方采样的作用是：

```text
让 df、PRP、chipLength、Ncoh、codeIndex 在各自范围内均匀覆盖；
避免初始种群集中在少数区域；
提高 Pareto 前沿搜索的多样性。
```

因此，随机策略不是拍脑袋生成，而是在统一工程可行域内进行结构化采样。

## 七、模式基线约束

不同模式的基线约束不同。

基线不是最优策略，而是最低可接受条件：

```text
fast：扫描时间必须明显快，最低可观测性达标；
foEs：df和频点数必须支持边界读取；
hEs：高度分辨率必须满足虚高读取；
weakEs：积累增益和可观测性要求更高；
full_trace：频点数和分辨率必须支持形态观测；
balanced：各项指标达到中等可用水平。
```

违反基线的候选会增加 `constraintViolation`，在 NSGA-II 约束支配排序中靠后。

## 八、模式目标偏好

不同模式的目标函数不同：

```text
fast:
    min scanTimeSec
    max observabilityScore
    min complexityCost

foEs:
    min dfMHz
    min scanTimeSec
    max integrationGainDb

hEs:
    min heightResolutionKm
    max integrationGainDb
    min scanTimeSec

weakEs:
    max observabilityScore
    max integrationGainDb
    min scanTimeSec

full_trace:
    min dfMHz
    min resolutionCost
    max observabilityScore
    min scanTimeSec

balanced:
    min scanTimeSec
    min resolutionCost
    max observabilityScore
```

这些目标用于引导 Pareto 前沿形成，而不是用单一加权值直接指定答案。

## 九、fast模式示例

假设 fast 模式固定窗口为：

```text
[7.70, 8.50] MHz
```

NSGA-II 在统一范围中搜索候选，例如：

```text
候选A：df大、Ncoh低、Barker码，扫描极快但频点数偏少；
候选B：df中等、Ncoh中等、Barker码，扫描较快且可观测性达标；
候选C：df小、Ncoh高、互补码，可观测性强但扫描时间过长。
```

fast 基线会惩罚：

```text
频点数过少的候选A；
扫描时间过长的候选C。
```

最终 Pareto 前沿中更可能保留候选B一类策略：

```text
扫描时间短；
最低可观测性达标；
复杂度较低；
适合快速判断 Es 是否出现。
```

## 十、论文表述建议

可以表述为：

```text
本文在统一物理工程可行域内构建 Es 自适应复探策略寻优框架。
系统首先基于 IRI 背景先验和初探电离图特征确定固定复探扫频窗口，
随后采用统一规则种子和拉丁超立方采样生成初始种群。
不同探测任务不改变参数搜索范围，
而是通过任务基线约束和多目标偏好引导 NSGA-II 搜索 Pareto 前沿，
最终输出满足对应任务需求的折中复探策略。
```

核心句：

```text
规则种子和搜索空间统一，任务基线和偏好分化；
不同模式结果来自不同评价标准，而不是来自不同搜索范围。
```

## 十一、大批量测试方法

为证明系统不是由少数样例或人为设定得到结论，需要加入大批量测试。测试目标不是证明某个模式永远优于其他模式，而是验证：

```text
1. 固定扫频范围是否始终不进入寻优；
2. 所有模式是否共享统一搜索范围；
3. 不同模式是否因基线和偏好不同而产生不同策略倾向；
4. Pareto 搜索是否稳定；
5. 输出策略是否满足物理/工程约束和任务基线；
6. 在不同 Es 场景和噪声条件下，系统是否仍能给出合理策略。
```

### 11.1 单场景全模式回归测试

目的：

```text
验证同一个初探场景下，六种模式都能运行，并且 fStart/fEnd 完全固定。
```

测试方法：

```text
固定场景随机种子；
固定 IRI 背景；
固定初探配置；
分别运行 fast、foEs、hEs、weakEs、full_trace、balanced；
记录每个模式的 target.requiredRangeMHz 和 optimizedCfg.fStart/fEnd。
```

判据：

```text
fixedErr = max(abs(target.requiredRangeMHz - [cfg.fStartMHz, cfg.fEndMHz]))
fixedErr 应为 0 或接近浮点误差。
```

同时检查：

```text
df、PRP、chipLength、Ncoh、codeType 均位于统一全局范围内；
EsCoverage 不作为目标函数驱动项；
不同模式的策略倾向符合任务偏好。
```

### 11.2 多随机种子稳定性测试

目的：

```text
验证 NSGA-II 不是偶然一次随机结果。
```

测试方法：

```text
保持同一 Es 场景；
改变 NSGA-II seed；
每个模式运行 N 次，例如 N = 30；
记录最终推荐策略和 Pareto 候选统计。
```

统计指标：

```text
scanTimeSec 的均值、标准差、分位数；
dfMHz 的均值、标准差、分位数；
heightResolutionKm 的均值、标准差；
integrationGainDb 的均值、标准差；
observabilityScore 的均值、标准差；
optimizationFeasible 比例；
固定窗口误差 fixedErr 最大值。
```

判据：

```text
所有 fixedErr 接近 0；
绝大多数运行能找到 optimizationFeasible 策略；
同一模式输出分布稳定，不应大范围随机漂移；
不同模式之间的指标分布应体现任务偏好差异。
```

### 11.3 多 Es 场景覆盖测试

目的：

```text
验证系统对不同 Es 强度、不同 foEs 位置、不同背景 E 层条件都有适应性。
```

建议构造场景组：

```text
弱 Es：SNR 较低，要求 weakEs 模式更偏向高增益；
中等 Es：一般条件，balanced 应表现稳定；
强 Es：回波明显，fast 应能给出短扫描策略；
低 foEs：Es 截止频率靠近 E 层背景；
高 foEs：Es 截止频率明显高于背景；
foE_obs 可见：初探可读正常 E 层；
foE_obs 不可靠：只使用 IRI 背景和 foEs_obs。
```

测试矩阵：

```text
场景数 M × 模式数 6 × NSGA-II随机种子数 N
```

例如：

```text
M = 8 个典型场景
N = 10 个优化随机种子
总运行数 = 8 × 6 × 10 = 480 次
```

判据：

```text
每次运行固定窗口正确；
参数均在统一可行域；
各模式主要指标符合预期排序：
    fast 的 scanTimeSec 通常较低；
    foEs 的 dfMHz 通常较低；
    hEs 的 heightResolutionKm 通常较低；
    weakEs 的 integrationGainDb/observabilityScore 通常较高；
    full_trace 的 nFreq 通常较多；
    balanced 位于折中区域。
```

### 11.4 边界条件测试

目的：

```text
验证系统在极端输入下不会崩溃，也不会违反固定窗口和工程约束。
```

建议测试：

```text
1. 固定窗口很窄；
2. 固定窗口较宽；
3. foEs_obs 接近初扫下边界；
4. foEs_obs 接近初扫上边界；
5. foE_obs 缺失；
6. IRI 背景可用但与观测点接近；
7. IRI 背景与观测点差异较大；
8. 低 SNR 弱回波；
9. traceContinuity 较差；
10. 可行域内很难同时满足扫描时间和增益基线。
```

判据：

```text
程序无错误退出；
若无法满足所有基线，应明确输出违反的约束项；
不允许通过改变 fStart/fEnd 来规避约束；
不允许生成越界参数。
```

### 11.5 消融对比测试

目的：

```text
验证规则种子、随机采样、模式基线和目标偏好各自的作用。
```

建议对比组：

```text
A. 规则种子 + 拉丁超立方采样 + 模式基线 + 模式目标；
B. 仅拉丁超立方采样 + 模式基线 + 模式目标；
C. 规则种子 + 拉丁超立方采样 + 无模式基线 + 模式目标；
D. 规则种子 + 拉丁超立方采样 + 模式基线 + 统一目标。
```

观察指标：

```text
找到可行解的比例；
收敛代数；
Pareto候选数量；
最终策略是否符合模式偏好；
不同模式之间是否能拉开差异。
```

预期：

```text
规则种子应提升搜索效率；
模式基线应减少不符合任务最低要求的候选；
模式目标应形成不同任务下的 Pareto 前沿差异。
```

### 11.6 统计汇总与可视化

大批量测试结果建议输出表格和图：

```text
1. 每个模式的 scanTimeSec 箱线图；
2. 每个模式的 dfMHz 箱线图；
3. 每个模式的 heightResolutionKm 箱线图；
4. 每个模式的 integrationGainDb 箱线图；
5. 每个模式的 observabilityScore 箱线图；
6. fixedErr 最大值表；
7. optimizationFeasible 比例表；
8. Pareto候选数量统计表；
9. 不同模式最终策略雷达图或平行坐标图。
```

这些图表用于证明：

```text
fast 确实更偏向短扫描；
foEs 确实更偏向小 df；
hEs 确实更偏向高高度分辨率；
weakEs 确实更偏向高增益和可观测性；
full_trace 确实更偏向频点充分和分辨率；
balanced 处于综合折中位置。
```

### 11.7 建议的测试规模

开发阶段：

```text
6 个模式 × 1 个场景 × 1 个 seed
用于快速检查语法、固定窗口和基本输出。
```

功能验证阶段：

```text
6 个模式 × 6 个场景 × 5 个 seed = 180 次
用于确认模式差异和稳定性。
```

论文/报告阶段：

```text
6 个模式 × 8~12 个场景 × 10~30 个 seed
总运行数约 480~2160 次。
```

如果单次仿真耗时较长，可以降低正演子射线数和真值频率密度做算法统计，再对少量代表性结果运行高精度正演复核。

### 11.8 测试输出字段

每次测试至少记录：

```text
caseId
taskMode
optimizerSeed
scenarioSeed
foE_IRI
foE_obs
foEs_obs
df_coarse
targetStartMHz
targetEndMHz
cfgStartMHz
cfgEndMHz
fixedErr
dfMHz
PRP
chipLength
Ncoh
codeType
codeLength
nFreq
scanTimeSec
heightResolutionKm
hAmbKm
dutyRatio
integrationGainDb
observabilityScore
resolutionCost
complexityCost
feasible
optimizationFeasible
constraintViolation
nPareto
nOptimizationFeasible
selectedLexicographicRank
```

这些字段可以直接支撑后续论文中的统计表、箱线图和 Pareto 对比图。
