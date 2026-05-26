# sci_supplement_smoke目录说明

## 目录作用

该目录保存 SCI 补充实验的 smoke 级结果。smoke 级实验规模较小，主要用于验证脚本链路是否可以正常生成 full_system、baseline、ablation 和 MAT 汇总。

## 文件说明

| 文件 | 作用 |
|---|---|
| `full_system_for_supplement.csv` | smoke 级完整系统结果。 |
| `baseline_comparison_summary.csv` | smoke 级固定经验策略对比结果。 |
| `ablation_study_summary.csv` | smoke 级消融实验结果。 |
| `sci_supplement_results.mat` | smoke 级补充实验 MAT 汇总文件。 |

## 注意事项

该目录结果不能作为最终论文统计结果。最终结果位于：

```text
outputs/final_full_run/sci_supplement_final/
```
