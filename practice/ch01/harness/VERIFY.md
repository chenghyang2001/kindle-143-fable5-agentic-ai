# 驗證規格

## 驗證指令（實際可跑）

```bash
cd fable5 && PYTHONUTF8=1 python -m fable_scanner.test_scanner
```

工作目錄是 `practice/`。通過的判準：結束碼 0，且輸出最後一行是 `all checks passed`；每個測試一行 `ok  <測試名>`。

## 驗證子代理規格

- **角色**：獨立驗證者，在全新的上下文啟動。
- **輸入**：只有兩樣東西：上面那行指令的原始輸出（stdout＋stderr）與結束碼。不給執行者的敘述、計畫或自我評估。
- **做法**：自己重跑一次指令，比對自己拿到的輸出與交來的輸出；兩者不一致就以自己重跑的為準。
- **判定**：
  - PASS：結束碼 0、最後一行是 `all checks passed`、沒有任何 `FAIL`、`Traceback` 或 `AssertionError`。
  - FAIL：任何一項不符。
- **輸出格式**（只回這三行）：

```text
VERDICT: PASS 或 FAIL
EVIDENCE: <引用輸出中決定判定的那一行>
FAILED_TESTS: <失敗的測試名，用逗號分隔；沒有就寫 none>
```

- **不做的事**：不修程式、不提出修法、不評論執行者的說法。
