# final_full_run目录说明

## 目录作用

该目录保存论文级完整规模实验结果，是当前项目最重要的输出目录。

完整实验包括：

```text
主实验 final：1800 条
SCI supplement full_system：1800 条
baseline 固定策略对比：7200 条
ablation 消融实验：9000 条
统计图：7 张
```

## 文件说明

| 文件 | 作用 |
|---|---|
| `final_report_batch_validation_summary.csv` | 论文主实验 1800 条 CSV 结果。 |
| `final_report_batch_validation_summary.mat` | 论文主实验 MAT 结果。 |
| `run_full_scale.ps1` | 后台运行主实验和补充实验的 PowerShell 脚本。 |
| `run_sci_supplement_final_restart.ps1` | 补跑 SCI supplement final 的 PowerShell 脚本，支持复用已有 full_system 和 baseline。 |

## 子目录说明

| 子目录 | 作用 |
|---|---|
| `sci_supplement_final/` | SCI 补充实验完整结果，包括 full_system、baseline、ablation 和 MAT 汇总。 |
| `figures_final/` | 完整规模实验生成的论文级统计图。 |
| `logs/` | 长时间后台运行日志和状态记录。 |

## 关键结果

主实验结果：

```text
fixedErr_max = 0
总体可行率 = 99.17%
```

消融实验结果：

```text
5 个变体 × 1800 = 9000 条
```

## 保留建议

该目录建议完整保留，后续论文写作和结果复核都依赖这里的数据。
