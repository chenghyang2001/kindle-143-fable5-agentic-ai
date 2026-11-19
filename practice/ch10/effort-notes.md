# Effort 筆記

## 本次實測（ch10/effort-results.txt，5 次 claude -p）

| 來源 | kind | effort | output_tokens |
| --- | --- | --- | --- |
| `er.run()` | classify | low | 5 |
| `er.run()` | summarize | medium | 220 |
| `er.run()` | audit（要求 10 行以內） | xhigh | 462 |
| 直接指定 | summarize（同一提示詞） | low | 207（回答 430 字元） |
| 直接指定 | summarize（同一提示詞） | xhigh | 281（回答 605 字元） |

## low 與 xhigh 差幾倍、差多少錢

同一個 summarize 提示詞：xhigh 281 ÷ low 207 ≈ **1.36 倍**，多了 74 個 output token。

用 README 的 Fable 輸出單價 $50／百萬 token 計算（**只是本次樣本，各跑一次**）：

- low：207 × $50 / 1,000,000 ＝ $0.01035
- xhigh：281 × $50 / 1,000,000 ＝ $0.01405
- 差額：74 × $50 / 1,000,000 ＝ **$0.0037**／次

差距比我預期小，原因可能是：摘要的輸入很短（5 行紀錄），值得多想的東西本來就不多，effort 拉高也沒什麼可以多寫；而且 medium（220）落在 low 與 xhigh 之間，三個數字其實很接近。對比之下，audit 在 xhigh 用了 462 token，即使提示詞要求 10 行以內，判斷密集的任務用掉的 token 明顯比較多。這也呼應 effort-router 技能的自我檢查：「如果每一級 effort 都加倍，品質會明顯變好嗎？」對這種短摘要來說，答案是不會，所以付 xhigh 只是多花錢。

量級：一天跑 1 萬次這種摘要，low 和 xhigh 每天差約 $37，一個月約 $1,110；這還沒算到更長的輸入可能讓差距變大。

## 為什麼 effort 不是硬上限

effort 是**行為訊號**，不是 token 預算（effort_router.py 的 docstring：「It is a behavioral signal, not a hard cap.」）：

- 它告訴模型「這件事值得投入多少心力」，模型依此決定要想多深、寫多長、呼叫幾次工具。它影響所有回應 token，包括文字、工具呼叫的參數與思考，但不會在某個數字把輸出截斷。
- 所以 low 不保證短。這次 low 的摘要用了 207 token，跟 medium 的 220 幾乎一樣，因為任務本身就需要那麼多字。
- 真正的硬上限是 `max_tokens`（到了就截斷，`stop_reason` 變成 max_tokens），或第 2 章看過的 `task_budget`。要控制成本上限，得靠這些參數；effort 控制的是「傾向」。
- 反過來，xhigh 也不保證長：沒什麼好想的任務，xhigh 也不會硬湊。

## 轉接層用 claude -p --effort，可能和直接打 API 不同

1. **傳遞方式不同**：轉接層把 `output_config.effort` 轉成 `claude -p --effort <level>`（claude_cli_client.py 第 160～161 行），由 Claude Code 再轉給模型。Claude Code 實際送出的請求怎麼設 effort、會不會再調整，我們看不到。
2. **外殼不同**：每次 `claude -p` 都帶著 Claude Code 自己的系統提示詞和工具定義，模型是在「代理」情境下回答，而不是單純的一問一答。effort 對 token 的影響可能被這層外殼稀釋或放大。
3. **max_tokens 被忽略**：`er.run()` 傳了 `max_tokens=2048`，轉接層不會傳過去，所以這次的數字不受截斷影響；直接打 API 時，如果某次超過上限，數字會被壓在 2048。
4. **output_tokens 的口徑**：這裡的 output_tokens 是 `claude -p` 回報的 usage，是否和直接打 API 時一樣把思考 token 算進去，從這個環境無法確認。
5. **樣本**：每個組合只跑一次，模型輸出本來就有變異，1.36 倍這個數字換一次可能就不一樣。正式決策應該對同一組提示詞各跑多次取中位數。

## 我的路由器（ch10/my_router.py → ch10/my-router.txt）

保留原版 9 種，加了 6 種這場演練實際遇到的類型：grade（low）、lint-explain（low）、write-report（medium）、memory-quarantine（low）、routing-policy（high）、scope-review（xhigh），每種都附一行理由。15 種加上 4 個邊界案例（未知類型、缺 kind、kind=None、不是 dict → high）全部 assert 通過。分布是 low 6、medium 4、high 1、xhigh 4、max 0。我沒有任何類型用 max，因為技能說 max 只留給「xhigh 經測量確實不夠」的情況，這場演練沒遇到。

改法上，我把 if／elif 換成一張 `POLICY` 對照表，effort 和理由放在一起，改政策只要改一處，也方便印出理由。
