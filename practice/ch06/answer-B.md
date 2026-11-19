# B 版回答（system 2942 字元）

---

問題找到了：不是「有時候」，是 `parse_line` 的 regex 太嚴格，不符合格式的行會回傳 `None` 被**無聲丟掉**——沒有例外、沒有警告、沒有計數。

## 證據（逐行比對 sample.log，共 10 行，parse_log 回傳 7 筆）

被丟掉的 3 行，各自撞到 `PATTERN = ^(\S+) (\S+) severity=(\d) user=(\S+) (.*)$` 的不同弱點：

| 行 | 內容 | 丟掉原因 |
|---|---|---|
| 4 | `severity=10 user=mallory impossible travel` | `(\d)` 只匹配**一位數**，severity=10 兩位數不符 |
| 6 | `severity=9 brute force from ...` | 該行根本沒有 `user=` 欄位 |
| 8 | `user= session token reused` | `user=` 後面是空的，`(\S+)` 要求至少一個非空白字元 |

更嚴重的是安全面向：被丟掉的三筆 severity 是 **[10, 9, 6]**——整份 log 裡最高的兩筆告警（impossible travel、brute force）正好都被吃掉了。這種解析器的失敗模式會優先丟掉最該看到的事件，因為攻擊相關的行往往格式最不規則。

## 根因總結

1. `(\d)` 應該是 `(\d+)` —— 這是純粹的 bug。
2. 格式嚴格綁死「每行都有 user= 且非空」，但真實 log 沒這個保證。
3. `parse_line` 回 `None` 時 `parse_log` 靜默跳過，零可觀測性，所以你只會察覺「好像少算幾行」。

## 建議修法（尚未動手，等你確認）

- `(\d)` → `(\d+)`。
- `user=(\S+)` 改成可選/可空，例如 `(?:user=(\S*))?`，user 缺失時記為 `None` 或 `"unknown"`。
- 最重要的：匹配失敗的行**不能無聲丟**——至少 log warning + 計數（parsed/dropped），或把原始行收進 `unparsed` 清單，讓丟行變成可見的訊號。
- 補幾個以這三行為案例的測試，鎖住行為。

要我直接改 `sample_target.py` 並補測試嗎？
