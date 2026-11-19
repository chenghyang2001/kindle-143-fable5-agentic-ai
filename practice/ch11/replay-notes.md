# 重放規則筆記：為什麼兩條規則方向相反

## 結果摘要（ch11/replay-results.txt）

`ch11/history.json` 共 8 則訊息（4 輪），包含：1 個有內容的 thinking（第 2 則，帶簽章）、1 個空 thinking（第 4 則）、1 個 redacted_thinking（第 6 則，而且是那則訊息唯一的區塊）、1 組 tool_use／tool_result（toolu_01）。

| # | 檢查 | 結果 |
| --- | --- | --- |
| 1 | 同模型（fable → fable）：`json.dumps` 逐位元組相同，且是深拷貝 | ✅ |
| 2 | 跨模型（fable → opus）：thinking／redacted_thinking 全部歸零 | ✅ |
| 3 | 呼叫兩次之後，原物件仍與讀入時逐位元組相同 | ✅ |
| 4 | tool_use 與 tool_result 原樣保留，`toolu_01` 仍然對得上 | ✅ |
| 5 | 第 6 則只剩 redacted_thinking → 換成說明 text；訊息數仍是 8，user／assistant 交替不變 | ✅ |
| 6 | 非思考區塊逐字相同 | ✅ |
| 7 | 邊界：空歷史回空 list；不是 list 就拋 TypeError | ✅ |
| 8 | linter：處理前 3 條 `messages` warn，處理後 clean | ✅ |

錯誤示範 `well_meaning_cleanup`：同模型時「順手」刪掉空的 thinking，結果逐位元組比對變成 False（thinking 區塊 2 → 1，914 → 849 字元）。

linter 的小發現：它對每一則帶思考區塊的 assistant 訊息各報一次 warn（`break` 只跳出內層迴圈），所以處理前出現 3 條一樣的 `messages`。這不影響正確性，但 CI 報告會重複。

## 為什麼方向相反：同模型「一個位元組都不能動」，跨模型「一定要拿掉」

兩條規則看起來矛盾，其實保護的是同一件事：**思考區塊只對產生它的那個模型有意義。**

**同一個模型重放 → 原封不動**
- 思考區塊帶著簽章（`signature`），redacted_thinking 帶著加密內容（`data`）。它們是模型自己的內部狀態，伺服器會驗證這些區塊確實是同一個模型、在同一段上下文裡產生的。改內容、改順序，甚至只是刪掉一個空的 thinking，都會讓驗證或接續出問題。
- 提示詞快取靠前綴比對：歷史改了一個位元組，後面的快取就全部失效，要重新付寫入快取的錢（第 9 章算過，長的歷史差好幾倍）。
- 第 9 章的 fallback credit 也要求請求本體完全一致：「好心清洗」不只是多付一次快取的錢，還會讓 credit 兌換失敗。linter 的 warn 訊息裡也特別寫了這個例外（unless an exact-body fallback-credit redemption requires otherwise）。
- 空的 thinking 看起來是垃圾，其實它記錄了「這一回合模型思考過但沒有輸出內容」，加上它自己的簽章，所以是狀態的一部分。

**換模型重放 → 一定要拿掉**
- 別的模型看不懂、也驗證不了另一個模型的簽章與加密內容。把 Fable 的思考區塊送給 Opus（包括被備援改送到 Opus 的那種情況），輕則被拒，重則讓新模型把舊模型的內部推理當成自己的前提。
- 換模型時快取本來就要重建，原封不動也省不到快取，沒有理由保留。
- 但**只**拿掉思考區塊：text、tool_use、tool_result 是對話本身的事實，少了它們，新模型就不知道前面發生過什麼；tool_use 的 id 和 tool_result 的 tool_use_id 必須成對留著，否則請求會壞掉。

**整則訊息變空時**：不能刪掉整則（兩個 user 相鄰會破壞交替結構），也不能留空陣列（API 不接受空的 assistant content），所以補一個說明性的 text 區塊。這是唯一一處「新增內容」，而且只會在跨模型時發生。

一句話：**同模型時，思考區塊是要原樣交還的狀態；換模型時，它是別人看不懂的私有資料。** 所以「整理歷史」這件事，在同模型時是破壞，在跨模型時是必要。
