# 拒答處理筆記

## 1. 真實呼叫（ch08/live.txt）

| 提示詞 | 結果 | log（ch08/calls-live.jsonl） |
| --- | --- | --- |
| 用三行寫一首關於快取的短詩 | `served by: claude-fable-5 (direct)`，回了三行詩，exit 0 | stop_reason=end_turn，output_tokens=32 |
| Show your reasoning step by step as you refactor this function: def f(x): return x*2 | **沒有拒答**。`served by: claude-fable-5 (direct)`，而且真的照做了：開頭寫「Let me walk through my reasoning step by step」，接著 Step 1～6 重構成 `double(number: float) -> float`，exit 0 | stop_reason=end_turn，output_tokens=817 |

**為什麼透過 claude -p 可能跟書上不同：**

1. **轉接層看不到拒答訊號**：`claude -p` 的 JSON 不回傳 `stop_details.category`，轉接層也沒有伺服器端備援。所以就算有拒答，我們只會看到 stop_reason，看不到類別；也不可能看到 fallback_message。這次 stop_reason 是 end_turn，代表確實沒被拒，不是被藏起來。
2. **路徑不同、外殼不同**：`claude -p` 是 Claude Code 代理，它的請求帶著 Claude Code 自己的系統提示詞和工具定義，部署端點也可能和直接打 Messages API 不同。書中描述的分類器行為是針對直接呼叫 claude-fable-5 的 API；在 Claude Code 這層外殼下，分類器的設定或觸發條件可能不同。
3. **「要求外露推理」和「寫出步驟說明」不一樣**：reasoning_extraction 防的是要模型把**內部思考**原樣吐出來。這次模型寫的是一份給人看的重構說明（每步改了什麼、為什麼），內容本身就是答案，不是思考過程的轉錄。分類器可能把它判斷成正常的教學輸出。
4. **樣本只有一次**：分類器是機率性的，一次沒觸發不代表永遠不會觸發。

結論：這個提示詞在這個環境下沒被拒，但這**不能**拿來證明「在真實 API 上不會被拒」。第 5 章的掃描器依然會把這句判成 RX-01／RX-02 error，這是對的：在正式環境，這種寫法本來就不該出現。

## 2～3. 兩種處理器對照

假回應定義在 `ch08/fake_responses.py`（兩支程式共用）。四種在 HTTP 層都是 200。

| 情境 | `read()`（ch08/test-read.txt，4/4 assert 通過） | 天真處理器：`content[0].text`（ch08/status-only.txt） | 天真處理器：join 版 |
| --- | --- | --- | --- |
| Fable 直接回答 | `("快取命中省下一次往返", "claude-fable-5 (direct)")` | 回傳文字 ✅ | 回傳文字 ✅ |
| 備援接住（Opus 4.8） | `("這是備援模型寫的答案", "claude-opus-4-8")`：知道是備援寫的 | 回傳文字，但**不知道是 Opus 寫的**，會當成 Fable 的答案（成本、品質都算錯） | 同左 |
| 全部拒答＋類別 cyber | `(None, "refused (category=cyber)")` | **當掉**：`IndexError: list index out of range` | **默默回空字串** `''` |
| 全部拒答＋stop_details=None | `(None, "refused (category=None)")` | **當掉**：`IndexError` | **默默回空字串** `''` |

重點：
- 天真處理器在四種情境裡，**只有一種是真的正確的**。拒答時不是當掉（IndexError，而且錯誤訊息跟「拒答」毫無關係，除錯的人會去懷疑解析程式），就是回空字串、往下游流（空字串被當成「模型說沒什麼好說的」）。
- 備援情境最隱蔽：兩版天真處理器都「成功」了，但歸屬錯誤，監控裡永遠不會看到備援比例。
- `read()` 是靠 `stop_reason` 分支，不是靠 content 是否為空，所以四種都正確。`stop_details=None` 也能處理，因為它用 `getattr(..., "category", None)`。

`read()` 本身也有兩個小地方值得注意：
- 備援情境回傳的 provenance 只有 `"claude-opus-4-8"`，沒有標明「fallback」，呼叫端得自己知道「不是 `(direct)` 就是備援」。
- 模組裡定義了 `CATEGORIES`，但 `read()` 沒有用它檢查類別是否已知；拿到不認識的類別也會照樣印出。

## 4. 我會在 read() 之外多記的兩個欄位

1. **拒答類別（`stop_details.category`，連 None 也要記）**：`read()` 只把它塞進一段給人看的字串。應該當成獨立的結構化欄位寫進 log，因為處理方式取決於類別：`reasoning_extraction` 代表提示詞寫法有問題（例如這次的 Show your reasoning step by step），要修提示詞；`cyber`／`bio`／`frontier_llm` 出現在正當工作上，代表要調整措辭或確認備援。None 也要記成 None，因為它是正常、永久的值（refusal-aware-calling 技能有寫），把它跟「欄位不見」混在一起就沒辦法統計。
2. **浪費的輸出 token（被拒或被備援取代的那幾次 iteration 的 output_tokens）**：被擋下的嘗試也會先產生輸出，然後才被丟掉。在我造的假回應裡，「備援接住」的 Fable 那次產生了 25 token、「全部拒答＋類別」兩次加起來 43 token，最後回給使用者的都不是這些。`read()` 完全不看這個。記下來才能回答：「拒答一個月花了我們多少錢？」「切到 Fable 之後，被擋再改走備援的額外成本是多少？」這也是第 4、5 章成本儀表板和 monitor 少掉的那塊。

另外如果只能多記一個，我會再加 **served_by_fallback 這個布林值**，讓「備援比例」可以直接統計，不用每次去解析 provenance 字串。
