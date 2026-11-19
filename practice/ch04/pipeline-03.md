# 專案 3 成本儀表板：job packet 流程對照

執行指令：`K143_CLI_LOG=ch04/calls-03.jsonl PYTHONUTF8=1 python run_with_cli.py fable5/projects/03_cost_dashboard/cost_dashboard.py`，完整輸出在 `ch04/run-03.txt`，共 2 次 claude -p。

## 流程圖（實際走的段落）

```text
  sample_usage_log.csv（12 筆）
          │
          ▼
 ┌──────────────────────────┐
 │ prep                     │  ✗ 沒呼叫 packet.prep()
 │ 純 Python summarize()    │  → cost_dashboard.py 第 27～38、45～51 行
 │ 模型：無  effort：無      │    依 PRICES 算每個模型的呼叫數、token、金額
 └────────────┬─────────────┘
              ▼
 ┌──────────────────────────┐
 │ plan_or_audit            │  ✓ 呼叫 1（log 第 1 筆）
 │ 模型：claude-fable-5     │  → cost_dashboard.py 第 53～63 行，effort="high"
 │ effort：high             │    packet.py 第 46～50 行 → _ask(FABLE, …)
 │ 輸出 2,058 tokens        │    設計路由政策＋列出錯路由
 └────────────┬─────────────┘
              ▼
 ┌──────────────────────────┐
 │ execute                  │  ✓ 呼叫 2（log 第 2 筆）
 │ 模型：claude-sonnet-5    │  → cost_dashboard.py 第 68～74 行，沒傳 effort
 │ effort：medium（預設）    │    packet.py 第 53～55 行預設 medium → _ask(CHEAP, …)
 │ 輸出 740 tokens          │    把政策排版成終端機報告、×4 算月省
 └────────────┬─────────────┘
              ▼
 ┌──────────────────────────┐
 │ verify                   │  ✗ 沒呼叫 packet.verify()
 │ （設計上是 Fable / low）   │    cost_dashboard.py 只 import plan_or_audit 與 execute（第 18 行）
 └──────────────────────────┘
```

對照依據：模型名稱來自 `ch04/calls-03.jsonl` 兩筆紀錄的 `request.model` 與 `response.model`（第 1 筆 claude-fable-5、第 2 筆 claude-sonnet-5）。effort 這個欄位**沒有寫進 log**，是從程式讀的：plan_or_audit 明寫 `effort="high"`，execute 沒傳，所以用 packet.py 的預設 `medium`。轉接層會把它轉成 `claude -p --effort`。

## monitor 輸出

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner monitor ../ch04/calls-03.jsonl
refusal analytics
total 2   refused 0 (0.0%)   fallback served 0

by category

cost by model
  claude-fable-5       $0.1029
  claude-sonnet-5      $0.0111

top refusal-triggering prompt prefixes
```

2 次呼叫都沒拒答，也沒有走到 Opus 4.8 備援（轉接層本來就沒有伺服器端備援）。按 log 裡的 token 數算，這次跑儀表板本身花了約 $0.114（Fable $0.1029＋Sonnet $0.0111）。

## 週摘要的金額是誰算的

**Python 算的。** `summarize()`（第 27～38 行）用 PRICES 的單價乘以每筆 token 數再加總，第 46～51 行格式化後印出 `=== Week summary ===`。這段在任何模型呼叫之前就印出來了，然後才當成文字餵給 Fable。後面「錯路由」表格裡的金額則是**模型算的**。

## 驗算模型的錯路由金額

模型拿到的只有每個模型的加總，加上每筆的「模型: task_type」清單（第 50 行），**沒有每筆的 token 數**。所以它自己用平均值估算：38,430 tokens ÷ 7 次 ≈ $0.109／次，每一項都套這個平均。用 CSV 的實際數字驗算：

| 任務 | CSV 實際 token（輸入／輸出） | 現在（Fable） | 改成之後 | 實際每週省 | 模型說省 | 誤差 |
| --- | --- | --- | --- | --- | --- | --- |
| typo_fix → Haiku | 500／50 | 500×$10/M＋50×$50/M＝$0.00750 | 500×$1/M＋50×$5/M＝$0.00075 | **$0.00675** | $0.098 | 高估約 14.5 倍 |
| fix_one_test → Sonnet | 700／150 | 700×$10/M＋150×$50/M＝$0.01450 | 700×$2/M＋150×$10/M＝$0.00290 | **$0.01160** | $0.087 | 高估約 7.5 倍 |

五項加起來，實際每週只省 $0.0323（月省約 $0.13），模型說每週省約 $0.48、月省 $1.91，高估了大約 15 倍。原因是 Fable 的 $0.76 幾乎都花在 threat_model（$0.32）和 migration_plan（$0.40）這兩筆大任務上，小任務每筆才幾毫美元，用平均值估算就會被大任務撐大。

模型其實有在表格上方寫明「沒有每筆的 token 拆分，所以用平均值」，但 execute 段照抄了這些數字、再乘以 4，報告裡完全沒保留這個前提。如果有 verify 段拿 CSV 對照，這種錯應該會被抓到。**路由的方向（哪些該降級）是對的，金額是錯的。**

順帶一提：這次跑儀表板本身花了約 $0.114，比實際每週可省的 $0.032 還多。

## 一句話測試：哪一段可以降級

**execute 可以降到 Haiku（或直接用 Python）**：它只是把 plan_or_audit 已經列好的表格重排成終端機格式，再把數字乘以 4，沒有分支、也不需要判斷，一句話就能說清楚：「把這張表排成報告，每週數字乘以 4」。這個乘法用 Python 做反而不會出錯。

反過來，真正缺的是 verify：金額應該用 Python 從 CSV 重算，或讓一個只看 CSV 與主張的 low effort 驗證者檢查，而不是信任模型的估算。
