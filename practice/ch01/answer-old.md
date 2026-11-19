# 回答：舊版 bad_prompt.md

- 任務：CI 的 build 失敗了，錯誤是 ModuleNotFoundError: No module named 'yaml'，請處理。
- model：claude-fable-5（經 claude -p 轉接層）

---

我先逐步排查：

**步驟 1：確認工作目錄裡有什麼**

先看專案結構，找出 CI 設定與依賴宣告檔。
