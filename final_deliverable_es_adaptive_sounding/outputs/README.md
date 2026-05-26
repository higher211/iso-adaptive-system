# outputs目录说明

## 目录作用

`outputs/` 保存系统运行产生的实验结果、统计图、日志和最终完整规模结果。

## 顶层文件说明

| 文件 | 作用 |
|---|---|
| `dev_batch_validation_summary.csv` | 小规模 dev 批量验证结果。 |
| `functional_batch_validation_summary.csv` | functional 批量验证结果，用于检查多场景多种子运行稳定性。 |
| `smoke_final_report_batch_validation_summary.csv` | final report smoke 测试结果。 |
| `smoke_final_report_batch_validation_summary.mat` | smoke 测试对应 MAT 文件。 |

## 子目录说明

| 子目录 | 作用 |
|---|---|
| `figures_smoke/` | smoke 级统计图。 |
| `sci_supplement_smoke/` | SCI 补充实验 smoke 结果。 |
| `final_full_run/` | 论文级完整规模实验结果，是最重要的结果目录。 |

## 保留建议

- `final_full_run/` 建议长期保留。
- smoke/dev/functional 结果可重新生成，但也可保留用于对比调试。
