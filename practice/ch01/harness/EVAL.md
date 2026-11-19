# EVAL：第一次驗證執行（2026-11-19 09:31，本機 Windows 11）

## 驗證指令輸出

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner.test_scanner
ok  test_bad_prompt_trips_multiple_categories
ok  test_good_prompt_is_clean_of_errors
ok  test_config_trips_temperature_and_thinking_rules
ok  test_monitor_counts_refusals_and_fallback
all checks passed
（exit code 0）
```

## 這次執行的結果

4 個測試全部通過：壞提示詞會觸發多類規則、好提示詞沒有 error、設定檔會觸發 temperature 與 thinking 規則、監控能正確統計拒答與備援。結束碼 0，最後一行是 `all checks passed`。照 VERIFY.md 的判準，這一輪的判定是 PASS：

```text
VERDICT: PASS
EVIDENCE: all checks passed
FAILED_TESTS: none
```

這個判定是我照規格自己對輸出做的，不是另開一個全新上下文的驗證子代理給的；嚴格說來，「執行者不自己評分」這一條這次還沒有落實。

## 哪幾個模組被用上

| 模組 | 這次怎麼用上 |
| --- | --- |
| 邊界 | 只讀、只跑測試，沒有修改 `fable5/` 任何檔案；SYSTEM.md 把可改範圍限定在 `fable5/fable_scanner/` |
| 接地進度 | 上面的 PASS 直接引用指令輸出的最後一行與結束碼，不是口頭宣稱 |
| 自主性 | 指令照 VERIFY.md 直接跑，沒有停下來問；說要跑就真的跑並附原始輸出 |
| 白話摘要 | 本頁用完整句子寫結果、用到的模組、缺口 |
| 上下文平靜 | 沒有提剩餘空間；掃描結果證實 harness 內沒有倒數句子（FS-01 為 0） |
| 記憶 | INDEX.md＋3 個 lesson 已就位，每課都有 provenance 行；但這次測試全綠，沒有新 lesson 可寫 |

## 還缺什麼

1. **真正獨立的驗證子代理**：目前判定由執行者自己做，要改成在全新上下文啟動、只收指令輸出的子代理。
2. **排程**：還沒掛到 `/schedule` Routine 或 cron，所以「每晚」目前只是文件上的約定。
3. **失敗路徑沒演練過**：這次全綠，沒驗證過「同一失敗連續 3 次就停止並寫問題報告」這條停止條件，也沒試過寫入新 lesson 的流程。
4. **輪次額度與分支**：SYSTEM.md 寫了「本晚輪次額度」與「不推 main」，但沒定義額度數字與工作分支名稱。
5. **歷史紀錄**：EVAL.md 現在只有一次執行；每晚應該追加一筆（日期、結果、耗時），才看得出趨勢。

## 附錄：harness 掃描結果

```text
$ cd fable5 && PYTHONUTF8=1 python -m fable_scanner scan ../ch01/harness

summary: 0 file(s) with findings, 0 total (0 error-severity)
（exit code 0）
```

掃描器會遞迴收集 `.md`，這次涵蓋 SYSTEM.md、VERIFY.md、memory/INDEX.md 與 3 個 lesson（EVAL.md 是在掃描後才寫的，不在掃描範圍內）。0 個發現。
