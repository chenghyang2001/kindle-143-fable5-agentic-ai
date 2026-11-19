# 遷移筆記：Opus 4.8 → Fable 5

輸出檔：`ch07/lint-before.txt`（原始範例 6 個 finding、3 個 error，exit 1；test_migration_linter 3/3 通過）、`ch07/lint-after.txt`（fixed_request.json：clean，exit 0）、`ch07/ci-gate.txt`（4 份請求有 3 份 FAIL，exit 1）。

## fixed_request.json 改了什麼

| 原始 | 修改後 | 對應 finding |
| --- | --- | --- |
| `"temperature": 0.7`、`"top_p": 0.9` | 刪除 | temperature、top_p（error） |
| `"thinking": {"type": "enabled", "budget_tokens": 8000}` | 整個刪除 | thinking.budget_tokens（error） |
| assistant 回合裡的 `{"type": "thinking", ...}` | 刪除，只留 text 區塊 | messages（warn） |
| 沒有 fallbacks | `"fallbacks": [{"model": "claude-opus-4-8"}]` | fallbacks（warn） |
| 沒有 effort | `"output_config": {"effort": "medium"}` | output_config.effort（info） |

effort 選 medium：任務是摘要事故報告，屬於 effort-router 說的「routine transforms」。model 原本就寫 claude-fable-5（範例雖然叫 opus_request，model 欄位已經改過），所以保留。

## 每種 finding 的後果

| finding | 嚴重度 | 後果 | 說明 |
| --- | --- | --- | --- |
| temperature／top_p／top_k | error | **400** | Fable 5 的思考一律開著，不接受取樣參數，整個請求直接被拒。舊程式最常帶著 temperature 一起搬過來。 |
| `thinking: {type: "disabled"}` | error | **400** | 思考無法關閉，送 disabled 會被拒。原本為了省錢或降延遲而關思考的呼叫，搬過來就會全部失敗。 |
| `thinking.budget_tokens` | error | **400** | 手動預算已經不支援，深度改由 `output_config.effort` 控制。 |
| assistant 回合帶著 thinking／redacted_thinking 區塊 | warn | **日後難改**（並可能被拒） | 思考區塊和產生它的模型綁在一起。換模型時（包括被備援改送到 Opus 4.8），帶著別的模型的思考區塊會出問題；如果寫進對話紀錄的儲存格式，之後每一條歷史對話都要清。 |
| Fable 呼叫沒有 fallbacks | warn | **卡死** | 拒答是 HTTP 200＋空內容，沒有備援就沒有東西能接手，迴圈拿到空字串後停住或默默往下走。資安這類容易被誤判的工作最常遇到。 |
| 沒設 `output_config.effort` | info | **白花錢**＋**日後難改** | 預設是 high；摘要、分類這類簡單工作用 high 是多付錢、多等時間。而且沒有明寫，日後要整個機隊調整 effort，就得一份一份去找、去改，不是改一個地方就好。 |

## CI 閘門（ch07/ci_gate.py）

匯入 `migration.migration_linter.lint()`，掃 `ch07/requests/*.json`，有 error 的檔印出 FAIL 與欄位，任何一份 FAIL 就 exit 1。結果：

| 檔案 | 結果 | 欄位 |
| --- | --- | --- |
| 01-fixed.json | PASS | — |
| 02-original-opus.json | FAIL | temperature、top_p、thinking.budget_tokens（error）；messages、fallbacks（warn）；output_config.effort（info） |
| 03-top-k-only.json | FAIL | top_k |
| 04-thinking-disabled.json | FAIL | thinking |

exit code 1。另外測了兩個邊界案例（沒有寫進交付檔）：空資料夾回 exit 2（「沒有 .json 請求」），壞掉的 JSON 會被當成 error 回 exit 1，不會因為解析失敗就被跳過而偷偷通過。

閘門只用 error 決定失敗，warn 不擋。這是故意的：error 是一定 400 的硬錯誤；warn 需要判斷（例如 fallback-credit 兌換時要保留原始 body）。代價是缺 fallbacks 的請求仍然會進到正式環境。

## linter 沒檢查、但遷移時也該檢查的一件事：model 有沒有真的改

linter **完全不檢查 model 欄位**。我實際試過：

```python
lint({"model": "claude-opus-4-8", "output_config": {"effort": "high"},
      "messages": [{"role": "user", "content": "hi"}]})
# → []，也就是 clean: this request is already Fable-5 valid
```

一份根本還在打 Opus 4.8 的請求，會被報成「已經是 Fable 5 合法請求」。而且 fallbacks 那條 warn 只在 `model == "claude-fable-5"` 時才檢查（第 50 行），所以 model 沒改的請求連這個提醒都拿不到。遷移時最容易漏的就是：某個設定檔或環境變數裡的 model 字串沒換，結果 CI 全綠，正式環境卻還在跑舊模型、付舊價、測不到新行為。

建議加一條：遷移模式下，`model` 不在目標清單（claude-fable-5／claude-mythos-5）就報 error。

順帶發現但這次不展開的兩件事：
- `thinking: {"type": "enabled"}` 沒帶 budget_tokens 時也不會被抓（只檢查 disabled 和 budget_tokens）。
- fallbacks 那條訊息提到要加 server-side-fallback 的 beta header，但 linter 沒有檢查 header（它只看 JSON body）；只有 fallbacks、沒有 header，一樣會在拒答時卡死。
