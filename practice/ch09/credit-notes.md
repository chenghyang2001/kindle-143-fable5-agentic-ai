# 備援 credit 筆記

## 測試結果（ch09/test-credit.txt，5/5 通過，0 次模型呼叫）

| 情境 | 驗證了什麼 |
| --- | --- |
| (a) 第一次就成功 | 只呼叫 1 次；請求是 claude-fable-5，帶 credit beta，沒有 fallback_credit |
| (b) 拒答＋有 token | 呼叫 2 次；第二次 model 換成 claude-opus-4-8，加上 `fallback_credit={"token": "tok-123", "has_prefill_claim": True}`，**其餘欄位的值與順序完全相同**；呼叫端傳入的 params 沒有被修改 |
| (c) 拒答＋沒有 token | 仍然重試到 Opus，本體一樣相同，但沒有 fallback_credit |
| (d) served_by_sticky | 只有 fallback_message → True；message 與 fallback_message 都有 → False；只有 message → False；iterations 是 None → False |
| (e) body_matches | 只換 model＋加 credit → True；「好心」刪掉 assistant 回合裡空字串的 text 區塊（2 個區塊變 1 個）→ **False** |

FakeClient 用深拷貝記錄每次的參數，所以如果 `manual_fallback_with_credit` 偷改了傳入的 dict，紀錄也不會跟著變，能抓到這種錯。

`body_matches` 的限制：它比的是 Python dict，所以只改欄位順序時仍然回 True（(e) 的附註）。伺服器比對的是收到的請求本體；如果你的 HTTP 層會重新序列化、改順序或改空白，dict 相同不代表位元組相同。要更嚴格，可以比對 `json.dumps(..., sort_keys=False)` 的結果，或在送出前對最終位元組做雜湊。

## 數字例子：有帶 token 與沒帶 token 的重試成本差

**以下全部是假設**，只用來看量級：

| 假設 | 數值 | 來源 |
| --- | --- | --- |
| 系統提示詞（已在 Fable 上快取） | 50,000 token | 自擬 |
| 這一輪新的使用者訊息（不在快取裡） | 500 token | 自擬 |
| 重試成功後的輸出 | 800 token | 自擬 |
| Fable 5 單價 | 輸入 $10／M、輸出 $50／M | fable5/README.md 第 121 行 |
| Opus 4.8 單價 | 輸入 $5／M、輸出 $25／M | README 沒寫；取自 fable_scanner/monitor.py 的 PRICE_PER_M |
| 寫入快取 | 輸入單價 × 1.25 | 題目給定的假設 |
| 讀取快取 | 輸入單價 × 0.1 | 題目給定的假設 |

第一次在 Fable 上被拒（兩種情況都一樣，不影響差額）：50,000 × 0.1 × $10/M ＋ 500 × $10/M ＝ **$0.0550**。

重試到 Opus 4.8：

| | 系統提示詞 50,000 token | 使用者訊息 500 token | 輸出 800 token | 合計 |
| --- | --- | --- | --- | --- |
| **沒帶 token**：Opus 從零寫快取 | 50,000 × 1.25 × $5/M ＝ $0.3125 | $0.0025 | $0.0200 | **$0.3350** |
| **有帶 token**：當成一直都在 Opus 上，計讀取快取 | 50,000 × 0.1 × $5/M ＝ $0.0250 | $0.0025 | $0.0200 | **$0.0475** |

**每次重試差 $0.2875，沒帶 token 的重試大約是有帶的 7 倍。** 假設每天 200 次拒答、一個月 6,000 次，差額是每月約 **$1,725**。

注意兩點：
- 差額幾乎全部來自系統提示詞那一段：系統提示詞越長，差得越多；提示詞短的話，這件事就不重要。
- 沒帶 token 的那次重試寫完快取之後，同一段對話在 Opus 上的下一輪就能讀快取了，所以多付的主要是「切換那一次」。但在拒答頻繁、每次都是新對話的工作負載（例如資安分流）上，每次都是「切換那一次」。

## 轉接層為什麼無法示範真正的 credit

1. **拿不到 token**：credit token 放在拒答回應的 `stop_details.fallback_credit_token`。`claude -p` 的輸出沒有 stop_details，轉接層一律填 None（拒答時填 `category=None`），所以就算真的被拒，也拿不到 token。
2. **beta 與參數被忽略**：`betas=["fallback-credit-2026-06-01"]` 和 `fallback_credit={...}` 在轉接層裡都被當成不支援的參數忽略掉，CLI 沒有對應的旋鈕可以傳過去。
3. **「本體完全一致」在這裡沒有意義**：每次 `claude -p` 都是一個新的 Claude Code session，真正送出的請求還包著 Claude Code 自己的系統提示詞、工具定義和它自己管理的快取，我們控制不了、也看不到最終的請求本體，更不可能保證兩次逐位元組相同。
4. **看不到計價**：轉接層走 Max 訂閱，沒有逐 token 的帳單可以比較「寫快取」和「讀快取」的價差；monitor 甚至不計 cache 欄位（第 5 章）。

所以這個練習只能用 FakeClient 驗證「請求長得對不對」，「credit 真的讓重試變便宜」只能在直接打 API、有逐筆帳單的環境裡驗證。
