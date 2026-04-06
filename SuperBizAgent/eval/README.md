# 参数优化测试集（chunk / top-k）

这个目录用于做 RAG 参数回归测试，目标是比较不同参数下的稳定性，而不是只看单次问答体验。

## 文件说明

- `chunk_topk_testset.jsonl`: 问题测试集（每行一个 JSON）
- `run_eval.ps1`: 批量调用 `/api/chat` 并按关键词命中率打分
- `summarize_csv.ps1`: 对已生成的 CSV 汇总通过率、关键词得分、失败题号

## 快速使用（PowerShell）

1. 启动服务后执行：

```powershell
pwsh .\eval\run_eval.ps1 -BaseUrl "http://localhost:9900" -Repeat 3
```

2. 查看输出：

- 控制台会打印总通过率和按类别通过率
- 详细结果在 `.\eval\last_eval_result.csv`

### 只看汇总（不用逐行看 CSV）

对已有 CSV 统计 **通过率、关键词得分、按分类、失败 id**：

```powershell
powershell -NoProfile -File "D:\maven_project\SuperBizAgent\eval\summarize_csv.ps1" -CsvPath "D:\maven_project\SuperBizAgent\eval\last_eval_result.csv"
```

只看某一类（例如 `rag`）：

```powershell
powershell -NoProfile -File "D:\maven_project\SuperBizAgent\eval\summarize_csv.ps1" -CsvPath "D:\maven_project\SuperBizAgent\eval\last_eval_result.csv" -Category "rag"
```

## 如何做 chunk / top-k 对比

建议固定同一份文档，按以下矩阵跑：

- chunk.max-size: `400 / 800 / 1200`
- chunk.overlap: `50 / 100 / 150`
- rag.top-k: `3 / 5 / 8`

每次改参数后：

1. 重启服务
2. 重新上传文档（触发重新分片和重建向量）
3. 执行：

```powershell
pwsh .\eval\run_eval.ps1 -Repeat 3 -OutCsv ".\eval\result_chunk800_topk5.csv"
```

最后按通过率、失败样本、答案长度波动综合判断。

## 文档不变时能不能测？

可以。你可以把文档固定为同一版本，反复测参数差异。

注意两点：

- 模型有随机性，单次结果不稳，建议 `Repeat >= 3`
- 若要更稳定，建议将对话模型温度调低（例如 0.2~0.3）后再跑评估

## 打分说明（当前脚本）

- 每条样本有 `must_keywords`
- 回答包含全部 must 关键词 -> `pass=true`
- 这是一种轻量自动打分，适合做参数筛选

如果你需要更严格评估，可扩展两种方式：

1. 增加 `expected_phrases` 和负例关键词
2. 增加人工抽样复核（建议每组参数至少抽 10 条）
