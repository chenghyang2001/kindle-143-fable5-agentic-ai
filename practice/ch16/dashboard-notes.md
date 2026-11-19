# 拒答儀表板筆記

log 由 `ch16/make_logs.py` 產生（固定亂數種子、隨機打散位置、時間平均分散在一週內），格式和 `fable_scanner/examples/refusal_log.jsonl` 相同；備援那 15 筆的 `usage.iterations` 是 Fable 的 message（0 輸出）＋Opus 的 fallback_message。告警邏輯在 `ch16/drift_alert.py`，直接 import `fable_scanner.monitor.analyze()`。輸出在 `ch16/drift.txt`。

## 兩週數字

| 指標 | week1（200 筆） | week2（1000 筆，流量 5 倍） | 比率變化 |
| --- | --- | --- | --- |
| cyber | 4（2.00%） | 20（2.00%） | +0.00 個百分點，1.0 倍 |
| reasoning_extraction | 2（1.00%） | 30（3.00%） | **+2.00 個百分點，3.0 倍** |
| fallback_served | 0（0.00%） | 15（1.50%） | **+1.50 個百分點，從 0 開始** |
| 拒答合計 | 6（3.00%） | 50（5.00%） | +2.00 個百分點，1.7 倍 |

## 天真版（次數 > 10）在 week2 誤報與漏報了什麼

week2 天真版發出 4 個告警：cyber 20、reasoning_extraction 30、fallback_served 15、拒答合計 50。

- **誤報：cyber**。20 筆看起來是 week1 的 5 倍，但流量也是 5 倍，比率都是 2.00%，完全沒變。這個告警純粹是流量造成的。值班的人去查會發現「什麼都沒壞」，幾次之後就會開始忽略告警，到了真正出事時也跟著被忽略。
- **抓對但理由錯：reasoning_extraction 與 fallback**。它們確實該告警，但天真版告警的理由是「次數超過 10」，所以如果流量沒有變 5 倍，例如還是 200 筆，就算 reasoning_extraction 從 1% 漲到 3%（6 筆），也不會告警。
- **漏報**：我另外造了一週低流量資料驗證：100 筆裡 9 筆 reasoning_extraction（9%，是 week1 的 9 倍）。天真版**無告警**，因為 9 不大於 10；比率版告警「1.00% → 9.00%，+8 個百分點，9.0 倍」。流量低的時候（假日、新服務剛上線），天真版會整個瞎掉。
- 反過來，week1 天真版也沒有告警，但那只是因為量小，不代表狀態健康。

天真版的根本問題是：次數同時受「流量」和「拒答率」影響，它分不出是哪一個在變。

## 比率版的結論

比率版在 week2 發出 3 個告警：reasoning_extraction、fallback_served、拒答合計；**cyber 沒有告警**。

- **cyber 是流量造成的**：2.00% → 2.00%，次數變 5 倍，完全由流量 5 倍解釋，比率沒漂移。
- **reasoning_extraction 是真的漂移**：1.00% → 3.00%，+2 個百分點、3 倍。流量只解釋了 5 倍中的「量」；如果比率不變，week2 應該只有 1000 × 1% ＝ 10 筆，實際是 30 筆，多出來的 20 筆就是漂移。reasoning_extraction 是看提示詞的「形狀」觸發的（要求外露推理），所以最可能的原因是這週有人上線了新的提示詞或範本，裡面寫了「step by step 解釋你的推理」之類的話。下一步是查這 30 筆的提示詞前綴（monitor 的 top refusal-triggering prompt prefixes），再用第 5 章的掃描器掃那份提示詞。
- **fallback 是新出現的訊號**：week1 0 筆，week2 15 筆（1.5%）。代表有 1.5% 的回答其實是 Opus 4.8 寫的，品質與成本都和 Fable 不同；這要和 reasoning_extraction 的上升一起查，看是不是同一批請求。
- 拒合計的告警是上面兩個加起來的結果，可以當總覽，但定位問題要看分類別的比率。

## 真實紀錄：為什麼拒答與備援一定是 0

用第 4 章的 `ch04/calls-02.jsonl`＋`ch04/calls-03.jsonl`（5 筆）當基準、第 5 章的 `ch05/canary-calls.jsonl`（5 筆）當本週，兩邊所有類別都是 0 次，三種告警都沒有。這是轉接層的結構造成的，不是因為「這些請求很安全」：

1. **拒答類別**：`claude -p` 的輸出沒有 `stop_details.category`，轉接層寫 log 時固定填 `stop_details: null`。monitor 的 `by_category` 只認得 cyber／bio／frontier_llm／reasoning_extraction，所以就算真的有拒答，也只會算進 refused，所有分類別都會是 0。
2. **備援**：轉接層忽略 `betas` 與 `fallbacks`，CLI 也沒有伺服器端備援，log 裡的 `iterations` 永遠只有 `type: "message"`，不會出現 `fallback_message`，所以 fallback_served 一定是 0。
3. 這 10 筆在 log 裡的 stop_reason 都是 end_turn，所以 refused 也是 0。

所以這個儀表板如果接在轉接層後面，會永遠顯示「一切正常」。這正是本章標題說的「錯誤儀表板看不見的拒答」：資料來源本身就不帶這兩個欄位，告警規則寫得再好也沒用。真實部署時，要確保 log 來自直接打 Messages API 的回應。

## Prometheus 告警規則草稿

需要兩個 counter 指標（在共用的模型呼叫層、每次拿到回應時累加）：

1. `fable_requests_total{model}`：所有送出的請求數（分母）。
2. `fable_refusals_total{model, category}`：`stop_reason == "refusal"` 的次數，category 取自 `stop_details.category`，沒有類別時填 `"null"`（分子）。

（備援比率可以再加第三個 counter `fable_fallback_served_total{fallback_model}`，用同樣的方式寫規則。）

```yaml
groups:
  - name: fable-refusal-drift
    rules:
      # 每個類別的拒答比率（近 1 天）
      - record: category:fable_refusal_ratio:1d
        expr: |
          sum by (category) (increase(fable_refusals_total[1d]))
            / ignoring(category) group_left()
          sum(increase(fable_requests_total[1d]))

      - alert: FableRefusalRatioDrift
        # 比上週同一時間高出 1 個百分點以上，或是上週的 2 倍以上；
        # 並且今天至少有 100 筆請求，避免極低流量時比率暴衝誤報
        expr: |
          (
              (category:fable_refusal_ratio:1d - category:fable_refusal_ratio:1d offset 7d) >= 0.01
            or
              (category:fable_refusal_ratio:1d >= 2 * category:fable_refusal_ratio:1d offset 7d)
          )
          and on() (sum(increase(fable_requests_total[1d])) >= 100)
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "拒答比率漂移：{{ $labels.category }}"
          description: "{{ $labels.category }} 的拒答比率目前是 {{ $value | humanizePercentage }}，比上週高出 1 個百分點以上或 2 倍以上。先查這個類別的提示詞前綴。"
```

草稿的限制：
- 某個類別上週完全沒出現時，`offset 7d` 那一側沒有時間序列，兩個比較條件都會對不上而不告警。要補一條「上週不存在、本週比率 ≥ 1%」的規則（例如用 `unless` 搭配 `offset 7d`），或在程式啟動時就把四個類別的 counter 都初始化成 0。
- 至少 100 筆的門檻和 `for: 1h` 是為了壓低低流量時的噪音，數字要依實際流量調整。
