# logs目录说明

## 目录作用

该目录保存完整规模实验的后台运行日志和状态记录。

## 文件说明

| 文件 | 作用 |
|---|---|
| `status.txt` | 记录 full-scale 实验开始、阶段切换、补跑开始和完成状态。 |
| `main_final_1800.log` | 主实验 final 1800 条运行日志。 |
| `sci_supplement_final.log` | 第一次 SCI supplement final 运行日志。该次运行在消融阶段前中断，日志为空或不完整。 |
| `sci_supplement_final_restart.log` | 补跑 SCI supplement final 的日志，最终显示 baseline=7200、ablation=9000、figures=7、exit code=0。 |

## 读取建议

优先查看：

```text
status.txt
sci_supplement_final_restart.log
```

它们能确认最终实验已经正常完成。
