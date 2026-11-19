# 回答：新版 system_prompt.md

- 任務：CI 的 build 失敗了，錯誤是 ModuleNotFoundError: No module named 'yaml'，請處理。
- model：claude-fable-5（經 claude -p 轉接層）

---

我先檢查了目前的工作目錄，結果發現無法開始診斷：

## 已確認的事實

- 目前的工作目錄 `C:\Users\USER\AppData\Local\Temp\k143-cli-cwd` 是**空的**，裡面沒有任何專案程式碼、CI 設定檔或依賴清單。這是我實際列出目錄內容確認的。
- 因此我目前沒有任何可以檢查的檔案，也沒有 CI 的實際日誌可以比對。

## 推測（尚未驗證）

`ModuleNotFoundError: No module named 'yaml'` 這類錯誤，最常見的原因是：

1. 程式碼裡有 `import yaml`，但提供這個模組的套件 **PyYAML** 沒有列在依賴清單（例如 `requirements.txt`、`pyproject.toml` 或 `setup.py`）裡。本機能跑通常是因為開發者曾手動裝過。
2. CI 的安裝步驟漏掉了安裝依賴，或裝錯了虛擬環境／Python 版本。
3. 比較少見：CI 快取壞掉，或某個間接依賴最近不再附帶 PyYAML。

對應的最小修正通常是在依賴清單加上一行 `PyYAML`（並視專案慣例鎖定版本），不需要動其他程式碼或 CI 設定。但在看到實際的程式碼和 CI 日誌之前，這只是推測。

## 我需要的資訊

請提供以下任一項，我就能實際驗證並給出確定的修正建議：

1. **專案的路徑**——程式碼在這台機器的哪個目錄？目前這個暫存目錄是空的。
2. **CI 失敗的完整日誌**——特別是依賴安裝那一段的輸出，以及錯誤的完整堆疊追蹤（哪個檔案的哪一行 `import yaml` 失敗）。
3. 專案的依賴清單檔案內容（`requirements.txt` 或 `pyproject.toml`）。

拿到之後我會先完成診斷並提出最小修正方案；實際修改檔案前我也會先跟你確認。
