# code目录说明

## 目录作用

`code/` 保存系统主代码、IRI 辅助脚本和实验运行入口。当前主干系统不依赖旧版本副本，核心文件共 5 个。

## 文件说明

| 文件 | 作用 | 是否主干 |
|---|---|---|
| `es_only_adaptive_sounding_system.m` | 主系统文件，包含 Es 场景生成、初探仿真、特征提取、IRI 先验、固定扫频范围生成、NSGA-II 优化、Pareto 策略选择和结果评价。 | 是 |
| `iri2020_profile.py` | IRI2020 背景剖面辅助脚本，为 MATLAB 主系统提供背景 E 层先验。 | 是 |
| `run_es_batch_validation.m` | 批量验证底层入口，按强度、任务模式、场景种子和优化器种子批量运行主系统。 | 是 |
| `run_es_final_report_batch_test.m` | 论文主实验入口，完整 final 实验规模为 1800 条。 | 是 |
| `run_es_sci_supplement_experiments.m` | SCI 补充实验入口，生成 full_system、baseline、ablation、统计图和 MAT 汇总。 | 是 |

## 主系统调用关系

```text
run_es_final_report_batch_test.m
        ↓
run_es_batch_validation.m
        ↓
es_only_adaptive_sounding_system.m
```

SCI 补充实验调用关系：

```text
run_es_sci_supplement_experiments.m
        ↓
run_es_batch_validation.m
        ↓
es_only_adaptive_sounding_system.m
```

## 主要运行命令

主实验 final：

```matlab
addpath('code');
T = run_es_final_report_batch_test();
```

SCI 补充实验 final：

```matlab
addpath('code');
R = run_es_sci_supplement_experiments(struct('stage','final'));
```

小规模 smoke 验证：

```matlab
addpath('code');
T = run_es_final_report_batch_test(struct('smoke',true));
```

## 代码维护说明

- 不建议随意拆分或删除 `es_only_adaptive_sounding_system.m` 内部函数。
- 如需重构，建议按场景、正演、特征提取、目标窗口、优化器、评价模块逐步拆分。
- 当前系统中扫频范围已固定，不进入 NSGA-II 寻优。
