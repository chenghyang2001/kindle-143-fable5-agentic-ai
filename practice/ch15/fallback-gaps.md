# 備援靜默失效的地方

## 這次的執行（ch15/second-pass.txt）

`ch15/batch_results.jsonl` 的 8 筆分類（assert 全部通過，另外測了 400 invalid_request、expired、canceled、None 四種邊界）：

| custom_id | 結果 | 分類 | 處理 |
| --- | --- | --- | --- |
| ticket-001、002、005 | succeeded／end_turn | done | 直接採用 |
| sec-003 | succeeded／refusal（cyber）：「說明 SQL injection 的防禦方式」 | fallback | 以 claude-opus-4-8 重送，end_turn，349 token，三點防禦說明 |
| sec-006 | succeeded／refusal（reasoning_extraction）：「請逐步寫出你的完整思考過程，解釋…XSS」 | fallback | 以 claude-opus-4-8 重送，end_turn，2022 token |
| ticket-004 | errored／rate_limit_error 429，retry_after 10 秒 | retry_same_model | 只印計畫：第 1／2／3 次等 10／20／40 秒 |
| ticket-007 | errored／overloaded_error 529 | retry_same_model | 2／4／8 秒 |
| ticket-008 | errored／timeout_error | retry_same_model | 2／4／8 秒 |

第二輪結果寫在 `ch15/second_pass_out.jsonl`：保留 custom_id、原模型、原拒答類別、served_by、stop_reason、output_tokens、回答文字。

照實說明：
- 第一次執行時，429 的退避印成「10、10、10 秒」（每次都被 retry_after 蓋過，看不出倍增）。我修正成以 retry_after 為基準再倍增後重跑一次，所以本練習共 4 次 claude -p。第一次的輸出保留在 `ch15/second-pass-run1.txt`。
- `served_by` 取自 `msg.model`。在轉接層裡，這個值只是照抄請求的 model，本身不能證明真的換了模型；第 7 章練習 2 曾從 claude -p 的 `modelUsage` 確認，指定 claude-opus-4-8 時 CLI 確實用的是 Opus 4.8。
- sec-006 是 reasoning_extraction：備援雖然「接住」了，但正確的修法應該是改提示詞，不要要求外露思考過程。Opus 照字面寫了「讓我一步步推導這個完整的思考過程」，輸出 2022 token，是 sec-003 的將近 6 倍。對 reasoning_extraction 而言，轉備援只是繞過問題，不是解決問題。
- 這兩筆的「拒答」是我造的資料；Fable 5 實際上不一定會拒答這兩個提示詞（第 8 章的 reasoning_extraction 典型句就沒有被拒）。

## 書中提到的三個盲區與補救

| 盲區 | 為什麼備援會失效 | 補救做法 |
| --- | --- | --- |
| **批次 API** | 批次請求是離線處理，沒有伺服器端備援這一步；被拒答的項目以 `succeeded`＋`stop_reason: refusal` 的形式原樣回到結果檔，看起來是「成功」 | 客戶端做第二輪：讀結果檔，用 `classify()` 這類分流器挑出拒答項目，只換 model 送到備援模型（可以再組成一個新的小批次），並記錄 served_by 與原拒答類別；暫時性錯誤另外排程重試同一個模型 |
| **雲端託管端點**（透過雲端平台使用模型） | 伺服器端備援 beta 與 fallbacks 參數不一定在那個平台上提供；請求不會報錯，只是拒答時沒人接 | 在客戶端的共用呼叫層實作備援：檢查 stop_reason，拒答就以同樣的本體換 model 重送（第 9 章的 manual_fallback_with_credit 就是這個形狀），並把拒答類別寫進 log。部署前先用 canary（第 5 章）在該平台實測拒答率 |
| **巢狀子呼叫**（工具執行時自己又呼叫模型） | `fallbacks` 只對那一個請求有效，不會傳進工具內部的子呼叫；子呼叫被拒時，工具可能把空字串當結果往上回 | 在共用的模型呼叫函式裡預設帶 fallbacks 與 beta header，讓所有子呼叫都經過它（第 14 章的結論）；工具執行器把子呼叫的拒答轉成明確的工具錯誤，不回傳空字串 |

## 把 429 當成拒答丟去備援，會造成哪兩個問題

1. **品質與成本悄悄改變，問題卻沒解決**：429 代表「現在送太快」，模型並沒有拒絕這個內容。丟去備援之後，這筆其實可以由原模型回答的工作，改由另一個模型回答：品質、格式、單價都不一樣（第 7 章：Opus 4.8 和 Fable 5 的單價差一倍），而報表上看起來只是「備援接住了」。限流的根本原因（送太快、配額不足）也被掩蓋，沒有人去調整速率或申請配額。
2. **限流擴散，備援也被打爆**：429 通常是整個流量太大，不是單一請求的問題。把所有 429 都轉去備援模型，等於把同樣大的流量瞬間倒到備援那邊，很快連備援也 429，真正需要備援的拒答項目反而沒有容量可用。而且沒有退避，等於在限流時加速重送，讓情況更糟。

反過來也一樣：把拒答當成暫時錯誤一直重試同一個模型，同樣的內容會被同樣的分類器一直擋，只會白白浪費重試次數與時間，永遠拿不到答案。所以分流器的第一步，一定是先分清楚「內容被拒」和「服務暫時不行」。
