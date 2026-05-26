# Es自适应复探策略寻优系统项目说明

## 项目定位

本项目实现了一个面向偶发 E 层（Sporadic E, Es）探测任务需求的自适应复探策略寻优系统。系统利用初扫电离图特征和 IRI 背景先验生成固定复探扫频范围，并在该范围内使用 NSGA-II 搜索满足不同任务偏好的 Pareto 折中策略。

核心思想是：

```text
扫哪里：由 IRI 背景先验、初扫特征和任务模式固定生成。
怎么扫：由 NSGA-II 优化 df、PRP、chipLength、Ncoh、codeType 等策略参数。
选哪个：由任务偏好和基线约束从 Pareto 前沿中选择推荐策略。
```

## 顶层目录结构

```text
code/
docs/
outputs/
```

## 目录说明

| 目录 | 作用 |
|---|---|
| `code/` | 主系统代码和批量实验入口。 |
| `docs/` | 技术路线、系统分析、最终技术报告和设计计划文档。 |
| `outputs/` | 小规模验证、功能验证、完整规模实验结果和统计图。 |

## 推荐阅读顺序

1. 阅读 `docs/es_adaptive_sounding_final_technical_report.md`，了解系统结构、原理和实验结论。
2. 阅读 `code/README.md`，了解主代码与实验脚本入口。
3. 查看 `outputs/final_full_run/README.md`，了解最终完整规模实验结果。
4. 查看 `outputs/final_full_run/figures_final/` 中的统计图。

## 主实验结果位置

```text
outputs/final_full_run/final_report_batch_validation_summary.csv
outputs/final_full_run/sci_supplement_final/
outputs/final_full_run/figures_final/
```

## 注意事项

- `outputs/final_full_run/` 是论文级最终结果目录，建议保留。
- `outputs/*smoke*` 是小规模测试结果，可重新生成。
- `code/outputs/` 已清理，不再作为主结果目录。
