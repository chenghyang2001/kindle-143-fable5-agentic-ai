# A 版回答（system 7 字元）

---

問題不是「偶爾」少算，而是**特定格式的行每次都會被靜默丟掉**。probe.txt 已經把原因找出來了，根因在那條 regex：

```python
PATTERN = re.compile(r"^(\S+) (\S+) severity=(\d) user=(\S+) (.*)$")
```

## 三個會漏掉的情況

| 行 | 內容特徵 | 為何不匹配 |
|---|---|---|
| 4 | `severity=10` | `(\d)` 只吃**一位數**，兩位數以上全掛 |
| 6 | 缺 `user=` 欄位 | 整段 `user=(\S+)` 對不上 |
| 8 | `user=`（空值） | `(\S+)` 要求至少一個非空白字元 |

最糟的是第 4、6 行是 severity 10 和 9——**最高危的告警反而最容易被吃掉**，對 SIEM 來說是很危險的盲點。

## 修正後的版本

```python
import re

# severity 改成 \d+；user 允許空值用 (\S*)；對缺欄位的行改走寬鬆解析
PATTERN = re.compile(r"^(\S+) (\S+) severity=(\d+) user=(\S*) ?(.*)$")


def parse_line(line):
    m = PATTERN.match(line)
    if not m:
        return {"raw": line, "parse_error": "no_match"}  # 不要靜默丟
    ts, host, sev, user, msg = m.groups()
    return {
        "ts": ts,
        "host": host,
        "severity": int(sev),
        "user": user or None,   # 空 user 記成 None 而非丟棄
        "msg": msg,
    }


def parse_log(path):
    events, errors = [], []
    with open(path, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            e = parse_line(line.rstrip("\n"))
            if "parse_error" in e:
                e["lineno"] = lineno
                errors.append(e)       # 保留，別吞掉
            events.append(e)
    return events, errors
```

## 關鍵改動

1. **`(\d)` → `(\d+)`**：讓 severity 10、100 都能解析（最重要的修正）。
2. **`user=(\S+)` → `user=(\S*)`**：接受空的 user 欄位。
3. **別靜默吞行**：原本 `return None` 讓異常行無聲消失，這是你「不知道少算」的根本原因。改成回傳帶 `parse_error` 的記錄並保留行號，上層就能告警或送 dead-letter。
4. **用 `with open(...)`**：原本的 `open()` 沒關檔案。

## 建議

- 對第 6 行那種缺欄位的格式，建議確認日誌來源——可能是**不同的 log schema 混在同一個檔**，長遠解法是先分流再用對應的 parser，而不是靠單一 regex 硬吃。
- 補一組 unit test，把這 10 行當 fixture，確保未來改 regex 不會再回歸。

要我幫你把測試也補上嗎？
