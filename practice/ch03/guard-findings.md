# 記憶工具處理器防護檢查結果

受測：`fable5/memory/memory_tool_handler.py`（沒有修改）。`h.ROOT` 改到 `ch03/memories`。原版輸出在 `ch03/guard-results.txt`，修正版輸出在 `ch03/guard-results-fixed.txt`。

自帶檢查 `python memory/memory_tool_handler.py` → `ok: traversal blocked`。

## 結果總表

| # | 情境 | 原版 | 修正版 |
| --- | --- | --- | --- |
| 1 | 正常 create → view | ✅ 讀回原內容 | ✅ |
| 2 | `/memories/../../secret.txt` | ✅ ValueError 擋下 | ✅ 回 error 字串 |
| 3 | `C:\Windows\win.ini`（view） | ✅ ValueError 擋下 | ✅ 回 error 字串 |
| 4 | create 10,667 個中文字（32,001 bytes） | ✅ 拒絕、不寫檔 | ✅ |
| 5 | str_replace 換成超大字串 | ❌ 寫入成功，檔案 32,003 bytes | ✅ 拒絕，檔案維持 12 bytes |
| 6 | insert 超大字串 | ❌ 寫入成功，檔案 32,025 bytes | ✅ 拒絕，檔案維持 20 bytes |
| 7 | rename 到 `/memories/../outside.md` | ✅ ValueError 擋下，外面沒有檔 | ✅ |
| 8 | （額外）31,990 bytes、15,995 個換行的內容 | ❌ 磁碟上 47,985 bytes | ✅ 磁碟上 31,990 bytes |

原版 5/8 符合，修正版 8/8 符合。

## 中文字數計算

上限 32,000 bytes ÷ 3 bytes／字 = 10,666.67。所以 10,666 字（31,998 bytes）還在上限內，**10,667 字（32,001 bytes）就超過**。

## 有效的防護

- **路徑逃逸**（情境 2、7）：`_resolve()` 先 `resolve()` 消掉 `..`，再確認結果在 ROOT 底下。rename 的目的地也走 `_resolve()`，所以搬不出去。
- **Windows 絕對路徑**（情境 3）：`ROOT / "C:\Windows\win.ini"` 在 Windows 上會被 pathlib 換成那個絕對路徑，`resolve()` 後不在 ROOT 底下，所以被擋。但這是「剛好被包含檢查接住」，不是刻意的設計。
- **create 的大小上限**（情境 4）：以 UTF-8 bytes 計算，中文不會被當成 1 字 1 byte 而漏網。

## 繞過或不符合預期的地方

1. **大小上限只套在 create**（情境 5、6）：str_replace 和 insert 直接寫回，完全沒有檢查。模型只要先建一個小檔，再用 str_replace 或 insert 灌內容，就能讓檔案無限長大，等於上限形同虛設。
2. **換行膨脹**（情境 8）：檢查的是 `text.encode()` 的長度，但 `write_text()` 在 Windows 用文字模式寫，每個 `\n` 會變成 `\r\n`。15,995 個換行讓磁碟上多了將近 16,000 bytes（47,985 bytes，是上限的 1.5 倍）。情境 5 的 32,003 bytes 也是這樣：32,001＋換行轉成 CRLF 的 2 bytes。
3. **擋下時是丟例外，不是回 tool_result**：情境 2、3、7 都是 `ValueError` 直接往外拋。實際迴圈裡如果沒有包 try，一次惡意路徑就會讓整個代理崩掉；模型也拿不到「為什麼被拒」的回饋。
4. **前綴比對太鬆**：`removeprefix("/memories")` 讓 `/memoriesX/a` 變成 `X/a`。這不會逃出根目錄，但會接受一個格式不對的路徑，不是使用者預期的行為。
5. **docstring 說的 provenance 要求並沒有實作**：程式碼裡沒有任何地方檢查寫入內容是否附出處行。
6. 次要：delete 對不存在的檔也回 `deleted`；rename 會覆蓋（或在 Windows 上因為目的地已存在而丟例外）；insert_line 沒檢查範圍。

## 建議怎麼補（已在 `ch03/handler_fixed.py` 示範並重跑證明）

1. 抽出一個 `_write_capped()`，create／str_replace／insert 都用它，**檢查最終內容**而不是輸入片段。
2. 用 `write_bytes(text.encode("utf-8"))` 寫檔、`read_bytes().decode()` 讀檔，讓磁碟大小等於檢查時的大小（或用 `write_text(..., newline="")`）。
3. 前綴嚴格比對 `/memories` 或 `/memories/`，其他一律拒絕。
4. `handle()` 外層把 `ValueError`／`OSError`／`KeyError` 轉成 `error: ...` 回給模型。
5. rename 遇到目的地已存在就拒絕；insert_line 檢查範圍；delete 找不到檔就回 error。
6. 尚未示範：provenance 檢查（例如要求最後一行以 `provenance:` 開頭），留給後續練習。
