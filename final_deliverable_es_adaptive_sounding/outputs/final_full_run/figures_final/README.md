# figures_final目录说明

## 目录作用

该目录保存完整规模实验生成的最终统计图，可用于论文、报告或答辩展示。

## 文件说明

| 文件 | 作用 |
|---|---|
| `mode_scan_time.png` | 六种任务模式的平均扫描时间对比。 |
| `mode_df.png` | 六种任务模式的平均频率步进对比。 |
| `mode_height_resolution.png` | 六种任务模式的平均高度分辨率对比。 |
| `mode_gain.png` | 六种任务模式的平均积累增益对比。 |
| `feasible_rate_heatmap.png` | 不同 Es 强度和任务模式下的优化可行率热力图。 |
| `baseline_scan_time.png` | NSGA-II、固定 medium、传统宽扫和人工启发式策略的扫描时间对比。 |
| `ablation_feasible_rate.png` | 各消融变体的优化可行率对比。 |

## 使用建议

- 论文中建议优先使用 `mode_scan_time.png`、`mode_df.png`、`mode_gain.png` 和 `feasible_rate_heatmap.png`。
- `baseline_scan_time.png` 适合说明任务驱动策略相比传统宽扫的效率优势。
- `ablation_feasible_rate.png` 适合说明模块消融后的可行率变化。
