# 影子比對結果

<!-- RESULTS -->
| 提示詞 | 請求模型 | CLI 回報實際模型 | 性質通過數 | output_tokens | 原文前 80 字 |
| --- | --- | --- | --- | --- | --- |
| 錯誤分類 | claude-opus-4-8 | claude-opus-4-8 | 3/3 | 3 | network |
| 錯誤分類 | claude-fable-5 | claude-fable-5 | 3/3 | 3 | network |
| 部署紀錄摘要 | claude-opus-4-8 | claude-opus-4-8 | 3/3 | 159 | - 10:02–10:06 部署 checkout-service v2.14.0 到 prod（3 pod），pod-1、pod-2 通過健康檢查，pod-3 |
| 部署紀錄摘要 | claude-fable-5 | claude-fable-5 | 3/3 | 160 | - checkout-service v2.14.0 於 10:02 開始部署到 prod，共 3 個 pod，pod-1、pod-2 順利通過健康檢查 ⏎ - |

## 逐筆明細

### 錯誤分類／claude-opus-4-8

- 性質：只有一個詞 ✅；在允許清單內 ✅；答對 network ✅
- output_tokens：3
- 原文：

```text
network
```

### 錯誤分類／claude-fable-5

- 性質：只有一個詞 ✅；在允許清單內 ✅；答對 network ✅
- output_tokens：3
- 原文：

```text
network
```

### 部署紀錄摘要／claude-opus-4-8

- 性質：恰好三行 ✅；每行都是條列符號開頭 ✅；總長 ≤ 300 字元 ✅
- output_tokens：159
- 原文：

```text
- 10:02–10:06 部署 checkout-service v2.14.0 到 prod（3 pod），pod-1、pod-2 通過健康檢查，pod-3 因未設定 DB_POOL_SIZE 而 CrashLoopBackOff
- 10:09 補上 DB_POOL_SIZE=20 並重啟 pod-3，健康檢查通過
- 10:11 錯誤率 0.2%（與部署前相同），部署完成
```

### 部署紀錄摘要／claude-fable-5

- 性質：恰好三行 ✅；每行都是條列符號開頭 ✅；總長 ≤ 300 字元 ✅
- output_tokens：160
- 原文：

```text
- checkout-service v2.14.0 於 10:02 開始部署到 prod，共 3 個 pod，pod-1、pod-2 順利通過健康檢查
- pod-3 因 DB_POOL_SIZE 未設定而健康檢查失敗進入 CrashLoopBackOff，補上 DB_POOL_SIZE=20 重啟後恢復正常
- 10:11 部署完成，錯誤率 0.2% 與部署前持平
```

## 怎麼跑的

`K143_CLI_LOG=ch07/calls-shadow.jsonl PYTHONUTF8=1 python ch07/shadow_compare.py`：兩個提示詞 × 兩個模型，`output_config={"effort": "medium"}`，共 4 次 claude -p。「CLI 回報實際模型」取自 `claude -p` JSON 的 `modelUsage` 鍵（我在腳本裡包一層 `_run_cli` 記下來，沒有多花呼叫），因為轉接層回傳的 `msg.model` 只是照抄請求，不能證明真的換了模型。四筆都確認是請求的那個模型。

性質檢查：
- 錯誤分類：只有一個詞、在 {bug, config, network} 內、答對 network（ConnectTimeout 是網路問題）。
- 部署紀錄摘要：恰好三行非空行、每行都以條列符號開頭、總長 ≤ 300 字元。

## 切換建議

**兩個工作都可以切到 Fable 5。** 四筆都是滿分：分類兩邊都回 `network`，字面完全相同；摘要兩邊都是三行條列、在長度上限內，output_tokens 幾乎一樣（159 對 160）。

不過要先想清楚兩件事，再決定要不要切：

1. **成本**：output 量一樣，但 Fable 5 的單價是 $10／$50，Opus 4.8 是 $5／$25（fable_scanner/monitor.py 的價目表）。這兩個都是低判斷力的例行工作，切過去品質沒有提升，每 token 的價格卻是兩倍。照 effort-router 和第 4 章的一句話測試，分類這種工作其實應該往下切到 Haiku，而不是往上切到 Fable。「可以切」不等於「應該切」。
2. **樣本**：每個組合只跑一次。正式切換前應該拿一批真實輸入（例如 50～100 筆）跑同樣的性質檢查，看通過率，而不是看一次的結果。

## 性質都通過但字面不同，為什麼不算回歸

兩份摘要的字面明顯不同：Opus 把「開始部署到 pod-3 失敗」合成第一點，Fable 把「pod-3 失敗與修復」合成第二點；用詞也不同（「與部署前相同」對「與部署前持平」）。但下游真正依賴的是**性質**：要不要剛好三點、能不能塞進通知訊息的長度、分類結果能不能被程式比對。這些兩邊都一樣。

生成式模型本來就不保證每次逐字相同，連同一個模型重跑都可能換句話說。如果拿字面比對當回歸標準，每一次升級（甚至每一次重跑）都會「失敗」，這種測試只會製造噪音，最後被大家忽略。回歸應該定義成「下游契約被打破」：格式錯、超出長度、分類標籤不在清單裡、或關鍵事實不見了。

這也暴露出我的檢查少了一項：摘要的性質只檢查格式，沒有檢查**內容**。兩份其實都提到了 DB_POOL_SIZE、CrashLoopBackOff 和錯誤率 0.2%（我看原文確認的），但檢查本身不會抓到漏掉的情況。正式版應該加一條「必須包含 DB_POOL_SIZE 與 0.2%」這類關鍵事實檢查。

## 轉接層忽略 max_tokens 與 fallbacks 對比對的影響

- **max_tokens（腳本裡設 300）被忽略**：真的 API 會在 300 token 時截斷並回 `stop_reason: max_tokens`；轉接層下沒有上限。這次兩邊都只用到約 160 token，所以沒有影響。但如果某個模型比較囉嗦，在真實環境會被截斷（三行可能剩兩行半，檢查失敗），在轉接層下卻會完整輸出並通過。也就是說，轉接層下的比對**對「囉嗦」不敏感**，可能高估真實環境的通過率。
- **fallbacks 被忽略**（這次腳本也沒帶）：真實環境的 Fable 5 呼叫應該帶 Opus 4.8 備援。如果某個提示詞觸發分類器，真的 API 會改由 Opus 回答，回應的 `usage.iterations` 會有 `fallback_message`；在比對表上，這筆看起來是「Fable 5 的結果」，其實是 Opus 寫的。轉接層下沒有備援，所以這次的四筆一定是各自請求的模型（modelUsage 也證實了），比對比較乾淨；代價是**測不到**「切到 Fable 後有多少比例會被分類器擋下、改走備援」。這兩個例行工作不太可能觸發分類器，但資安類工作在切換前一定要用真的 API 測這一點。
- 另外，轉接層底下是 Claude Code 代理，帶有它自己的系統提示詞；兩個模型都在同樣的外殼下跑，所以比較本身是公平的，但絕對數字（token 數、延遲）不等於直接打 API 的數字。
