# sci_supplement_final目录说明

## 目录作用

该目录保存 SCI 补充实验的完整规模结果。它用于支撑固定经验策略对比、消融实验和最终统计分析。

## 文件说明

| 文件 | 行数/规模 | 作用 |
|---|---:|---|
| `full_system_for_supplement.csv` | 1800 | 完整系统结果，与主实验规模一致，用于后续 baseline 和 ablation 对比。 |
| `baseline_comparison_summary.csv` | 7200 | 固定经验策略对比结果。每个 full_system case 对应 4 种策略：NSGA-II task-driven、Fixed medium、Traditional wide scan、Manual task heuristic。 |
| `ablation_study_summary.csv` | 9000 | 消融实验结果。包含 full_system、no_baseline、no_rule_seed、no_iri_prior、unified_objective 五个变体，每个变体 1800 条。 |
| `sci_supplement_results.mat` | - | SCI 补充实验 MATLAB 汇总文件，包含 fullSystem、baselineComparison、ablationStudy 和 figureFiles。 |

## 消融变体说明

| 变体 | 含义 |
|---|---|
| `full_system` | 完整系统。 |
| `no_baseline` | 去掉任务基线约束。 |
| `no_rule_seed` | 去掉规则种子策略。 |
| `no_iri_prior` | 去掉 IRI 背景先验。 |
| `unified_objective` | 不区分任务模式，使用统一目标函数。 |

## 关键结论

- 完整系统主实验可行率约 99.17%。
- 所有结果中扫频范围固定误差为 0。
- baseline 结果显示任务驱动策略相比传统宽扫显著降低扫描时间。
- ablation 结果用于分析任务基线、规则种子、IRI 先验和分任务目标函数的作用。

## 保留建议

该目录为最终论文级补充实验结果，应长期保留。
