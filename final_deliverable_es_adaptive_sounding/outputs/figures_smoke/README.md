# figures_smoke目录说明

## 目录作用

该目录保存 SCI 补充实验 smoke 阶段生成的统计图。它们用于快速检查绘图流程是否正常，不代表最终论文级完整统计结果。

## 文件说明

| 文件 | 作用 |
|---|---|
| `mode_scan_time.png` | 不同任务模式平均扫描时间图。 |
| `mode_df.png` | 不同任务模式平均频率步进图。 |
| `mode_height_resolution.png` | 不同任务模式平均高度分辨率图。 |
| `mode_gain.png` | 不同任务模式平均积累增益图。 |
| `feasible_rate_heatmap.png` | 不同强度和任务模式下的可行率热力图。 |
| `baseline_scan_time.png` | 固定策略对比的扫描时间图。 |
| `ablation_feasible_rate.png` | 消融实验可行率图。 |

## 注意事项

最终论文级图像位于：

```text
outputs/final_full_run/figures_final/
```
