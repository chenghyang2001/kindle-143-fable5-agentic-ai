# K143《用 Claude Fable 5 與 Mythos 5 打造代理式 AI 工程》範例程式碼＋提示詞＋技能庫演練

Ken Huang 著。全書 6 個 Part、18 章：從 Fable 5／Mythos 5 帶來的改變與 Harness 架構、迴圈工程、記憶工程，到昂貴規劃廉價建置的十個資安專案、Fable Scanner、11 個原生技能，再深入遷移、拒答、備援、effort、思考重放、快取、提示注入、工具投毒、備援盲區、拒答監控、回歸測試，最後收在 CISO 上線閘門。
書附範例程式碼是作者公開的 [kenhuangus/fable5](https://github.com/kenhuangus/fable5)（MIT 授權）。

每章的練習由「教練」視窗送給「練習」視窗裡的 Claude，讓它實際操作書附範例：跑離線工具（scanner、linter、scope gate、記憶防護）、讀技能檔再套用、用模板寫系統提示詞、寫小測試，並透過轉接層真的跑需要模型的範例。

> 練習內容為依各章重點原創撰寫，不含書籍原文。

## 不用 API 金鑰：claude -p 轉接層

本機不設 `ANTHROPIC_API_KEY`（直接打 API 會扣 API Credits）。範例中呼叫 Anthropic API 的地方，改由 `practice/claude_cli_client.py` 冒充 `anthropic` SDK，內部呼叫 Claude Code 無頭模式 `claude -p --output-format json`（走 Max 訂閱額度）。範例原始碼一行都不改：

```bash
cd practice
PYTHONUTF8=1 python run_with_cli.py fable5/projects/03_cost_dashboard/cost_dashboard.py
PYTHONUTF8=1 python run_with_cli.py -m fable_scanner canary run
```

轉接層會從子程序環境移除金鑰與巢狀 session 變數、有逾時與單一行程呼叫上限，並可把每次呼叫寫成 fable_scanner monitor 讀得懂的 JSONL。effort 會轉成 `claude -p --effort`；伺服器端 web_search 降級為 Claude Code WebSearch；max_tokens、temperature、thinking、fallbacks 等 API 專屬參數忽略。詳見 `practice/CLAUDE.md`。

## 結構

```
prompts/chNN.md              各章練習：章節重點、作者做過的實驗、練習提示詞、觀察重點、教練解說要點
code/fable5/                 書附範例原檔（作者公開，MIT）
practice/fable5/             練習用副本（練習不可修改）
practice/claude_cli_client.py  anthropic SDK → claude -p 轉接層
practice/run_with_cli.py     不改原始碼、透過轉接層執行範例的入口
practice/chNN/               練習產出
teaching/drill.json          章節清單
teaching/DRILL-PROMPT.md     教練開場提示詞
teaching/HANDOFF.md          演練進度表
```

| 章 | 主題 | 練習數 |
| --- | --- | --- |
| ch01 | 改變了什麼：Fable 5、Mythos 5 與 Harness | 2 |
| ch02 | 迴圈工程 | 2 |
| ch03 | 記憶工程 | 2 |
| ch04 | 昂貴規劃，廉價建置：安全專案組合 | 2 |
| ch05 | Fable Scanner：讓每份提示詞保持 Fable 原生 | 2 |
| ch06 | 11 個 Fable／Mythos 原生代理技能 | 3 |
| ch07 | 把生產機隊從 Opus 4.8 遷移過來 | 2 |
| ch08 | 錯誤處理器看不見的拒答 | 1 |
| ch09 | 備援切換時別付兩次錢 | 1 |
| ch10 | Effort 旋鈕就是成本旋鈕 | 1 |
| ch11 | 自適應思考與跨模型重放陷阱 | 1 |
| ch12 | 提示快取經濟學 | 1 |
| ch13 | Fable 5 代理的提示注入防禦 | 1 |
| ch14 | 工具投毒與 MCP 安全 | 1 |
| ch15 | 備援靜默失效的地方 | 1 |
| ch16 | 錯誤儀表板看不見的拒答 | 1 |
| ch17 | Fable 5 的回歸測試 | 1 |
| ch18 | 治理代理部署：CISO 控制地圖 | 1 |

第 11～16 章在書附 repo 沒有對應資料夾（thinking/、caching/、injection_defense/ 等未公開），練習改為依書中觀念自寫小工具與測試，並盡量串接 repo 既有的 linter、monitor、canary。

## 怎麼演練

HP1 螢幕 2（橫式）左右兩半：左半「K143 教練」、右半「K143 練習-全書」。
由主 Claude 開好兩個視窗並送出 `teaching/DRILL-PROMPT.md`，教練一章一章跑完，每章 commit＋push。
