呼叫 Fable 5 時不要送 temperature、top_p、top_k；API 會直接回 400。

細節：
- 這三個取樣參數在 Fable 5 不支援，請求在送出前就該移除，不是靠重試解決。
- 掃描器的 FS-02（warn，config 類）會在 JSON 設定裡抓到這三個鍵；migration_linter 也把它們列為要刪的欄位。
- 深度改用 output_config.effort 控制（low／medium／xhigh）。
- 為什麼重要：夜間迴圈若沿用舊模型的設定檔，每一輪都會 400，驗證永遠跑不到。

provenance：fable5/fable_scanner/rules.py 第 119～127 行（FS-02）；fable5/migration/migration_linter.py 第 16 行 SAMPLING_PARAMS；fable5/README.md 最後一節 API 注意事項第 2 點。
