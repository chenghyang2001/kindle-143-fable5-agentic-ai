# 金絲雀與監控筆記

在 `ch05/` 裡執行：`canary init`（0 次呼叫）→ 在 `ch05/.fable-scanner/baseline.json` 加入 `my-format` → `canary run`（5 次 claude -p，輸出 `canary-run1.txt`）→ 在 `fable5/` 下跑 `monitor ../ch05/canary-calls.jsonl`（輸出 `monitor.txt`）。

## 每個提示詞的分數與延遲

| id | 狀態 | 延遲 | 分數 | 實際輸出（`.fable-scanner/latest.json`） |
| --- | --- | --- | --- | --- |
| code-simple | ok | 3190 ms | 100% | ```` ```python\ndef reverse_string(s):\n    return s[::-1]\n``` ````（55 字元） |
| reason-plain | ok | 3092 ms | 100% | `20` |
| instruction-follow | ok | 2766 ms | 100% | `alpha bravo charlie` |
| knowledge | ok | 4914 ms | 100% | 一句話，含「false positives」，183 字元 |
| my-format | ok | 3919 ms | 100% | `STATUS: OK\nTESTS: 4`（19 字元） |

延遲是 canary.py 在 `_call()` 前後用 `time.monotonic()` 量的（第 60、69 行），包含轉接層啟動 `claude -p` 子程序的時間，不是純 API 延遲。

## 我設計的 my-format

```json
{"id": "my-format",
 "prompt": "Summarize this CI result in exactly two lines and nothing else.\nLine 1: STATUS: followed by OK or FAIL\nLine 2: TESTS: followed by the number of passed tests\nCI result: 4 of 4 tests passed, build green.",
 "expect": {"contains": ["status: ok", "tests: 4"], "max_len": 40}}
```

實際輸出 `STATUS: OK\nTESTS: 4`，完全照格式，3 項檢查都過。

**太鬆的地方**（拿實際規則推）：
- `_score()` 會先把輸出轉小寫（第 42 行），所以 `status: ok`、`Status: Ok` 都算過，大小寫寫錯不會被抓到。
- `contains` 只檢查子字串，不檢查順序與行數：`STATUS: OK TESTS: 4` 寫成一行也會過；`TESTS: 40` 也會過，因為裡面含 `tests: 4`。
- `max_len: 40` 留了 21 字元的空間：如果模型在前面加「Here is it:\n」（11 字元）變成 30 字元，照樣滿分。這正好是我最想抓的漂移（不守「nothing else」）。

**太緊的地方**：這次沒有。19 字元離 40 還很遠；就算模型用程式碼區塊包起來（約 27 字元）也會過，所以不會誤報。

**怎麼改**：canary 只支援 `contains`／`exact`／`min_len`／`max_len`。要嚴格的話可以直接用 `exact: "STATUS: OK\nTESTS: 4"`（`exact` 會先 strip，但不轉小寫），或把 `max_len` 收到 25。我選 contains＋max_len 是為了符合題目要求，結果證明它對「格式」的把關偏鬆。

同樣的問題也出現在內建的 code-simple：提示詞說「Return only the code」，輸出卻包了 ```` ```python ```` 區塊，分數仍然是 100%，因為 expect 只檢查有沒有 `def `、`return` 和長度 ≥ 20。

## 為什麼第一次 run 不會比較

`canary init` 只寫入提示詞，`outcomes` 是空的 `{}`（第 81 行）。`run_canary()` 第 101～106 行看到 `outcomes` 是空的，就把這次的 refused／ms／score 寫進 baseline.json 當基準，印出「first run -- snapshot captured as baseline outcomes」然後回 0。沒有基準就沒有東西能比；金絲雀比的是「跟過去的自己比有沒有漂移」，所以第一次只能拍快照。代價是：如果第一次就是壞的（例如延遲特別高），之後的比較都會以壞的基準為準。

## monitor 的成本數字從哪裡來

`monitor.py` 第 51～57 行：對每筆 log 的 `response.usage.iterations[]`，用 `iteration.model` 查 `PRICE_PER_M`（Fable 是 $10／$50 每百萬 token），計算 `input_tokens × 輸入價 + output_tokens × 輸出價`。

這次 5 筆：input_tokens 各是 2（共 10），output_tokens 是 25＋3＋11＋58＋17＝114。10×$10/M＋114×$50/M ≈ $0.0058，跟 `monitor.txt` 一致。

注意：每筆 log 還有 `cache_read_input_tokens`（約 650～680）或 `cache_creation_input_tokens`（716），那是 `claude -p` 自己的系統提示詞。monitor **不看這兩個欄位**，所以 $0.0058 低估了實際用量。另外 monitor 的 Sonnet 單價是 $3／$15，第 4 章成本儀表板用的是 $2／$10（推廣價），兩支程式的價目表不一致。

## 轉接層下為什麼看不到拒答類別與備援

- **拒答類別**：真的 API 拒答時會回 `stop_reason: "refusal"`，並在 `stop_details.category` 寫明 cyber／bio／frontier_llm／reasoning_extraction。`claude -p` 的輸出沒有這個欄位，所以轉接層一律填 `stop_details: None`（claude_cli_client.py 第 30、233、244 行）。monitor 的「by category」和「top refusal-triggering prompt prefixes」因此永遠是空的。這次 5 筆都是 `end_turn`，本來就沒有拒答。
- **備援**：真的 API 帶 `betas: server-side-fallback-…` 和 `fallbacks: [{model: claude-opus-4-8}]` 時，被分類器擋下的請求會在伺服器端改由 Opus 4.8 回答，`usage.iterations` 裡會出現 `type: "fallback_message"` 的那一段。轉接層把 betas／fallbacks 忽略掉（第 23～24 行），CLI 也沒有對應功能，所以永遠不會有 fallback_message，monitor 的 `fallback served` 也一定是 0（第 29 行）。

## 真實部署時這兩個欄位為什麼最重要

1. **拒答不是錯誤**：拒答回的是 HTTP 200，不會出現在 5xx 錯誤率裡。沒有 `stop_reason`／`category`，拒答就是「靜靜地拿到空內容」，迴圈卡住也沒有警報。
2. **類別決定怎麼處理**：`reasoning_extraction` 代表提示詞寫法有問題（例如要它 explain your reasoning），應該修提示詞；`cyber` 出現在正當的資安工作上，代表該接備援或調整措辭。不知道類別，就不知道該修哪裡。
3. **備援會改變你以為在用的模型**：`fallback_message` 代表那個回答其實是 Opus 4.8 寫的，不是 Fable 5。如果備援比例上升，品質、成本（價目不同）和行為都會跟著改變，金絲雀分數卻可能看起來正常。job_packet 的 docstring 也提醒「check the returned category before assuming Fable itself saw the prompt」。
4. **漂移的早期訊號**：金絲雀的拒答率告警（`refusal_max=0.2`）完全依賴 `refused`。在轉接層下，這條告警永遠不會觸發，只剩延遲和分數兩條在把關。
